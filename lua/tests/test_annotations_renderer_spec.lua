-- lua/tests/test_annotations_renderer_spec.lua
-- Behavioral coverage for blade-nav.features.annotations.renderer:
-- render -> extmarks set; re-render is idempotent (clear+set in the same
-- synchronous batch, so counts never grow); invalid buffer does not error;
-- show=false clears the namespace instead of rendering.

local renderer = require("blade-nav.features.annotations.renderer")
local values = require("blade-nav.features.annotations.values")

local function make_php_buffer(lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].filetype = "php"
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "php")
  if ok and parser then
    pcall(function()
      parser:parse()
    end)
  end
  return bufnr
end

local function extmark_count(bufnr)
  return #vim.api.nvim_buf_get_extmarks(bufnr, values.ns, 0, -1, {})
end

describe("annotations.renderer.render_buffer", function()
  before_each(function()
    values.invalidate_maps()
    renderer.set_config({ show = true, hl = "Comment", prefix = " -> ", max_len = 160 })
  end)

  it("renders extmarks in the values namespace for recognized calls (synchronous)", function()
    local bufnr = make_php_buffer({
      "<?php",
      "config('app.name');",
      "env('SOME_KEY');",
    })

    assert.equals(0, extmark_count(bufnr))

    renderer.render_buffer(bufnr, false)

    local marks = vim.api.nvim_buf_get_extmarks(bufnr, values.ns, 0, -1, { details = true })
    assert.is_true(#marks >= 2, "expected at least 2 extmarks, got " .. #marks)

    for _, mark in ipairs(marks) do
      local details = mark[4]
      assert.is_not_nil(details.virt_text)
      local text = details.virt_text[1][1]
      assert.is_true(text:find(" -> ", 1, true) ~= nil, "virt_text should include the configured prefix: " .. text)
    end

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("re-rendering the same buffer does not duplicate extmarks (clear+set in one batch)", function()
    local bufnr = make_php_buffer({
      "<?php",
      "config('app.one');",
      "config('app.two');",
    })

    renderer.render_buffer(bufnr, false)
    local first_count = extmark_count(bufnr)
    assert.is_true(first_count >= 2)

    renderer.render_buffer(bufnr, false)
    local second_count = extmark_count(bufnr)

    assert.equals(first_count, second_count)

    renderer.render_buffer(bufnr, false)
    local third_count = extmark_count(bufnr)
    assert.equals(first_count, third_count)

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("does not error when given an invalid/nonexistent buffer", function()
    assert.has_no.errors(function()
      renderer.render_buffer(999999, false)
    end)
  end)

  it("clears existing extmarks instead of rendering when config.show is false", function()
    local bufnr = make_php_buffer({
      "<?php",
      "config('app.three');",
    })

    renderer.render_buffer(bufnr, false)
    assert.is_true(extmark_count(bufnr) >= 1)

    renderer.set_config({ show = false, hl = "Comment", prefix = " -> ", max_len = 160 })
    renderer.render_buffer(bufnr, false)

    assert.equals(0, extmark_count(bufnr))

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)
