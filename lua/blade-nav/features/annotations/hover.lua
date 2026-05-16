local M = {}

local uv = vim.loop
local ts = vim.treesitter
local unpack = table.unpack or unpack
local log = require("blade-nav.utils.log")
local textnode = require("blade-nav.core.textnode")
local lang_extractor = require("blade-nav.extractors.lang")
local values = require("blade-nav.features.annotations.values")

local PHP_CALLS_Q = values.PHP_CALLS_Q
local JS_CALLS_Q = values.JS_CALLS_Q
local for_each_php_tree = values.for_each_php_tree
local for_each_js_tree = values.for_each_js_tree
local find_enclosing_call = values.find_enclosing_call
local find_enclosing_js_call = values.find_enclosing_js_call
local format_value_for_display = values.format_value_for_display

local config = {}
local renderer = nil

local last_float = { win = nil, buf = nil }
local original_notify = vim.notify
local suppress_notify_until = 0

function M.set_config(cfg)
  config = cfg
end

function M.set_renderer(r)
  renderer = r
end

local function find_value_in_tree(query, find_call_fn, root, bufnr, row, col)
  for _, match, _ in query:iter_matches(root, bufnr) do
    local fn, method, key, callnode
    local default_value = nil

    for id, nodes in pairs(match) do
      local cap = query.captures[id]
      local node = nodes[1]
      local node_text = ts.get_node_text(node, bufnr)

      if cap == "fn_name" then
        fn = node_text
      elseif cap == "method" then
        method = node_text
      elseif cap == "key_str" then
        key = node_text
      elseif cap == "default_str" then
        default_value = node_text
      end

      callnode = callnode or find_call_fn(node)
    end

    if callnode and key then
      local sr, sc, er, ec = callnode:range()
      if row >= sr and row <= er and col >= sc and col <= ec then
        local kind = (fn == "env") and "env" or "config"
        if method and (method == "get" or method == "set") then
          kind = "config"
        end
        if fn == "__" or fn == "trans" then
          kind = "lang"
        end
        return {
          fn = fn,
          method = method,
          key = key,
          callnode = callnode,
          default_value = default_value,
          kind = kind,
        }
      end
    end
  end

  return nil
end

local function value_at_cursor(bufnr)
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  row = row - 1
  local found

  for_each_php_tree(bufnr, function(root, b)
    if found then
      return
    end
    found = find_value_in_tree(PHP_CALLS_Q, find_enclosing_call, root, b, row, col)
  end)

  if not found then
    for_each_js_tree(bufnr, function(root, b)
      if found then
        return
      end
      found = find_value_in_tree(JS_CALLS_Q, find_enclosing_js_call, root, b, row, col)
    end)
  end

  if not found then
    return nil
  end

  return format_value_for_display(found.key, found.default_value, found.kind)
end

local function extract_value_info_from_target(expr)
  if not expr or expr == "" then
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
  local root = tree:root()

  for _, match, _ in PHP_CALLS_Q:iter_matches(root, code) do
    local fn, method, key, callnode
    local default_value = nil
    for id, nodes in pairs(match) do
      local cap = PHP_CALLS_Q.captures[id]
      local node = nodes[1]
      local node_text = ts.get_node_text(node, code)

      if cap == "fn_name" then
        fn = node_text
      elseif cap == "method" then
        method = node_text
      elseif cap == "key_str" then
        key = node_text
      elseif cap == "default_str" then
        default_value = node_text
      end

      callnode = callnode or find_enclosing_call(node)
    end

    if key then
      local kind = (fn == "env") and "env" or "config"
      if method and (method == "get" or method == "set") then
        kind = "config"
      end
      if fn == "__" or fn == "trans" then
        kind = "lang"
      end

      return { fn = fn, method = method, key = key, default_value = default_value, kind = kind }
    end
  end

  return nil
end

local function get_value_info_for_blade()
  local text = textnode.get_text_node()
  if not text or text == "" then
    return nil
  end
  return extract_value_info_from_target(text)
end

local function value_info_at_cursor(bufnr)
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  row = row - 1
  local found

  for_each_php_tree(bufnr, function(root, b)
    if found then
      return
    end
    found = find_value_in_tree(PHP_CALLS_Q, find_enclosing_call, root, b, row, col)
  end)

  if not found then
    for_each_js_tree(bufnr, function(root, b)
      if found then
        return
      end
      found = find_value_in_tree(JS_CALLS_Q, find_enclosing_js_call, root, b, row, col)
    end)
  end

  return found
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

local function format_value_from_target(expr)
  if not expr or expr == "" then
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

  local root = tree:root()

  for _, match, _ in PHP_CALLS_Q:iter_matches(root, code) do
    local fn, method, key, callnode
    local default_value = nil
    for id, nodes in pairs(match) do
      local cap = PHP_CALLS_Q.captures[id]
      local node = nodes[1]
      local node_text = ts.get_node_text(node, code)

      if cap == "fn_name" then
        fn = node_text
      elseif cap == "method" then
        method = node_text
      elseif cap == "key_str" then
        key = node_text
      elseif cap == "default_str" then
        default_value = node_text
      end
      callnode = callnode or find_enclosing_call(node)
    end

    if key then
      local kind = (fn == "env") and "env" or "config"
      if method and (method == "get" or method == "set") then
        kind = "config"
      end
      if fn == "__" or fn == "trans" then
        kind = "lang"
      end

      return format_value_for_display(key, default_value, kind)
    end
  end

  return nil
end

local function get_value_for_blade()
  local text = textnode.get_text_node()
  if not text or text == "" then
    return nil
  end
  return format_value_from_target(text)
end

local function conditional_notify(msg, level, opts)
  if suppress_notify_until > 0 and uv.now() < suppress_notify_until then
    if type(msg) == "string" and msg:match("No information available") then
      return
    end
  end
  return original_notify(msg, level, opts)
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

local function try_lsp_hover(bufnr, has_fallback, before_wins)
  if has_fallback then
    suppress_notify_until = uv.now() + (config.hover_suppress_ms or 500)
    vim.notify = conditional_notify
  end

  local ok, err = pcall(vim.lsp.buf.hover)
  if not ok then
    log.debug("LSP hover failed: %s", err)
  end

  return before_wins
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
  local ok, err = pcall(function()
    vim.bo[bufn].filetype = "lsp-hover"
  end)

  if not ok then
    log.debug("Failed to set filetype: %s", err)
  end

  last_float = { buf = bufn, win = win }
  return true
end

local function check_hover_result(before_wins, has_fallback, bufnr)
  if has_fallback then
    vim.notify = original_notify
    suppress_notify_until = 0
  end

  local new_win
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if not before_wins[w] then
      new_win = w
      break
    end
  end

  local should_fallback = false

  if new_win then
    local buf = vim.api.nvim_win_get_buf(new_win)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local joined = table.concat(lines, "\n"):gsub("%s+$", "")

    if joined == "" or joined:match("No information available") then
      pcall(vim.api.nvim_win_close, new_win, true)
      should_fallback = true
    else
      last_float = { buf = buf, win = new_win }
      return
    end
  else
    should_fallback = true
  end

  if should_fallback then
    show_fallback_value(bufnr)
  end
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

  local before_wins = {}
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    before_wins[w] = true
  end

  try_lsp_hover(bufnr, has_fallback, before_wins)

  vim.defer_fn(function()
    check_hover_result(before_wins, has_fallback, bufnr)
  end, 100)
end

return M
