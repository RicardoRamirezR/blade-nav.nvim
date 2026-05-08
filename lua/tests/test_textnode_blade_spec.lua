-- lua/tests/test_textnode_blade_spec.lua
-- Macro runner: test 4 positions per-line (col0, ^, $, rand)
--
local textnode = require("blade-nav.core.textnode")
local ts = vim.treesitter

local blade_fixture = [[
@extends('layouts.default')

@section('title')
    <title>Última actividad | Noah Club</title>
@endsection

@section('content')
    <x-input.checkbox />
    <livewire:pupa />
    <livewire:pupa-new />

    {!! $content !!}

    {{ route('pet-history.download') }}
    {{ to_route('recurrents.feed') }}
    {{ config('services.whatsapp.base_url') }}
    {{ config('services.whatsapp.token') }}
    @include('forms.followuph', [
        'id' => 1,
        'pet_id' => 1,
        'user_id' => 1,
        'catdog_followup' => company() == 10,
        'in_modal' => true,
    ])
    {{ env('WHATSAPP_TOKEN') }}
    @extends('layouts.default')
    @include('view.name')
    @include('view.name', ['status' => 'complete'])
    @includeIf('view.name', ['status' => 'complete'])
    @includeWhen($boolean, 'view.name', ['status' => 'complete'])
    @includeUnless($boolean, 'view.name', ['status' => 'complete'])
    @includeFirst(['custom.admin', 'admin'], ['status' => 'complete'])
    @each('view.name', $jobs, 'job')
    @each('view.name', $jobs, 'job', 'view.empty')
@endsection
]]

local expected_map = {
  [1] = { fname = "@extends", first_arg = "layouts.default", col0_expected = true },
  [2] = { fname = nil, first_arg = nil, col0_expected = nil },
  [8] = { fname = "component", first_arg = "input.checkbox", col0_expected = nil },
  [9] = { fname = "livewire", first_arg = "pupa", col0_expected = nil },
  [10] = { fname = "livewire", first_arg = "pupa-new", col0_expected = nil },
  [14] = { fname = "route", first_arg = "pet-history.download", col0_expected = nil },
  [15] = { fname = "to_route", first_arg = "recurrents.feed", col0_expected = nil },
  [16] = { fname = "config", first_arg = "services.whatsapp.base_url", col0_expected = nil },
  [17] = { fname = "config", first_arg = "services.whatsapp.token", col0_expected = nil },
  [18] = { fname = "@include", first_arg = "forms.followuph", col0_expected = nil },
  [19] = { fname = "@include", first_arg = "forms.followuph", col0_expected = true },
  [24] = { fname = "@include", first_arg = "forms.followuph", col0_expected = true },
  [25] = { fname = "env", first_arg = "WHATSAPP_TOKEN", col0_expected = nil },
  [26] = { fname = "@extends", first_arg = "layouts.default", col0_expected = nil },
  [27] = { fname = "@include", first_arg = "view.name", col0_expected = nil },
  [28] = { fname = "@include", first_arg = "view.name", col0_expected = nil },
  [29] = { fname = "@includeIf", first_arg = "view.name", col0_expected = nil },
  [30] = { fname = "@includeWhen", first_arg = "view.name", col0_expected = nil },
  [31] = { fname = "@includeUnless", first_arg = "view.name", col0_expected = nil },
  [32] = { fname = "@includeFirst", first_arg = { "custom.admin", "admin" }, col0_expected = nil },
  [33] = { fname = "@each", first_arg = { "view.name" }, col0_expected = nil },
  [34] = { fname = "@each", first_arg = { "view.name", "view.empty" }, col0_expected = nil },
  [35] = { fname = nil, first_arg = nil, col0_expected = nil },
}

local function prepare_buffer(ft, text)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(text, "\n"))
  vim.bo[bufnr].filetype = ft
  vim.api.nvim_buf_set_option(bufnr, "filetype", ft)
  vim.api.nvim_set_current_buf(bufnr)
  local ok, parser = pcall(ts.get_parser, bufnr, ft)
  if ok and parser then
    pcall(function()
      parser:parse()
    end)
  end
  return bufnr
end

local function last_non_blank_index(line)
  for i = #line, 1, -1 do
    if line:sub(i, i):match("%S") then
      return i - 1
    end
  end
  return 0
end

local function same(a, b)
  return vim.inspect(a) == vim.inspect(b)
end

describe("textnode macro runner full fixture 4 positions", function()
  local bufnr = prepare_buffer("blade", blade_fixture)

  for lnum, expected in pairs(expected_map) do
    it("validates " .. (expected.fname or "") .. " at line " .. lnum, function()
      local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ""

      local col0 = 0
      local first_non_blank = math.max(0, (line:find("%S") or 1) - 1)
      local last_index = last_non_blank_index(line)
      local rand_index
      if last_index - first_non_blank >= 2 then
        math.randomseed(lnum)
        rand_index = math.random(first_non_blank + 1, last_index - 1)
      else
        rand_index = first_non_blank
      end

      local positions = {
        { name = "col0", col = col0 },
        { name = "^", col = first_non_blank },
        { name = "$", col = last_index },
        { name = "rand", col = rand_index },
      }

      local col0_expected = nil
      if expected.col0_expected ~= nil then
        if expected.col0_expected == true then
          col0_expected = { fname = expected.fname, first_arg = expected.first_arg }
        else
          col0_expected = expected.col0_expected
        end
      end

      local function probe(row, col)
        vim.api.nvim_win_set_cursor(0, { row, col })
        local ok, parser = pcall(ts.get_parser, bufnr, vim.api.nvim_buf_get_option(bufnr, "filetype"))
        if ok and parser then
          pcall(function()
            parser:parse()
          end)
        end
        local full, fname, first_arg = textnode.get_text_node()
        return { full = full, fname = fname, first_arg = first_arg }
      end

      local res0 = probe(lnum, positions[1].col)
      if col0_expected == nil then
        assert.is_nil(
          res0.fname,
          string.format("line %d col0: expected nil fname but got %s", lnum, vim.inspect(res0.fname))
        )
        assert.is_nil(
          res0.first_arg,
          string.format("line %d col0: expected nil first_arg but got %s", lnum, vim.inspect(res0.first_arg))
        )
      else
        assert.is_true(
          same(res0.fname, col0_expected.fname),
          string.format(
            "line %d col0: fname mismatch (expected %s) got %s",
            lnum,
            vim.inspect(col0_expected.fname),
            vim.inspect(res0.fname)
          )
        )
        assert.is_true(
          same(res0.first_arg, col0_expected.first_arg),
          string.format(
            "line %d col0: first_arg mismatch (expected %s) got %s",
            lnum,
            vim.inspect(col0_expected.first_arg),
            vim.inspect(res0.first_arg)
          )
        )
      end

      for i = 2, 4 do
        local pos = positions[i]
        local res = probe(lnum, pos.col)
        local ok_fname = same(res.fname, expected.fname)
        local ok_first = same(res.first_arg, expected.first_arg)
        if not (ok_fname and ok_first) then
          local msg = {
            string.format("Line %d failed at position %s (col=%d)", lnum, pos.name, pos.col),
            string.format(
              "  expected fname=%s first_arg=%s",
              vim.inspect(expected.fname),
              vim.inspect(expected.first_arg)
            ),
            string.format(
              "  got      fname=%s first_arg=%s full=%s",
              vim.inspect(res.fname),
              vim.inspect(res.first_arg),
              vim.inspect(res.full)
            ),
            string.format("  line text: %s", vim.inspect(line)),
            string.format("  positions: %s", vim.inspect(positions)),
          }
          pcall(function()
            textnode.debug_nodes_at_cursor()
          end)
          assert.is_true(false, table.concat(msg, "\n"))
        end
      end
    end)
  end

  pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
end)
