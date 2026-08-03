-- lua/tests/test_integrations_cmp_spec.lua
-- Behavioral coverage for blade-nav.integrations.cmp's public contract:
-- source.complete(_, request, callback) given a buffer line + cursor,
-- returning items with correct newText, honoring close_tag_on_complete.
--
-- nvim-cmp itself is not installed in the test environment, so a minimal
-- fake "cmp" module is preloaded to let M.setup() run its real registration
-- path and hand us the real `source` table it builds internally.

local helpers = require("tests.helpers")
local fs = require("blade-nav.utils.fs")
local cache = require("blade-nav.utils.cache")
local config_module = require("blade-nav.core.config")

describe("integrations.cmp source.complete", function()
  local fixtures_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/fixtures"
  local orig_get_root_dir
  local laravel = require("blade-nav.utils.laravel")
  local orig_items_for_prefix = laravel.items_for_prefix

  local function install_fake_cmp()
    local captured_source
    package.loaded["cmp"] = nil
    package.loaded["cmp.config"] = nil
    package.preload["cmp"] = function()
      return {
        register_source = function(_, instance)
          captured_source = instance
        end,
        setup = { filetype = function() end },
        config = {
          sources = function(x)
            return x
          end,
        },
        get_config = function()
          return { sources = {} }
        end,
      }
    end
    return function()
      return captured_source
    end
  end

  local function setup_cmp_source(opts)
    package.loaded["blade-nav.integrations.cmp"] = nil
    local get_captured = install_fake_cmp()
    local cmp_integration = require("blade-nav.integrations.cmp")
    cmp_integration.setup(opts)
    return get_captured()
  end

  local function complete_sync(source, line, offset)
    local result
    local request = {
      context = {
        cursor_before_line = line,
        cursor = { line = 0, character = #line },
      },
      offset = offset,
    }
    source.complete(source, request, function(r)
      result = r
    end)
    return result
  end

  before_each(function()
    orig_get_root_dir = fs.get_root_dir
    fs.get_root_dir = function()
      return fixtures_dir
    end
    cache.clear()
    config_module.setup({ close_tag_on_complete = true })
  end)

  after_each(function()
    fs.get_root_dir = orig_get_root_dir
    laravel.items_for_prefix = orig_items_for_prefix
    package.preload["cmp"] = nil
    package.loaded["cmp"] = nil
  end)

  it("returns @include('welcome') with a full closing tag by default", function()
    helpers.with_buffer({ "    @include('" }, { filetype = "blade" }, function()
      local source = setup_cmp_source({ close_tag_on_complete = true })
      assert.is_not_nil(source, "expected cmp.register_source to have captured the blade-nav source")

      local line = "    @include('"
      local result = complete_sync(source, line, 5)

      assert.is_not_nil(result)
      assert.is_true(#result.items > 0)

      local found
      for _, item in ipairs(result.items) do
        if item.label == "@include('welcome')" then
          found = item
        end
      end
      assert.is_not_nil(found, vim.inspect(result.items))
      assert.equals("@include('welcome')", found.textEdit.newText)
    end)
  end)

  it("omits the closing tag when close_tag_on_complete = false", function()
    config_module.setup({ close_tag_on_complete = false })

    helpers.with_buffer({ "    @include('" }, { filetype = "blade" }, function()
      local source = setup_cmp_source({ close_tag_on_complete = false })
      assert.is_not_nil(source)

      local line = "    @include('"
      local result = complete_sync(source, line, 5)

      local found
      for _, item in ipairs(result.items) do
        if item.label == "@include('welcome')" then
          found = item
        end
      end
      assert.is_not_nil(found, vim.inspect(result.items))
      -- Label is stable; newText drops the trailing "')" when close_tag_on_complete=false.
      assert.equals("@include('welcome", found.textEdit.newText)
    end)
  end)

  it("returns component items for the <x- prefix", function()
    helpers.with_buffer({ "    <x-" }, { filetype = "blade" }, function()
      local source = setup_cmp_source({ close_tag_on_complete = true })

      local line = "    <x-"
      local result = complete_sync(source, line, 5)

      local found
      for _, item in ipairs(result.items) do
        if item.label == "<x-alert />" then
          found = item
        end
      end
      assert.is_not_nil(found, vim.inspect(result.items))
      assert.equals("<x-alert />", found.textEdit.newText)
    end)
  end)

  it("calls back exactly once with an empty item list when items_for_prefix throws", function()
    helpers.with_buffer({ "    @include('" }, { filetype = "blade" }, function()
      local source = setup_cmp_source({ close_tag_on_complete = true })
      assert.is_not_nil(source, "expected cmp.register_source to have captured the blade-nav source")

      laravel.items_for_prefix = function()
        error("simulated completion failure")
      end

      local calls = 0
      local result
      local line = "    @include('"
      source.complete(source, {
        context = {
          cursor_before_line = line,
          cursor = { line = 0, character = #line },
        },
        offset = 5,
      }, function(r)
        calls = calls + 1
        result = r
      end)

      laravel.items_for_prefix = orig_items_for_prefix

      assert.equals(1, calls, "the callback must be invoked exactly once even on error")
      assert.is_not_nil(result)
      assert.equals(0, #result.items)
      assert.equals(false, result.isIncomplete)
    end)
  end)
end)
