-- lua/tests/test_regression_core_spec.lua
-- Regression coverage for Wave-1 audit fixes in blade-nav.core.* and
-- blade-nav.loader (see .superpowers/sdd/task-7-brief.md).

local stub = require("luassert.stub")

local function clear_blade_nav_modules()
  for k in pairs(package.loaded) do
    if k:match("^blade%-nav") then
      package.loaded[k] = nil
    end
  end
end

describe("regression: core.config nil-safety before setup()", function()
  it("config.get(key) returns nil without error when called before setup() ever ran", function()
    clear_blade_nav_modules()
    local config = require("blade-nav.core.config")

    local ok, result = pcall(config.get, "anything")

    assert.is_true(ok, "config.get() raised an error before setup(): " .. tostring(result))
    assert.is_nil(result)
  end)
end)

describe("regression: textnode Config::get dead-target fix", function()
  it("target list stores 'Config::get' without trailing parens (old entry was 'Config::get()')", function()
    clear_blade_nav_modules()
    local textnode = require("blade-nav.core.textnode")

    local php_list = textnode.get_target_lists().php
    assert.is_true(vim.tbl_contains(php_list, "Config::get"))
    assert.is_false(vim.tbl_contains(php_list, "Config::get()"))
  end)

  it("climbs from a nested non-target call to the enclosing Config::get(...) (dead-target regression)", function()
    clear_blade_nav_modules()
    local textnode = require("blade-nav.core.textnode")
    local helpers = require("tests.helpers")

    -- Cursor sits on the nested `now()` call, which is not itself a target.
    -- extract_php must walk up and recognize the enclosing Config::get(...)
    -- via is_target(); with the old "Config::get()" (parens-included) list
    -- entry this comparison always fails and the walk-up silently returns
    -- the inner "now" call instead.
    helpers.with_buffer("<?php\nConfig::get('key', now());\n", { filetype = "php", cursor = { 2, 20 } }, function()
      local full, fname, first_arg = textnode.get_text_node()
      assert.equals("Config::get", fname)
      assert.equals("key", first_arg)
      assert.is_not_nil(full)
    end)
  end)
end)

describe("regression: loader bails out on a genuinely non-Laravel cwd", function()
  local tmpdir, root_dir_stub

  before_each(function()
    vim.g.blade_nav = nil
    vim.g.loaded_blade_nav = nil

    clear_blade_nav_modules()
    local fs = require("blade-nav.utils.fs")
    tmpdir = vim.uv.fs_mkdtemp("/tmp/blade-nav-nonlaravel-XXXXXX")
    assert.is_truthy(tmpdir)

    root_dir_stub = stub(fs, "get_root_dir").returns(tmpdir)
  end)

  after_each(function()
    root_dir_stub:revert()
    vim.uv.fs_rmdir(tmpdir)
  end)

  it("does not set vim.g.loaded_blade_nav for a real empty directory (real is_laravel_project, not mocked)", function()
    local loader = require("blade-nav.loader")
    loader.ftplugin_loader()

    assert.is_nil(vim.g.loaded_blade_nav)
  end)
end)
