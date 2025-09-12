local cmd = require("blade-nav.utils.cmd")
local fs = require("blade-nav.utils.fs")
local uv = vim.loop

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
    fs.command_exists = function(cmd)
      return cmd == "fd"
    end

    local files = fs.find_files(tmpdir, "blade.php")
    assert.is_truthy(files)
    assert.is_true(vim.tbl_contains(files, tmpdir .. "/views/home.blade.php"))
    assert.is_true(vim.tbl_contains(files, tmpdir .. "/views/about.blade.php"))
  end)

  it("finds files with find branch", function()
    fs.command_exists = function(_)
      return false
    end

    local files = fs.find_files(tmpdir, "blade.php")
    assert.is_truthy(files)
    assert.is_true(vim.tbl_contains(files, tmpdir .. "/views/home.blade.php"))
    assert.is_true(vim.tbl_contains(files, tmpdir .. "/views/about.blade.php"))
  end)

  it("respects exclude_dirs", function()
    fs.command_exists = function(cmd)
      return cmd == "fd"
    end

    local files = fs.find_files(tmpdir, "blade.php", { "exclude" })
    assert.is_truthy(files)
    for _, f in ipairs(files) do
      assert.is_falsy(f:match("secret.blade.php"))
    end
  end)
end)
