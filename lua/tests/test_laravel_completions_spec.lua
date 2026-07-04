-- lua/tests/test_laravel_completions_spec.lua
-- Behavioral coverage for blade-nav.utils.laravel.completions.items_for_prefix:
-- canonical completion items for view('), @extends('), <x-, <livewire: (and,
-- bonus, inertia(' using the previously-unused Admin/Index.vue + Settings.tsx
-- fixtures).
--
-- Fixture views live under lua/fixtures/resources/views/:
--   welcome.blade.php, admin/dashboard.blade.php,
--   components/alert.blade.php, livewire/counter.blade.php
-- Fixture inertia pages live under lua/fixtures/resources/js/Pages/:
--   Admin/Index.vue, Settings.tsx, Dashboard.vue

local fs = require("blade-nav.utils.fs")
local cache = require("blade-nav.utils.cache")
local config_module = require("blade-nav.core.config")
local completions = require("blade-nav.utils.laravel.completions")

describe("laravel.completions.items_for_prefix", function()
  local fixtures_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/fixtures"
  local orig_get_root_dir

  local function labels_of(items)
    local labels = {}
    for _, item in ipairs(items or {}) do
      table.insert(labels, item.label)
    end
    return labels
  end

  before_each(function()
    orig_get_root_dir = fs.get_root_dir
    fs.get_root_dir = function()
      return fixtures_dir
    end
    cache.clear()
    config_module.setup({})
  end)

  after_each(function()
    fs.get_root_dir = orig_get_root_dir
  end)

  it("returns view('...') items for the view( prefix in a php buffer", function()
    vim.bo.filetype = "php"

    local items = completions.items_for_prefix("    view('")
    assert.is_not_nil(items)

    local labels = labels_of(items)
    assert.is_true(vim.tbl_contains(labels, "view('welcome')"), vim.inspect(labels))
    assert.is_true(vim.tbl_contains(labels, "view('admin.dashboard')"), vim.inspect(labels))

    for _, item in ipairs(items) do
      assert.equals(item.label, item.new_text)
      assert.equals("view", item.kind)
    end
  end)

  it("returns @extends('...') items for the @extends( prefix in a blade buffer", function()
    vim.bo.filetype = "blade"

    local items = completions.items_for_prefix("    @extends('")
    assert.is_not_nil(items)

    local labels = labels_of(items)
    assert.is_true(vim.tbl_contains(labels, "@extends('welcome')"), vim.inspect(labels))
    assert.is_true(vim.tbl_contains(labels, "@extends('admin.dashboard')"), vim.inspect(labels))
  end)

  it("returns <x-...> component items for the <x- prefix in a blade buffer", function()
    vim.bo.filetype = "blade"

    local items = completions.items_for_prefix("    <x-")
    assert.is_not_nil(items)

    local labels = labels_of(items)
    assert.is_true(vim.tbl_contains(labels, "<x-alert />"), vim.inspect(labels))
    assert.equals("component", items[1].kind)
  end)

  it("returns <livewire:...> items for the <livewire: prefix in a blade buffer", function()
    vim.bo.filetype = "blade"

    local items = completions.items_for_prefix("    <livewire:")
    assert.is_not_nil(items)

    local labels = labels_of(items)
    assert.is_true(vim.tbl_contains(labels, "<livewire:counter />"), vim.inspect(labels))
    assert.equals("livewire", items[1].kind)
  end)

  it("returns inertia('...') items using the previously-unused Admin/Index.vue and Settings.tsx fixtures", function()
    vim.bo.filetype = "php"

    local items = completions.items_for_prefix("    inertia('")
    assert.is_not_nil(items)

    local labels = labels_of(items)
    assert.is_true(vim.tbl_contains(labels, "inertia('Admin.Index')"), vim.inspect(labels))
    assert.is_true(vim.tbl_contains(labels, "inertia('Settings')"), vim.inspect(labels))
  end)

  it("returns nil for empty or nil input", function()
    assert.is_nil(completions.items_for_prefix(nil))
    assert.is_nil(completions.items_for_prefix(""))
  end)

  it("returns nil when no known pattern is present before the cursor", function()
    vim.bo.filetype = "blade"
    assert.is_nil(completions.items_for_prefix("    just some prose"))
  end)
end)
