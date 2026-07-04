-- lua/tests/test_core_context_spec.lua
-- Behavioral coverage for blade-nav.core.context.create(): it captures the
-- buffer/filetype/line, and overlays target/first_arg (and the full node
-- text) from textnode.get_text_node() at the current cursor position -- or
-- falls back to the raw current line when nothing is extracted.

local helpers = require("tests.helpers")
local context_creator = require("blade-nav.core.context")

describe("core.context.create", function()
  it("captures buffer/filetype and extracts target/first_arg for an @include directive", function()
    helpers.with_buffer({ "@include('layouts.default')" }, { filetype = "blade" }, function(bufnr)
      vim.api.nvim_win_set_cursor(0, { 1, 4 })

      local ctx = context_creator.create()

      assert.equals(bufnr, ctx.buffer)
      assert.equals("blade", ctx.filetype)
      assert.equals("@include", ctx.target)
      assert.equals("layouts.default", ctx.first_arg)
      assert.equals("@include('layouts.default')", ctx.line)
    end)
  end)

  it("extracts target/first_arg for a <x-...> component tag", function()
    helpers.with_buffer({ "    <x-comp.button />" }, { filetype = "blade" }, function()
      local col = ("    <x-comp.button />"):find("%S") - 1
      vim.api.nvim_win_set_cursor(0, { 1, col })

      local ctx = context_creator.create()

      assert.equals("component", ctx.target)
      assert.equals("comp.button", ctx.first_arg)
    end)
  end)

  it("extracts target/first_arg for a PHP view() call", function()
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
      assert.equals("a.b", ctx.first_arg)
    end)
  end)

  it("falls back to the raw current line and nil target when nothing is extracted", function()
    helpers.with_buffer({ "just plain prose here, no directive" }, { filetype = "php" }, function()
      vim.api.nvim_win_set_cursor(0, { 1, 3 })

      local ctx = context_creator.create()

      assert.is_nil(ctx.target)
      assert.is_nil(ctx.first_arg)
      assert.equals("just plain prose here, no directive", ctx.line)
    end)
  end)
end)
