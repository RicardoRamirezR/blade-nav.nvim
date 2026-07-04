local M = {}

local ts = vim.treesitter
-- LuaJIT has no table.unpack; fall back to the global unpack (deprecated in Lua 5.2+).
---@diagnostic disable-next-line: deprecated
local unpack = table.unpack or unpack -- luacheck: ignore 143
local log = require("blade-nav.utils.log")
local textnode = require("blade-nav.core.textnode")
local lang_extractor = require("blade-nav.extractors.lang")
local values = require("blade-nav.features.annotations.values")

local find_enclosing_call = values.find_enclosing_call
local find_enclosing_js_call = values.find_enclosing_js_call
local format_value_for_display = values.format_value_for_display

local config = {}
local renderer = nil

local last_float = { win = nil, buf = nil }

function M.set_config(cfg)
  config = cfg
end

function M.set_renderer(r)
  renderer = r
end

local function find_value_in_tree(query, find_call_fn, root, bufnr, row, col)
  for _, match, _ in query:iter_matches(root, bufnr) do
    local info = values.extract_call_info(query, match, bufnr, find_call_fn)
    if info and info.callnode and ts.is_in_node_range(info.callnode, row, col) then
      return info
    end
  end

  return nil
end

local function value_info_at_cursor(bufnr)
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  row = row - 1
  local found

  local php_query = values.get_php_query()
  if php_query then
    values.for_each_php_tree(bufnr, function(root, b)
      if found then
        return
      end
      found = find_value_in_tree(php_query, find_enclosing_call, root, b, row, col)
    end)
  end

  if not found then
    local js_query = values.get_js_query()
    if js_query then
      values.for_each_js_tree(bufnr, function(root, b)
        if found then
          return
        end
        found = find_value_in_tree(js_query, find_enclosing_js_call, root, b, row, col)
      end)
    end
  end

  return found
end

local function value_at_cursor(bufnr)
  local info = value_info_at_cursor(bufnr)
  if not info then
    return nil
  end
  return format_value_for_display(info.key, info.default_value, info.kind)
end

local function extract_value_info_from_target(expr)
  if not expr or expr == "" then
    return nil
  end

  local query = values.get_php_query()
  if not query then
    return nil
  end

  local code = "<?php " .. expr .. ";"
  local ok, parser = pcall(vim.treesitter.get_string_parser, code, "php")
  if not ok or not parser then
    return nil
  end

  local tree = parser:parse()[1]
  if not tree then
    return nil
  end

  for _, match, _ in query:iter_matches(tree:root(), code) do
    local info = values.extract_call_info(query, match, code, find_enclosing_call)
    if info then
      return info
    end
  end

  return nil
end

local function format_value_from_target(expr)
  local info = extract_value_info_from_target(expr)
  if not info then
    return nil
  end
  return format_value_for_display(info.key, info.default_value, info.kind)
end

local function get_value_info_for_blade()
  local text = textnode.get_text_node()
  if not text or text == "" then
    return nil
  end
  return extract_value_info_from_target(text)
end

local function get_value_for_blade()
  local text = textnode.get_text_node()
  if not text or text == "" then
    return nil
  end
  return format_value_from_target(text)
end

local function show_translations_for_key(key)
  if not key or key == "" then
    return
  end

  local maps = lang_extractor.get_map_all_locales()
  local locales = vim.tbl_keys(maps)
  if #locales == 0 then
    vim.notify("No translation locales found", vim.log.levels.WARN)
    return
  end
  table.sort(locales)

  if last_float and type(last_float.win) == "number" and vim.api.nvim_win_is_valid(last_float.win) then
    local curwin = vim.api.nvim_get_current_win()
    if curwin == last_float.win then
      vim.api.nvim_win_close(last_float.win, true)
      last_float = { win = nil, buf = nil }
      return
    else
      vim.api.nvim_set_current_win(last_float.win)
      return
    end
  else
    last_float = { win = nil, buf = nil }
  end

  local lines = {}
  table.insert(lines, ("**Translations: `%s`**"):format(key))
  table.insert(lines, "")

  for _, locale in ipairs(locales) do
    local m = maps[locale] or {}
    local v = m[key]
    if v and v ~= "" then
      table.insert(lines, ("`%s` — %s"):format(locale, v))
    else
      table.insert(lines, ("`%s` — (missing)"):format(locale))
    end
  end

  local bufn, win = vim.lsp.util.open_floating_preview(lines, "markdown", {
    border = "rounded",
    max_width = math.floor(vim.o.columns * 0.6),
  })

  if not (bufn and win) then
    vim.notify("Failed to open translation window", vim.log.levels.ERROR)
    return
  end

  vim.bo[bufn].modifiable = false
  vim.bo[bufn].filetype = "markdown"
  vim.bo[bufn].buftype = "nofile"
  vim.bo[bufn].bufhidden = "wipe"

  vim.keymap.set("n", "q", "<cmd>close<CR>", { buffer = bufn, nowait = true, noremap = true, silent = true })
  vim.keymap.set("n", "<Esc>", "<cmd>close<CR>", { buffer = bufn, nowait = true, noremap = true, silent = true })

  last_float = { buf = bufn, win = win }
end

local function has_value_at_cursor(bufnr)
  local ft = vim.bo[bufnr].filetype
  if ft == "blade" then
    local blade_value = get_value_for_blade()
    if blade_value then
      return true
    end
    return value_at_cursor(bufnr) ~= nil
  end

  return value_at_cursor(bufnr) ~= nil
end

local function should_show_translations(info)
  return info and info.kind == "lang" and info.key
end

local function show_fallback_value(bufnr)
  local ft = vim.bo[bufnr].filetype
  local text = (ft == "blade" and get_value_for_blade()) or value_at_cursor(bufnr)
  if not text then
    return false
  end

  if last_float.win and vim.api.nvim_win_is_valid(last_float.win) then
    vim.api.nvim_set_current_win(last_float.win)
    return true
  end

  local bufn, win = vim.lsp.util.open_floating_preview({ text }, "markdown", { border = "rounded" })
  last_float = { buf = bufn, win = win }
  return true
end

-- Issue our own textDocument/hover request instead of calling
-- vim.lsp.buf.hover(): the built-in always vim.notify()s "No information
-- available" when the response is empty, with no way to opt out short of
-- monkey-patching vim.notify. Requesting directly lets us decide ourselves
-- whether to show the real hover float, fall back to our own value popup, or
-- (matching stock behavior) notify when neither is available.
local function request_lsp_hover(bufnr, has_fallback)
  local win = vim.api.nvim_get_current_win()
  local done = false

  local function handler(err, result)
    if done then
      return
    end
    done = true

    if not err then
      local contents = result and result.contents
      if contents then
        local lines = vim.lsp.util.convert_input_to_markdown_lines(contents)
        if #lines > 0 then
          local bufn, floatwin = vim.lsp.util.open_floating_preview(lines, "markdown", {
            border = "rounded",
            focus_id = "textDocument/hover",
          })
          last_float = { buf = bufn, win = floatwin }
          return
        end
      end
    else
      log.debug("LSP hover failed: %s", err.message or tostring(err))
    end

    if has_fallback then
      show_fallback_value(bufnr)
    else
      vim.notify("No information available", vim.log.levels.INFO)
    end
  end

  vim.lsp.buf_request(bufnr, "textDocument/hover", function(client)
    return vim.lsp.util.make_position_params(win, client.offset_encoding)
  end, handler, function() end)
end

function M.on_K()
  local bufnr = vim.api.nvim_get_current_buf()

  if config.show then
    renderer.render_buffer(bufnr, false)
  end

  local info
  local ft = vim.bo[bufnr].filetype
  if ft == "blade" then
    info = get_value_info_for_blade()
  else
    info = value_info_at_cursor(bufnr)
  end

  if should_show_translations(info) then
    show_translations_for_key(info.key)
    return
  end

  local clients = vim.lsp.get_clients({ bufnr = bufnr })

  local supports_hover = false
  for _, client in ipairs(clients) do
    if client.server_capabilities and client.server_capabilities.hoverProvider then
      supports_hover = true
      break
    end
  end

  if not supports_hover then
    show_fallback_value(bufnr)
    return
  end

  local has_fallback = has_value_at_cursor(bufnr)
  request_lsp_hover(bufnr, has_fallback)
end

return M
