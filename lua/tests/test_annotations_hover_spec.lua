-- lua/tests/test_annotations_hover_spec.lua
-- Behavioral coverage for blade-nav.features.annotations.hover's on_K flow:
-- an LSP hover response renders in a float; with no hover-capable LSP client
-- the plugin value is shown instead; __()/trans() keys get a multi-locale
-- float; stale LSP responses (changedtick mismatch) are ignored; and with no
-- LSP hover and no plugin value the previously-captured buffer-local K (or
-- the built-in K) is replayed.
--
-- vim.lsp.get_clients / vim.lsp.buf_request / vim.lsp.util.open_floating_preview
-- are replaced with spies (saved/restored per test); the hover module is
-- re-required fresh per test so its last_float state never leaks between
-- tests.

local helpers = require("tests.helpers")

local values = require("blade-nav.features.annotations.values")
local config_extractor = require("blade-nav.extractors.config")
local lang_extractor = require("blade-nav.extractors.lang")

describe("annotations.hover.on_K", function()
  local hover
  local orig_get_clients
  local orig_buf_request
  local orig_open_preview
  local orig_feedkeys
  local orig_cfg_get_map
  local orig_lang_get_map_all
  local preview_calls

  local function fresh_hover()
    package.loaded["blade-nav.features.annotations.hover"] = nil
    hover = require("blade-nav.features.annotations.hover")
    hover.set_config({ show = false })
    return hover
  end

  -- Records open_floating_preview calls and returns a valid (buf, win) pair
  -- so the translation-float path does not take its error branch.
  local function install_preview_spy()
    preview_calls = {}
    vim.lsp.util.open_floating_preview = function(lines, filetype, opts)
      table.insert(preview_calls, { lines = lines, filetype = filetype, opts = opts })
      local bufn = vim.api.nvim_create_buf(false, true)
      return bufn, vim.api.nvim_get_current_win()
    end
  end

  local function stub_hover_capable_client()
    vim.lsp.get_clients = function()
      return { { server_capabilities = { hoverProvider = true }, offset_encoding = "utf-16" } }
    end
  end

  local function stub_no_clients()
    vim.lsp.get_clients = function()
      return {}
    end
  end

  before_each(function()
    orig_get_clients = vim.lsp.get_clients
    orig_buf_request = vim.lsp.buf_request
    orig_open_preview = vim.lsp.util.open_floating_preview
    orig_feedkeys = vim.api.nvim_feedkeys
    orig_cfg_get_map = config_extractor.get_map
    orig_lang_get_map_all = lang_extractor.get_map_all_locales
    values.invalidate_maps()
    fresh_hover()
  end)

  after_each(function()
    vim.lsp.get_clients = orig_get_clients
    vim.lsp.buf_request = orig_buf_request
    vim.lsp.util.open_floating_preview = orig_open_preview
    vim.api.nvim_feedkeys = orig_feedkeys
    config_extractor.get_map = orig_cfg_get_map
    lang_extractor.get_map_all_locales = orig_lang_get_map_all
    package.loaded["blade-nav.features.annotations.hover"] = nil
    values.invalidate_maps()
  end)

  it("renders the LSP hover response in a floating preview", function()
    install_preview_spy()
    stub_hover_capable_client()
    vim.lsp.buf_request = function(_, _, _, handler)
      handler(nil, { contents = { kind = "markdown", value = "**HoverDoc**" } })
    end

    helpers.with_buffer({ "<?php", "config('app.name');" }, { filetype = "php", cursor = { 2, 2 } }, function()
      hover.on_K()
    end)

    assert.equals(1, #preview_calls)
    assert.equals("markdown", preview_calls[1].filetype)
    local joined = table.concat(preview_calls[1].lines, "\n")
    assert.is_true(joined:find("HoverDoc", 1, true) ~= nil, "float should contain the LSP hover contents")
  end)

  it("falls back to the plugin value float when no LSP client supports hover", function()
    install_preview_spy()
    stub_no_clients()
    config_extractor.get_map = function()
      return { ["app.name"] = { kind = "scalar", text = "Demo App" } }
    end

    helpers.with_buffer({ "<?php", "config('app.name');" }, { filetype = "php", cursor = { 2, 2 } }, function()
      hover.on_K()
    end)

    assert.equals(1, #preview_calls)
    assert.equals("config(app.name) = Demo App", preview_calls[1].lines[1])
  end)

  it("shows a multi-locale float for __() keys", function()
    install_preview_spy()
    lang_extractor.get_map_all_locales = function()
      return {
        es = { ["messages.welcome"] = "Bienvenido" },
        en = { ["messages.welcome"] = "Welcome" },
      }
    end

    helpers.with_buffer({ "<?php", "__('messages.welcome');" }, { filetype = "php", cursor = { 2, 2 } }, function()
      hover.on_K()
    end)

    assert.equals(1, #preview_calls)
    local lines = preview_calls[1].lines
    assert.is_true(lines[1]:find("messages.welcome", 1, true) ~= nil)

    local joined = table.concat(lines, "\n")
    assert.is_true(joined:find("`en` — Welcome", 1, true) ~= nil, "missing en row: " .. joined)
    assert.is_true(joined:find("`es` — Bienvenido", 1, true) ~= nil, "missing es row: " .. joined)
    -- Locales are sorted: the en row comes before the es row.
    assert.is_true(joined:find("`en`", 1, true) < joined:find("`es`", 1, true))
  end)

  it("ignores an LSP response that arrives after the buffer changed (stale changedtick)", function()
    install_preview_spy()
    stub_hover_capable_client()
    local captured_handler
    vim.lsp.buf_request = function(_, _, _, handler)
      captured_handler = handler
    end

    helpers.with_buffer({ "<?php", "config('app.name');" }, { filetype = "php", cursor = { 2, 2 } }, function(bufnr)
      hover.on_K()
      assert.is_not_nil(captured_handler, "on_K should have issued an LSP hover request")

      -- The buffer changes before the response arrives.
      vim.api.nvim_buf_set_lines(bufnr, 1, 1, false, { "config('app.other');" })

      captured_handler(nil, { contents = { kind = "markdown", value = "**StaleDoc**" } })
    end)

    assert.equals(0, #preview_calls, "a stale hover response must not render anything")
  end)

  it("replays the captured previous buffer-local K when there is no LSP hover and no plugin value", function()
    install_preview_spy()
    stub_no_clients()

    local prev_called = false
    hover.set_prev_K_lookup(function()
      return {
        callback = function()
          prev_called = true
        end,
      }
    end)

    helpers.with_buffer({ "<?php", "$x = 1;" }, { filetype = "php" }, function()
      hover.on_K()
    end)

    assert.is_true(prev_called, "expected the captured previous K mapping to be invoked")
    assert.equals(0, #preview_calls)
  end)

  it("feeds the captured previous K rhs with noremap when it is a string mapping", function()
    install_preview_spy()
    stub_no_clients()

    local feed = {}
    vim.api.nvim_feedkeys = function(keys, mode, escape_ks)
      feed.keys = keys
      feed.mode = mode
      feed.escape_ks = escape_ks
    end

    hover.set_prev_K_lookup(function()
      return { rhs = "<Plug>(UserK)" }
    end)

    helpers.with_buffer({ "<?php", "$x = 1;" }, { filetype = "php" }, function()
      hover.on_K()
    end)

    assert.equals("n", feed.mode, "previous K rhs must be fed with noremap to avoid recursing into our own K")
    assert.is_true(feed.keys ~= nil and #feed.keys > 0)
    assert.equals(0, #preview_calls)
  end)

  it("falls back to the built-in K when no previous mapping exists", function()
    install_preview_spy()
    stub_no_clients()
    hover.set_prev_K_lookup(function()
      return nil
    end)

    helpers.with_buffer({ "<?php", "$x = 1;" }, { filetype = "php" }, function()
      assert.has_no.errors(function()
        hover.on_K()
      end)
    end)

    assert.equals(0, #preview_calls)
  end)
end)
