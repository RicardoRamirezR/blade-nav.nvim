-- lua/tests/test_commands_spec.lua
-- Behavioral coverage for blade-nav.commands.install_artisan_command():
-- the :BladeNavInstallArtisanCommand user command writes a BladeNav.php copy
-- under app/Console/Commands/ relative to a (temp) project root, and
-- notifies an error when mkdir fails.
--
-- NOTE: one test below is marked `pending` -- it documents a real bug found
-- in already-"fixed" code (see the comment on that test for details) rather
-- than asserting broken behavior as if it were correct.

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
    -- get_blade_nav_filename() has a real path bug (see the pending test
    -- below), so we stub fs.read_file to succeed *only* for that exact
    -- source path, letting the rest of the real pipeline (mkdir, write,
    -- namespace rewrite, success notify) run unstubbed against tmpdir.
    local source_path = laravel.get_blade_nav_filename()
    local dummy_content = "<?php\n\nnamespace App\\Console\\Commands;\n\nclass BladeNav {}\n"

    fs.read_file = function(path)
      if path == source_path then
        return dummy_content, true
      end
      return orig_read_file(path)
    end

    vim.cmd("BladeNavInstallArtisanCommand")

    local dest_path = tmpdir .. "/app/Console/Commands/BladeNav.php"
    local written, _ = fs.read_file(dest_path)
    assert.is_not_nil(written, "expected BladeNav.php to be written to " .. dest_path)
    assert.equals(dummy_content, written)

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
    local source_path = laravel.get_blade_nav_filename()
    fs.read_file = function(path)
      if path == source_path then
        return "<?php\nnamespace App\\Console\\Commands;\n", true
      end
      return orig_read_file(path)
    end

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

  it("PENDING (real bug): end-to-end run without stubbing read_file never writes the file", function()
    -- BUG: laravel.get_blade_nav_filename() (lua/blade-nav/utils/laravel/init.lua)
    -- computes script_dir .. "/../../../BladeNav.php" from
    -- lua/blade-nav/utils/laravel/init.lua's own directory. That is only
    -- THREE ".." segments, which resolves to "<repo_root>/lua/BladeNav.php" --
    -- but the real BladeNav.php ships at "<repo_root>/BladeNav.php" (one
    -- level higher). fs.read_file() on the miscomputed path always fails, so
    -- :BladeNavInstallArtisanCommand can never succeed in real usage; it
    -- always hits the "Error reading file" branch instead of writing.
    -- Verified directly: realpath on the computed path reports "No such
    -- file or directory" from the actual repo root.
    -- This is pre-existing (present since v2.0.0, untouched by the Wave-1
    -- audit fixes), not something introduced by this test suite, and is not
    -- fixed here per task instructions (tests must not fix production code).
    pending("BUG: get_blade_nav_filename() resolves to <root>/lua/BladeNav.php instead of <root>/BladeNav.php, so fs.read_file(source) always fails and :BladeNavInstallArtisanCommand can never write the file in real usage")
  end)
end)
