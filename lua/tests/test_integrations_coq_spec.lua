-- lua/tests/test_integrations_coq_spec.lua
-- Behavioral coverage for blade-nav.integrations.coq_source's public
-- contract: _G.COQsources["blade-nav"].fn(args, callback), which slices
-- args.line at args.pos[2] (the cursor column) to find the completion
-- prefix, returns items with correct insertText, and honors
-- close_tag_on_complete.

local helpers = require("tests.helpers")
local fs = require("blade-nav.utils.fs")
local cache = require("blade-nav.utils.cache")
local config_module = require("blade-nav.core.config")

describe("integrations.coq_source fn(args, callback)", function()
  local fixtures_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/fixtures"
  local orig_get_root_dir
  local laravel = require("blade-nav.utils.laravel")
  local orig_items_for_prefix = laravel.items_for_prefix

  local function load_coq_source()
    _G.COQsources = nil
    package.loaded["blade-nav.integrations.coq_source"] = nil
    require("blade-nav.integrations.coq_source")
    return _G.COQsources["blade-nav"]
  end

  local function call_fn_sync(coq_source, args)
    local result = { called = false }
    coq_source.fn(args, function(r)
      result.called = true
      result.value = r
    end)
    return result
  end

  before_each(function()
    orig_get_root_dir = fs.get_root_dir
    fs.get_root_dir = function()
      return fixtures_dir
    end
    cache.clear()
  end)

  after_each(function()
    fs.get_root_dir = orig_get_root_dir
    laravel.items_for_prefix = orig_items_for_prefix
  end)

  it("slices the line at the cursor column and returns @include('welcome') by default", function()
    config_module.setup({ close_tag_on_complete = true })

    helpers.with_buffer({ "    @include('" }, { filetype = "blade" }, function()
      local coq_source = load_coq_source()
      local line = "    @include('"

      -- Trailing garbage after the cursor column must be ignored (proves the
      -- slice actually happens at args.pos[2], not just the whole line).
      local res = call_fn_sync(coq_source, { line = line .. "garbage", pos = { 1, #line } })

      assert.is_true(res.called)
      assert.is_not_nil(res.value)
      assert.equals(false, res.value.isIncomplete)

      local found
      for _, item in ipairs(res.value.items) do
        if item.label == "@include('welcome')" then
          found = item
        end
      end
      assert.is_not_nil(found, vim.inspect(res.value.items))
      assert.equals("@include('welcome')", found.insertText)
    end)
  end)

  it("omits the closing tag when close_tag_on_complete = false", function()
    config_module.setup({ close_tag_on_complete = false })

    helpers.with_buffer({ "    @include('" }, { filetype = "blade" }, function()
      local coq_source = load_coq_source()
      local line = "    @include('"

      local res = call_fn_sync(coq_source, { line = line, pos = { 1, #line } })

      local found
      for _, item in ipairs(res.value.items) do
        if item.label == "@include('welcome')" then
          found = item
        end
      end
      assert.is_not_nil(found, vim.inspect(res.value.items))
      assert.equals("@include('welcome", found.insertText)
    end)

    config_module.setup({ close_tag_on_complete = true })
  end)

  it("calls back with nil for a non blade/php filetype", function()
    helpers.with_buffer({ "    @include('" }, { filetype = "vue" }, function()
      local coq_source = load_coq_source()
      local res = call_fn_sync(coq_source, { line = "    @include('", pos = { 1, 14 } })

      assert.is_true(res.called)
      assert.is_nil(res.value)
    end)
  end)

  it("calls back with nil when the prefix does not match the keyword pattern", function()
    helpers.with_buffer({ "    just some prose" }, { filetype = "blade" }, function()
      local coq_source = load_coq_source()
      local res = call_fn_sync(coq_source, { line = "    just some prose", pos = { 1, 19 } })

      assert.is_true(res.called)
      assert.is_nil(res.value)
    end)
  end)

  it("calls back exactly once with no items when items_for_prefix throws", function()
    config_module.setup({ close_tag_on_complete = true })

    helpers.with_buffer({ "    @include('" }, { filetype = "blade" }, function()
      local coq_source = load_coq_source()

      laravel.items_for_prefix = function()
        error("simulated completion failure")
      end

      local calls = 0
      coq_source.fn({ line = "    @include('", pos = { 1, 14 } }, function(r)
        calls = calls + 1
        assert.is_nil(r, "coq's empty-result convention is callback() with no value")
      end)

      laravel.items_for_prefix = orig_items_for_prefix

      assert.equals(1, calls, "the callback must be invoked exactly once even on error")
    end)
  end)
end)
