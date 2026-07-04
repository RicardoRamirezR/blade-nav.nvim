-- lua/tests/test_commands_spec.lua
-- Behavioral coverage for blade-nav.commands.install_artisan_command():
-- the :BladeNavInstallArtisanCommand user command writes a BladeNav.php copy
-- under app/Console/Commands/ relative to a (temp) project root, and
-- notifies an error when mkdir fails. Also covers get_blade_nav_filename()'s
-- resolution of the bundled BladeNav.php at the plugin root (regression
-- coverage for a real path-math bug, see the comment on that test).

local fs = require("blade-nav.utils.fs")
local cache = require("blade-nav.utils.cache")
local laravel = require("blade-nav.utils.laravel")
local commands = require("blade-nav.commands")
local uv = vim.uv

describe("commands.install_artisan_command", function()
  local tmpdir
  local orig_get_root_dir
  local orig_read_file
  local orig_mkdir
  local orig_notify
  local notify_calls

  local function rmdir(path)
    local dir = uv.fs_scandir(path)
    if dir then
      while true do
        local name, t = uv.fs_scandir_next(dir)
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

  before_each(function()
    tmpdir = uv.fs_mkdtemp("/tmp/blade-nav-cmd-test-XXXXXX")
    assert.is_truthy(tmpdir)

    orig_get_root_dir = fs.get_root_dir
    fs.get_root_dir = function()
      return tmpdir
    end

    orig_read_file = fs.read_file
    orig_mkdir = vim.fn.mkdir

    cache.clear()

    notify_calls = {}
    orig_notify = vim.notify
    vim.notify = function(msg, level)
      table.insert(notify_calls, { msg = msg, level = level })
    end

    commands.install_artisan_command()
  end)

  after_each(function()
    fs.get_root_dir = orig_get_root_dir
    fs.read_file = orig_read_file
    vim.fn.mkdir = orig_mkdir
    vim.notify = orig_notify
    rmdir(tmpdir)
  end)

  it("writes a BladeNav.php copy under app/Console/Commands/ of the temp cwd", function()
    -- get_blade_nav_filename() now resolves to the real, bundled BladeNav.php,
    -- so the full pipeline (read source, mkdir, write, namespace rewrite,
    -- success notify) runs unstubbed against tmpdir.
    local source_path = laravel.get_blade_nav_filename()
    local source_content = orig_read_file(source_path)
    assert.is_not_nil(source_content, "expected the real BladeNav.php to be readable at " .. source_path)

    vim.cmd("BladeNavInstallArtisanCommand")

    local dest_path = tmpdir .. "/app/Console/Commands/BladeNav.php"
    local written, _ = fs.read_file(dest_path)
    assert.is_not_nil(written, "expected BladeNav.php to be written to " .. dest_path)
    assert.equals(source_content, written)

    local found_success = false
    for _, call in ipairs(notify_calls) do
      if call.msg:match("BladeNav%.php has been copied") then
        found_success = true
        assert.equals(vim.log.levels.INFO, call.level)
      end
    end
    assert.is_true(found_success, vim.inspect(notify_calls))
  end)

  it("notifies an error and does not write the file when mkdir fails", function()
    vim.fn.mkdir = function()
      error("EACCES: permission denied")
    end

    vim.cmd("BladeNavInstallArtisanCommand")

    local dest_path = tmpdir .. "/app/Console/Commands/BladeNav.php"
    assert.is_nil((fs.read_file(dest_path)))

    local found_error = false
    for _, call in ipairs(notify_calls) do
      if call.msg:match("Error creating directory") then
        found_error = true
        assert.equals(vim.log.levels.ERROR, call.level)
      end
    end
    assert.is_true(found_error, vim.inspect(notify_calls))
  end)

  it("get_blade_nav_filename() resolves to the real, readable BladeNav.php at the plugin root", function()
    -- Regression test for a real bug: get_blade_nav_filename() used to
    -- compute script_dir .. "/../../../BladeNav.php" (only three ".."
    -- segments), which resolved to "<repo_root>/lua/BladeNav.php" instead of
    -- the actual bundled file at "<repo_root>/BladeNav.php". That made
    -- fs.read_file(source) always fail, so :BladeNavInstallArtisanCommand
    -- could never succeed in real usage.
    local source_path = laravel.get_blade_nav_filename()

    local content, err = orig_read_file(source_path)
    assert.is_not_nil(
      content,
      "expected BladeNav.php to be readable at " .. source_path .. " (" .. tostring(err) .. ")"
    )
    assert.is_true(
      content:find("class BladeNav", 1, true) ~= nil,
      "expected BladeNav.php content to define class BladeNav"
    )
  end)
end)
