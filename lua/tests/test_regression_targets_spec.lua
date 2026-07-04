-- lua/tests/test_regression_targets_spec.lua
-- Regression coverage for Wave-1 audit fixes in blade-nav.targets.* and
-- blade-nav.extractors.lang (see .superpowers/sdd/task-7-brief.md).

local stub = require("luassert.stub")

local function clear_blade_nav_modules()
  for k in pairs(package.loaded) do
    if k:match("^blade%-nav") then
      package.loaded[k] = nil
    end
  end
end

local fixtures_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/fixtures"

describe("regression: targets/lang search pattern is crash-safe with special characters", function()
  local root_dir_stub

  before_each(function()
    clear_blade_nav_modules()
    local fs = require("blade-nav.utils.fs")
    root_dir_stub = stub(fs, "get_root_dir").returns(fixtures_dir)
  end)

  after_each(function()
    root_dir_stub:revert()
  end)

  it("resolve() does not throw for a key containing quotes and parens", function()
    local lang_target = require("blade-nav.targets.lang")
    local buf_before = vim.api.nvim_get_current_buf()

    local ok, err = pcall(lang_target.resolve, {
      type = "php",
      name = "messages.confirm('yes' or \"no\")",
    })

    assert.is_true(ok, "resolve() raised an error: " .. tostring(err))

    local buf_after = vim.api.nvim_get_current_buf()
    if buf_after ~= buf_before then
      vim.api.nvim_buf_delete(buf_after, { force = true })
    end
  end)
end)

describe("regression: targets/livewire kebab_to_pascal-based path building", function()
  local root_dir_stub, path_exists_stub, is_dir_stub

  before_each(function()
    clear_blade_nav_modules()
    local fs = require("blade-nav.utils.fs")
    root_dir_stub = stub(fs, "get_root_dir").returns("/fake/root")
    path_exists_stub = stub(fs, "path_exists").returns(false)
    is_dir_stub = stub(fs, "is_dir").returns(false)
  end)

  after_each(function()
    root_dir_stub:revert()
    path_exists_stub:revert()
    is_dir_stub:revert()
  end)

  it("builds app/Livewire/Admin/UserList.php for the dotted identifier 'admin.user-list'", function()
    local livewire = require("blade-nav.targets.livewire")
    local ctx = {
      line = "<livewire:admin.user-list />",
      target = "livewire",
      first_arg = "admin.user-list",
      filetype = "blade",
    }

    local target = livewire.get_target(ctx)
    assert.is_table(target)
    assert.is_true(vim.tbl_contains(target.choices, "/fake/root/app/Livewire/Admin/UserList.php"))
  end)
end)

describe("regression: targets/route line-scan resolves to_route()", function()
  it("recognizes to_route('dashboard') via the line-scan path (no context.target/first_arg)", function()
    clear_blade_nav_modules()
    local route = require("blade-nav.targets.route")

    local target = route.get_target({ line = "to_route('dashboard')" })

    assert.is_table(target)
    assert.equals("route", target.type)
    assert.equals("dashboard", target.name)
  end)
end)

describe("regression: extractors.lang finds keys under root lang/ (Laravel 9+ layout)", function()
  local root_dir_stub, lang_extractor

  before_each(function()
    clear_blade_nav_modules()
    local fs = require("blade-nav.utils.fs")
    local cache = require("blade-nav.utils.cache")
    cache.clear()
    root_dir_stub = stub(fs, "get_root_dir").returns(fixtures_dir)
    lang_extractor = require("blade-nav.extractors.lang")
  end)

  after_each(function()
    lang_extractor.stop_watcher()
    root_dir_stub:revert()
  end)

  it("returns 'messages.welcome' from lua/fixtures/lang/en/messages.php", function()
    local keys = lang_extractor.get_keys()
    assert.is_true(vim.tbl_contains(keys, "messages.welcome"))
  end)
end)
