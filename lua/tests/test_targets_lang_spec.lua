local lang = require("blade-nav.targets.lang")
local fs = require("blade-nav.utils.fs")
local choice = require("blade-nav.utils.choice")
local uv = vim.uv

describe("blade-nav.targets.lang", function()
  local tmpdir
  local old_get_root_dir
  local old_path_exists
  local old_project_relative
  local old_select_file
  local called_select_file

  before_each(function()
    tmpdir = uv.fs_mkdtemp("/tmp/blade-nav-lang-test-XXXXXX")
    assert.is_truthy(tmpdir)

    -- Mock fs.get_root_dir to point to the tmpdir
    old_get_root_dir = fs.get_root_dir
    fs.get_root_dir = function()
      return tmpdir
    end

    old_project_relative = fs.project_relative
    fs.project_relative = function(path)
      -- simulate relative path to the project root
      local escaped_tmpdir = tmpdir:gsub("([^%w])", "%%%1")
      local rel = path:gsub("^" .. escaped_tmpdir .. "/", "")
      return rel
    end

    old_path_exists = fs.path_exists
    fs.path_exists = function(p)
      local stat = uv.fs_stat(p)
      return stat ~= nil
    end

    called_select_file = {}
    old_select_file = choice.select_file
    choice.select_file = function(prompt, choices, cb)
      table.insert(called_select_file, { prompt = prompt, choices = choices })
      if cb then
        cb(tmpdir .. "/resources/lang/en.json")
      end
    end

    uv.fs_mkdir(tmpdir .. "/resources", 493)
    uv.fs_mkdir(tmpdir .. "/resources/lang", 493)
    uv.fs_mkdir(tmpdir .. "/resources/lang/es", 493)

    -- JSON locale
    local fd = assert(uv.fs_open(tmpdir .. "/resources/lang/en.json", "w", 420))
    uv.fs_write(fd, '{"welcome": "Hello"}', -1)
    uv.fs_close(fd)

    -- PHP locale (includes a nested array, like real Laravel lang files)
    fd = assert(uv.fs_open(tmpdir .. "/resources/lang/es/messages.php", "w", 420))
    uv.fs_write(fd, "<?php return ['greeting' => 'Hola', 'whatsapp' => ['token' => 'abc']];", -1)
    uv.fs_close(fd)
  end)

  after_each(function()
    fs.get_root_dir = old_get_root_dir
    fs.path_exists = old_path_exists
    fs.project_relative = old_project_relative
    choice.select_file = old_select_file

    -- Cleanup
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

  it("detects json target correctly", function()
    local t = lang.get_target({ target = "__", first_arg = "welcome" })
    assert.is_truthy(t)
    assert.equals("json", t.type)
    assert.equals("welcome", t.name)
  end)

  it("detects php target correctly", function()
    local t = lang.get_target({ target = "__", first_arg = "messages.greeting" })
    assert.is_truthy(t)
    assert.equals("php", t.type)
    assert.equals("messages.greeting", t.name)
  end)

  it("returns nil for invalid target", function()
    local t = lang.get_target({ target = "something", first_arg = "foo" })
    assert.is_nil(t)
  end)

  it("collects all locale files and calls choice.select_file with expected display values", function()
    local info = { type = "json", name = "welcome" }
    local ok = lang.resolve(info)
    assert.is_true(ok)
    assert.is_truthy(called_select_file[1])

    local choices = called_select_file[1].choices
    local found = false
    for _, c in ipairs(choices) do
      if c:match("^✓ resources/lang/en%.json$") then
        found = true
        break
      end
    end
    assert.is_true(found, "Expected ✓ entry for en.json but got:\n" .. table.concat(choices, "\n"))
  end)

  it("marks missing keys with ✗ in PHP files", function()
    local info = { type = "php", name = "messages.nonexistent" }
    local ok = lang.resolve(info)
    assert.is_true(ok)

    local choices = called_select_file[#called_select_file].choices
    local has_x = false
    for _, c in ipairs(choices) do
      if c:match("^✗ resources/lang/es/messages%.php$") then
        has_x = true
        break
      end
    end
    assert.is_true(has_x, "Expected ✗ entry for messages.php but got:\n" .. table.concat(choices, "\n"))
  end)

  it("marks nested PHP keys with ✓ (nested array traversal, not literal regex)", function()
    -- messages.php contains 'whatsapp' => ['token' => ...]: the dotted key
    -- whatsapp.token only exists via nested-array traversal.
    local info = { type = "php", name = "messages.whatsapp.token" }
    local ok = lang.resolve(info)
    assert.is_true(ok)

    local choices = called_select_file[#called_select_file].choices
    local has_check = false
    for _, c in ipairs(choices) do
      if c:match("^✓ resources/lang/es/messages%.php$") then
        has_check = true
        break
      end
    end
    assert.is_true(has_check, "Expected ✓ entry for messages.php but got:\n" .. table.concat(choices, "\n"))
  end)

  it("caches locale file list and decoded JSON across resolve calls", function()
    local cache = require("blade-nav.utils.cache")

    local ok = lang.resolve({ type = "json", name = "welcome" })
    assert.is_true(ok)

    assert.is_table(cache.get("targets_lang_locale_files:" .. tmpdir))
    assert.is_table(cache.get("targets_lang_json:" .. tmpdir .. "/resources/lang/en.json"))
  end)

  it("handles missing files gracefully", function()
    local info = { type = "json", name = "unknownkey" }

    -- erase lang directory
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
    rmdir(tmpdir .. "/resources/lang")

    local ok = lang.resolve(info)
    assert.is_false(ok)
  end)
end)
