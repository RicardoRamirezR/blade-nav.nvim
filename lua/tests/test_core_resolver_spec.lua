-- lua/tests/test_core_resolver_spec.lua
-- End-to-end coverage: real cursor -> textnode.get_text_node() (via
-- core.context.create()) -> core.resolver.resolve() handler routing, on
-- real blade/php fixture lines. Confirms exactly the right target handler
-- engages for @include('x'), <x-comp>, and view('a.b').

local helpers = require("tests.helpers")
local context_creator = require("blade-nav.core.context")
local resolver = require("blade-nav.core.resolver")
local targets = require("blade-nav.targets")

describe("core.resolver end-to-end handler routing", function()
  before_each(function()
    -- Fresh, fully-loaded handler set for every test (mirrors the pattern
    -- used by test_targets_lazy_spec.lua / test_targets_improvements_spec.lua).
    targets._handlers = {}
    targets._handler_order = {}
    targets._handler_modules = {}
    targets._failed_handlers = {}
    targets._handler_capabilities = {}
    targets.load_handlers("blade-nav.targets", "./lua/blade-nav/targets", { handlers = {} })
  end)

  it("routes @include('x') to the directive handler", function()
    helpers.with_buffer({ "@include('x')" }, { filetype = "blade" }, function()
      vim.api.nvim_win_set_cursor(0, { 1, 4 })

      local ctx = context_creator.create()
      assert.equals("@include", ctx.target)

      local result = resolver.resolve(ctx)
      assert.is_not_nil(result)
      assert.equals("directive", result.type)
      assert.equals("x", result.name)
    end)
  end)

  it("routes <x-comp> to the component handler", function()
    helpers.with_buffer({ "<x-comp />" }, { filetype = "blade" }, function()
      vim.api.nvim_win_set_cursor(0, { 1, 3 })

      local ctx = context_creator.create()
      assert.equals("component", ctx.target)

      local result = resolver.resolve(ctx)
      assert.is_not_nil(result)
      assert.equals("component", result.type)
      assert.equals("comp", result.name)
    end)
  end)

  it("routes view('a.b') to the view handler", function()
    helpers.with_buffer({
      "<?php",
      "function foo()",
      "{",
      "    view('a.b');",
      "}",
    }, { filetype = "php" }, function()
      vim.api.nvim_win_set_cursor(0, { 4, 4 })

      local ctx = context_creator.create()
      assert.equals("view", ctx.target)

      local result = resolver.resolve(ctx)
      assert.is_not_nil(result)
      assert.equals("view", result.type)
      assert.equals("a.b", result.name)
    end)
  end)

  it("resolves to nil when no handler matches (plain prose)", function()
    helpers.with_buffer({ "just plain prose here, no directive" }, { filetype = "php" }, function()
      vim.api.nvim_win_set_cursor(0, { 1, 3 })

      local ctx = context_creator.create()
      local result = resolver.resolve(ctx)
      assert.is_nil(result)
    end)
  end)
end)
