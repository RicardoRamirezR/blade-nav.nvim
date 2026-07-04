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

describe("annotations.renderer.render_buffer background/async path", function()
  before_each(function()
    values.invalidate_maps()
    renderer.clear_queue()
    renderer.set_config({ show = true, hl = "Comment", prefix = " -> ", max_len = 160 })
  end)

  after_each(function()
    -- Defensive cleanup so a slow/failed test never leaks a running timer or
    -- pending queue entries into the next `it` block (module state in
    -- renderer.lua is shared across all tests in this file/process).
    renderer.clear_queue()
    renderer.cleanup_timer()
  end)

  -- The queue/timer are driven by vim.schedule + a uv timer, which only run
  -- when the main loop is pumped. vim.wait polls the condition AND pumps the
  -- loop, so it both drives and observes the background processing.
  local function wait_for_queue_drain(timeout)
    return vim.wait(timeout or 2000, function()
      return #renderer.get_processing_queue() == 0
    end, 10)
  end

  local function sorted_marks(bufnr)
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, values.ns, 0, -1, { details = true })
    local out = {}
    for _, mark in ipairs(marks) do
      table.insert(out, { row = mark[2], col = mark[3], text = mark[4].virt_text[1][1] })
    end
    table.sort(out, function(a, b)
      if a.row ~= b.row then
        return a.row < b.row
      end
      return a.col < b.col
    end)
    return out
  end

  it("background render eventually produces the same extmarks as the synchronous path", function()
    local lines = {
      "<?php",
      "config('app.name');",
      "env('SOME_KEY');",
    }

    local sync_bufnr = make_php_buffer(lines)
    renderer.render_buffer(sync_bufnr, false)
    local expected = sorted_marks(sync_bufnr)
    assert.is_true(#expected >= 2, "sync fixture should produce at least 2 extmarks")

    local async_bufnr = make_php_buffer(lines)
    renderer.render_buffer(async_bufnr, true)

    assert.is_true(wait_for_queue_drain(2000), "background queue did not drain within timeout")

    local actual = sorted_marks(async_bufnr)
    assert.equals(#expected, #actual)
    for i, expected_mark in ipairs(expected) do
      assert.equals(expected_mark.row, actual[i].row)
      assert.equals(expected_mark.col, actual[i].col)
      assert.equals(expected_mark.text, actual[i].text)
    end

    vim.api.nvim_buf_delete(sync_bufnr, { force = true })
    vim.api.nvim_buf_delete(async_bufnr, { force = true })
  end)

  it("queueing the same buffer twice before processing runs does not duplicate extmarks", function()
    local lines = {
      "<?php",
      "config('app.one');",
      "config('app.two');",
    }

    -- Reference count from the synchronous path: what a single, non-duplicated
    -- render of this content should produce.
    local reference_bufnr = make_php_buffer(lines)
    renderer.render_buffer(reference_bufnr, false)
    local expected_count = extmark_count(reference_bufnr)
    assert.is_true(expected_count >= 2)

    local bufnr = make_php_buffer(lines)
    renderer.render_buffer(bufnr, true)
    renderer.render_buffer(bufnr, true)

    assert.equals(
      1,
      #renderer.get_processing_queue(),
      "queueing the same buffer twice should replace, not append, the pending entry"
    )

    assert.is_true(wait_for_queue_drain(2000), "background queue did not drain within timeout")

    assert.equals(expected_count, extmark_count(bufnr))

    vim.api.nvim_buf_delete(reference_bufnr, { force = true })
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("does not error and produces no extmarks when the buffer is deleted before the batch runs", function()
    local bufnr = make_php_buffer({
      "<?php",
      "config('app.deleted');",
    })

    assert.has_no.errors(function()
      renderer.render_buffer(bufnr, true)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    assert.is_true(wait_for_queue_drain(2000), "background queue did not drain within timeout")
    assert.is_false(vim.api.nvim_buf_is_valid(bufnr))
  end)

  it("leaves populated extmarks once the background render settles (no persistent blank state)", function()
    local bufnr = make_php_buffer({
      "<?php",
      "config('app.populated');",
    })

    renderer.render_buffer(bufnr, true)

    assert.is_true(wait_for_queue_drain(2000), "background queue did not drain within timeout")
    assert.is_true(extmark_count(bufnr) > 0)

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)
