-- lua/tests/test_textnode_spec.lua
-- Integration tests for blade-nav.core.textnode using real tree-sitter parsing.
-- Comments and code in English.

local helpers = require("tests.helpers")
local textnode = require("blade-nav.core.textnode")

-- Helper to assert that textnode.get_text_node() returns expected values.
-- @param filetype: string (e.g. "blade")
-- @param cursor: { row, col } (1-based)
-- @param buf_text: string (e.g. "<livewire:pupa />")
-- @param expected_full: string|nil (e.g. "<livewire:pupa />")
-- @param expected_name: string|nil (e.g. "livewire")
-- @param expected_arg: string|nil (e.g. "pupa")
local function assert_text_node(filetype, cursor, buf_text, expected_full, expected_name, expected_arg)
  local opts = {
    cursor = cursor,
    filetype = filetype,
  }
  helpers.with_buffer(buf_text, opts, function()
    local full, name, arg = textnode.get_text_node()

    local pos = vim.api.nvim_win_get_cursor(0)
    local row = pos[1]

    local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1]

    assert.equals(expected_full, full, "full mismatch")
    assert.equals(expected_name, name, "name mismatch")
    assert.equals(expected_arg, arg, "arg mismatch")
  end)
end

describe("textnode integration (tree-sitter)", function()
  it("extracts component info from <livewire:pupa />", function()
    assert_text_node("blade", { 1, 15 }, [[<livewire:pupa />]], "<livewire:pupa />", "livewire", "pupa")
  end)

  it("extracts directive info from @extends('layouts.default')", function()
    assert_text_node(
      "blade",
      { 1, 12 },
      [[@extends('layouts.default')]],
      "@extends('layouts.default')",
      "@extends",
      "layouts.default"
    )
  end)

  it("handles nested multiple directives and selects correct one", function()
    assert_text_node(
      "blade",
      { 2, 15 },
      [[
      @extends('layouts.default')
      <livewire:pupa />
    ]],
      "<livewire:pupa />",
      "livewire",
      "pupa"
    )
  end)

  it("returns nil when cursor is outside any relevant node", function()
    helpers.with_buffer(
      [[
      <div>hello</div>
    ]],
      { filetype = "blade" },
      function()
        vim.api.nvim_win_set_cursor(0, { 1, 5 })
        local full, name, arg = textnode.get_text_node()

        assert.is_nil(full)
        assert.is_nil(name)
        assert.is_nil(arg)
      end
    )
  end)

  it("parses directive with different argument style", function()
    assert_text_node(
      "blade",
      { 1, 12 },
      [[@include("partials.header")]],
      '@include("partials.header")',
      "@include",
      "partials.header"
    )
  end)
end)

describe("textnode integration (cursor movement)", function()
  it("extracts component info from <livewire:pupa />", function()
    assert_text_node(
      "blade",
      { 4, 12 },
      [[
@extends('layouts.default')

@section('content')
    <livewire:pupa />
@endsection
    ]],
      "<livewire:pupa />",
      "livewire",
      "pupa"
    )
  end)

  it("extracts directive info from @include('view.name')", function()
    assert_text_node(
      "blade",
      { 1, 5 },
      [[
  @include('view.name')
      ]],
      "@include('view.name')",
      "@include",
      "view.name"
    )
  end)

  it("extracts config() call", function()
    assert_text_node(
      "blade",
      { 1, 2 },
      [[
  {{ config('services.whatsapp.base_url') }}
      ]],
      "config('services.whatsapp.base_url')",
      "config",
      "services.whatsapp.base_url"
    )
  end)

  it("extracts env() call", function()
    assert_text_node(
      "blade",
      { 1, 7 },
      [[
  {{ env('WHATSAPP_TOKEN') }}
      ]],
      "env('WHATSAPP_TOKEN')",
      "env",
      "WHATSAPP_TOKEN"
    )
  end)

  it("returns nil when cursor outside", function()
    assert_text_node(
      "blade",
      { 3, 1 },
      [[
  @extends('layouts.default')

  @section('content')
      <livewire:pupa />
  @endsection
      ]],
      nil
    )
  end)
end)
