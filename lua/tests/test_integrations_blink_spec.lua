-- lua/tests/test_integrations_blink_spec.lua
-- Behavioral coverage for blade-nav.integrations.blink's public contract:
-- Source:get_completions(ctx, callback), given a buffer line + cursor,
-- returning the blink.cmp.CompletionResponse shape with correct insertText,
-- honoring close_tag_on_complete.

local helpers = require("tests.helpers")
local fs = require("blade-nav.utils.fs")
local cache = require("blade-nav.utils.cache")
local config_module = require("blade-nav.core.config")

describe("integrations.blink Source:get_completions", function()
  local fixtures_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/fixtures"
  local orig_get_root_dir
  local laravel = require("blade-nav.utils.laravel")
  local orig_items_for_prefix = laravel.items_for_prefix

  before_each(function()
    orig_get_root_dir = fs.get_root_dir
    fs.get_root_dir = function()
      return fixtures_dir
    end
    cache.clear()

    package.loaded["blink.cmp.types"] = nil
    package.preload["blink.cmp.types"] = function()
      return { CompletionItemKind = { Reference = 1 } }
    end
  end)

  after_each(function()
    fs.get_root_dir = orig_get_root_dir
    laravel.items_for_prefix = orig_items_for_prefix
    package.preload["blink.cmp.types"] = nil
    package.loaded["blink.cmp.types"] = nil
  end)

  local function get_completions_sync(source, line, col)
    local result
    source:get_completions({ line = line, cursor = { 1, col } }, function(r)
      result = r
    end)
    return result
  end

  it("returns the CompletionResponse shape with @include('welcome') by default", function()
    config_module.setup({ close_tag_on_complete = true })

    helpers.with_buffer({ "    @include('" }, { filetype = "blade" }, function()
      local Source = require("blade-nav.integrations.blink")
      local instance = Source.new()

      local line = "    @include('"
      local result = get_completions_sync(instance, line, #line)

      assert.is_not_nil(result)
      assert.equals(false, result.is_incomplete_forward)
      assert.equals(false, result.is_incomplete_backward)
      assert.is_true(#result.items > 0)

      local found
      for _, item in ipairs(result.items) do
        if item.label == "@include('welcome')" then
          found = item
        end
      end
      assert.is_not_nil(found, vim.inspect(result.items))
      assert.equals("@include('welcome')", found.insertText)
      assert.equals(1, found.kind)
    end)
  end)

  it("omits the closing tag when close_tag_on_complete = false", function()
    config_module.setup({ close_tag_on_complete = false })

    helpers.with_buffer({ "    @include('" }, { filetype = "blade" }, function()
      local Source = require("blade-nav.integrations.blink")
      local instance = Source.new()

      local line = "    @include('"
      local result = get_completions_sync(instance, line, #line)

      local found
      for _, item in ipairs(result.items) do
        if item.label == "@include('welcome')" then
          found = item
        end
      end
      assert.is_not_nil(found, vim.inspect(result.items))
      assert.equals("@include('welcome", found.insertText)
    end)

    config_module.setup({ close_tag_on_complete = true })
  end)

  it("returns <livewire:counter /> for the <livewire: prefix", function()
    config_module.setup({ close_tag_on_complete = true })

    helpers.with_buffer({ "    <livewire:" }, { filetype = "blade" }, function()
      local Source = require("blade-nav.integrations.blink")
      local instance = Source.new()

      local line = "    <livewire:"
      local result = get_completions_sync(instance, line, #line)

      local found
      for _, item in ipairs(result.items) do
        if item.label == "<livewire:counter />" then
          found = item
        end
      end
      assert.is_not_nil(found, vim.inspect(result.items))
      assert.equals("<livewire:counter />", found.insertText)
    end)
  end)

  it("reports blade/php as enabled filetypes", function()
    local Source = require("blade-nav.integrations.blink")
    local instance = Source.new()

    helpers.with_buffer({ "" }, { filetype = "blade" }, function()
      assert.is_true(instance:enabled())
    end)
    helpers.with_buffer({ "" }, { filetype = "vue" }, function()
      assert.is_false(instance:enabled())
    end)
  end)

  it("calls back exactly once with an empty item list when items_for_prefix throws", function()
    config_module.setup({ close_tag_on_complete = true })

    helpers.with_buffer({ "    @include('" }, { filetype = "blade" }, function()
      local Source = require("blade-nav.integrations.blink")
      local instance = Source.new()

      laravel.items_for_prefix = function()
        error("simulated completion failure")
      end

      local calls = 0
      local result
      local line = "    @include('"
      instance:get_completions({ line = line, cursor = { 1, #line } }, function(r)
        calls = calls + 1
        result = r
      end)

      laravel.items_for_prefix = orig_items_for_prefix

      assert.equals(1, calls, "the callback must be invoked exactly once even on error")
      assert.is_not_nil(result)
      assert.equals(0, #result.items)
      assert.equals(false, result.is_incomplete_forward)
      assert.equals(false, result.is_incomplete_backward)
    end)
  end)
end)
