local cmd = require("blade-nav.utils.cmd")
local fs = require("blade-nav.utils.fs")
local cache = require("blade-nav.utils.cache")
local uv = vim.uv

describe("fs.get_root_dir", function()
  local real_execute_silent
  local tmpdir

  local function write_file(path, content)
    local fd = assert(uv.fs_open(path, "w", 420))
    uv.fs_write(fd, content, -1)
    uv.fs_close(fd)
  end

  local function mkdir(path)
    vim.fn.mkdir(path, "p", 493)
  end

  before_each(function()
    real_execute_silent = cmd.execute_silent
    cache.clear()
    tmpdir = uv.fs_mkdtemp("/tmp/blade-nav-root-test-XXXXXX")
    assert.is_truthy(tmpdir)
  end)

  after_each(function()
    cmd.execute_silent = real_execute_silent
    vim.api.nvim_buf_set_name(0, "")
    cache.clear()

    local function rmdir(path)
      local fd = uv.fs_scandir(path)
      if fd then
        while true do
          local name, t = uv.fs_scandir_next(fd)
          if not name then
            break
          end
          local full = path .. "/" .. name
          if t == "directory" then
            rmdir(full)
          else
            uv.fs_unlink(full)
          end
        end
      end
      uv.fs_rmdir(path)
    end
    rmdir(tmpdir)
  end)

  it("finds the nearest Laravel root (artisan marker) in a monorepo", function()
    mkdir(tmpdir .. "/monorepo/scripts/resources/views")
    write_file(tmpdir .. "/monorepo/scripts/artisan", "")
    vim.api.nvim_buf_set_name(0, tmpdir .. "/monorepo/scripts/resources/views/home.blade.php")

    assert.are.equal(tmpdir .. "/monorepo/scripts", fs.get_root_dir())
  end)

  it("does not reuse a cached Laravel root for a buffer outside the app", function()
    mkdir(tmpdir .. "/monorepo/scripts/resources/views")
    write_file(tmpdir .. "/monorepo/scripts/artisan", "")
    vim.api.nvim_buf_set_name(0, tmpdir .. "/monorepo/scripts/resources/views/home.blade.php")
    assert.are.equal(tmpdir .. "/monorepo/scripts", fs.get_root_dir())

    cmd.execute_silent = function(command, opts)
      if command[1] == "git" and command[2] == "rev-parse" then
        return tmpdir .. "/monorepo", true
      end
      return real_execute_silent(command, opts)
    end

    vim.api.nvim_buf_set_name(0, tmpdir .. "/monorepo/assets/app.css")
    assert.are.equal(tmpdir .. "/monorepo", fs.get_root_dir())
  end)

  it("falls back to the git root when no Laravel root is found", function()
    mkdir(tmpdir .. "/repo/app/Models")
    vim.api.nvim_buf_set_name(0, tmpdir .. "/repo/app/Models/User.php")

    cmd.execute_silent = function(command, opts)
      if command[1] == "git" and command[2] == "rev-parse" then
        return tmpdir .. "/repo", true
      end
      return real_execute_silent(command, opts)
    end

    assert.are.equal(tmpdir .. "/repo", fs.get_root_dir())
  end)

  it("falls back to cwd when neither Laravel root nor git root is found", function()
    mkdir(tmpdir .. "/plain")
    vim.api.nvim_buf_set_name(0, tmpdir .. "/plain/file.txt")

    cmd.execute_silent = function(command, opts)
      if command[1] == "git" and command[2] == "rev-parse" then
        return "fatal: not a git repository", false
      end
      return real_execute_silent(command, opts)
    end

    assert.are.equal(vim.fn.getcwd(), fs.get_root_dir())
  end)

  it("uses cwd as start when the buffer is unnamed", function()
    vim.api.nvim_buf_set_name(0, "")

    cmd.execute_silent = function(command, opts)
      if command[1] == "git" and command[2] == "rev-parse" then
        return "fatal: not a git repository", false
      end
      return real_execute_silent(command, opts)
    end

    assert.are.equal(vim.fn.getcwd(), fs.get_root_dir())
  end)
end)

describe("fs.find_files", function()
  local tmpdir
  local real_command_exists
  local real_get_root_dir
  local real_execute_silent

  before_each(function()
    -- Save the real implementations to restore later
    real_command_exists = fs.command_exists
    real_get_root_dir = fs.get_root_dir
    real_execute_silent = cmd.execute_silent

    -- Create a temporary directory with some blade.php files
    tmpdir = uv.fs_mkdtemp("/tmp/blade-nav-test-XXXXXX")
    assert.is_truthy(tmpdir)

    uv.fs_mkdir(tmpdir .. "/views", 493)
    local fd = assert(uv.fs_open(tmpdir .. "/views/home.blade.php", "w", 420))
    uv.fs_write(fd, "<div>home</div>", -1)
    uv.fs_close(fd)

    fd = assert(uv.fs_open(tmpdir .. "/views/about.blade.php", "w", 420))
    uv.fs_write(fd, "<div>about</div>", -1)
    uv.fs_close(fd)

    uv.fs_mkdir(tmpdir .. "/exclude", 493)
    fd = assert(uv.fs_open(tmpdir .. "/exclude/secret.blade.php", "w", 420))
    uv.fs_write(fd, "<div>secret</div>", -1)
    uv.fs_close(fd)

    -- Mock get_root_dir to return our temp directory
    fs.get_root_dir = function()
      return tmpdir
    end
  end)

  after_each(function()
    -- Restore original implementations
    fs.command_exists = real_command_exists
    fs.get_root_dir = real_get_root_dir
    cmd.execute_silent = real_execute_silent

    -- Recursive cleanup of temp directory
    local function rmdir(path)
      local fd = uv.fs_scandir(path)
      if fd then
        while true do
          local name, t = uv.fs_scandir_next(fd)
          if not name then
            break
          end
          local full = path .. "/" .. name
          if t == "directory" then
            rmdir(full)
          else
            uv.fs_unlink(full)
          end
        end
      end
      uv.fs_rmdir(path)
    end
    rmdir(tmpdir)
  end)

  it("finds files with fd branch", function()
    -- Only run this test when fd is actually available
    local has_fd = fs.command_exists("fd")
    if not has_fd then
      pending("fd not available")
      return
    end

    local files = fs.find_files(tmpdir, "blade.php")
    assert.is_truthy(files)
    assert.is_true(vim.tbl_contains(files, tmpdir .. "/views/home.blade.php"))
    assert.is_true(vim.tbl_contains(files, tmpdir .. "/views/about.blade.php"))
  end)

  it("finds files with find branch", function()
    -- Mock to force using find even if fd is available
    local real_command_exists = fs.command_exists
    fs.command_exists = function(cmd)
      if cmd == "fd" then
        return false
      end
      return real_command_exists(cmd)
    end

    local files = fs.find_files(tmpdir, "blade.php")
    assert.is_truthy(files)
    assert.is_true(vim.tbl_contains(files, tmpdir .. "/views/home.blade.php"))
    assert.is_true(vim.tbl_contains(files, tmpdir .. "/views/about.blade.php"))

    -- Restore original function
    fs.command_exists = real_command_exists
  end)

  it("respects exclude_dirs", function()
    local has_fd = fs.command_exists("fd")

    -- Mock to ensure consistent behavior regardless of fd availability
    local real_command_exists = fs.command_exists
    fs.command_exists = function(cmd)
      if has_fd then
        return cmd == "fd"
      else
        return false
      end
    end

    local files = fs.find_files(tmpdir, "blade.php", { "exclude" })
    assert.is_truthy(files)
    for _, f in ipairs(files) do
      assert.is_falsy(f:match("secret.blade.php"))
    end

    -- Restore original function
    fs.command_exists = real_command_exists
  end)
end)

describe("fs.project_relative", function()
  local real_get_root_dir

  before_each(function()
    real_get_root_dir = fs.get_root_dir
  end)

  after_each(function()
    fs.get_root_dir = real_get_root_dir
  end)

  it("returns a relative path when inside the project root", function()
    fs.get_root_dir = function()
      return "/tmp/myproject"
    end

    local path = "/tmp/myproject/resources/lang/en.json"
    local result = fs.project_relative(path)
    assert.are.equal("resources/lang/en.json", result)
  end)

  it("returns an absolute path when outside the project root", function()
    fs.get_root_dir = function()
      return "/tmp/myproject"
    end

    local result = fs.project_relative("/tmp/some-random-file.txt")
    -- macOS resolves /tmp to /private/tmp, so support both
    assert(
      result == "/tmp/some-random-file.txt" or result == "/private/tmp/some-random-file.txt",
      string.format("Unexpected path: %s", result)
    )
  end)

  it("handles empty or nil input gracefully", function()
    assert.are.equal("", fs.project_relative(""))
    assert.is_nil(fs.project_relative(nil))
  end)

  it("uses fs.get_root_dir when available", function()
    local called = false
    fs.get_root_dir = function()
      called = true
      return "/tmp/myproject"
    end

    fs.project_relative("/tmp/myproject/resources/lang/es/messages.php")
    assert.is_true(called)
  end)
end)
