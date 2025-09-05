-- lua/blade-nav/annotations/values.lua

local M = {}

local ns = vim.api.nvim_create_namespace("blade-nav/values")
local ts = vim.treesitter
local uv = vim.loop

local cache = require("blade-nav.utils.cache")
local config_extractor = require("blade-nav.extractors.config")
local debounce = require("blade-nav.utils.debounce")
local env_extractor = require("blade-nav.extractors.env")
local log = require("blade-nav.utils.log")
local textnode = require("blade-nav.core.textnode")

local env_map = env_extractor.get_map()
local cfg_map = config_extractor.get_map()

local config = {}
local render_debounced

-- Treesitter query for config/env/Config::get/Config::set
local PHP_CALLS_Q = vim.treesitter.query.parse(
  "php",
  [[
  ; Standard function call: env('key', 'default') or env('key')
  (function_call_expression
    function: (name) @fn_name
    arguments: (arguments
      (argument
        (string (string_content) @key_str))
      (argument
        (string (string_content) @default_str))?)
    (#eq? @fn_name "env"))

  ; Standard function call: config('key')
  (function_call_expression
    function: (name) @fn_name
    arguments: (arguments
      (argument
        (string (string_content) @key_str)))
    (#eq? @fn_name "config"))

  ; Scoped call: Config::get('key', 'default') or Config::get('key')
  (scoped_call_expression
    scope: (name) @scope
    name: (name) @method
    arguments: (arguments
      (argument
        (string (string_content) @key_str))
      (argument
        (string (string_content) @default_str))?)
    (#eq? @scope "Config")
    (#any-of? @method "get" "set"))
]]
)

-- Utility: iterate php subtrees (Blade injects php)
local function for_each_php_tree(bufnr, cb)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then
    return
  end

  parser:for_each_tree(function(tstree, langtree)
    if langtree:lang() == "php" then
      cb(tstree:root(), bufnr)
    end
  end)
end

local function truncate(s, n)
  if not s then
    return ""
  end

  if #s <= n then
    return s
  end

  return s:sub(1, n - 1) .. "…"
end

-- Find enclosing call node (function_call_expression or scoped_call_expression)
local function find_enclosing_call(node)
  while node do
    local t = node:type()
    if t == "function_call_expression" or t == "scoped_call_expression" then
      return node
    end
    node = node:parent()
  end

  return nil
end

-- Aux common function to format values
local function format_value(key, default_value, kind)
  if kind == "env" then
    local env_value = env_map[key]
    if not env_value or env_value == "" then
      return default_value or "(not found)"
    end
    return env_value
  end

  local config_entry = cfg_map[key]
  if not config_entry then
    return "(not found)"
  end

  if config_entry.kind == "array" then
    return string.format("[array: %d]", config_entry.array_size or 0)
  end

  if config_entry.kind == "env_ref" then
    local referenced_env_value = env_map[config_entry.ref] or "(not found)"
    return string.format("%s", referenced_env_value)
  end

  return config_entry.text
end

local function format_value_for_display(key, default_value, kind)
  if kind == "env" then
    local env_value = env_map[key]
    if not env_value or env_value == "" then
      return ("env(%s) = %s"):format(key, default_value or "(not found)")
    end
    return ("env(%s) = %s"):format(key, env_value)
  end

  local config_entry = cfg_map[key]
  if not config_entry then
    return ("config(%s) = (not found)"):format(key)
  end

  if config_entry.kind == "array" then
    return ("config(%s) = [array: %d]"):format(key, config_entry.array_size or 0)
  end

  if config_entry.kind == "env_ref" then
    local referenced_env_value = env_map[config_entry.ref] or "(not found)"
    return ("config(%s) = %s"):format(key, referenced_env_value)
  end

  return ("config(%s) = %s"):format(key, config_entry.text)
end

-- Render virtual text for a buffer (safe to call repeatedly)
local function render_buffer(bufnr)
  if not vim.api.nvim_buf_is_loaded(bufnr) then
    return
  end

  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  if not config.show then
    return
  end

  for_each_php_tree(bufnr, function(root, b)
    local processed_nodes = {}

    for _, match, _ in PHP_CALLS_Q:iter_matches(root, b) do
      local fn, method, key, callnode
      local default_value = nil

      for id, nodes in pairs(match) do
        local cap = PHP_CALLS_Q.captures[id]
        local node = nodes[1]
        local node_text = ts.get_node_text(node, b)

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

      if not key or not callnode then
        goto continue
      end

      local sr, sc, er, ec = callnode:range()
      local node_range = string.format("%d:%d-%d:%d", sr, sc, er, ec)

      if processed_nodes[node_range] then
        goto continue
      end

      processed_nodes[node_range] = true

      local kind = (fn == "env") and "env" or "config"
      if method and (method == "get" or method == "set") then
        kind = "config"
      end

      local value_txt = format_value(key, default_value, kind)
      local vt = config.prefix .. truncate(value_txt, config.max_len)

      local _, _, er, ec = callnode:range()
      vim.api.nvim_buf_set_extmark(b, ns, er, ec, {
        virt_text = { { vt, config.hl } },
        virt_text_pos = "eol",
        hl_mode = "combine",
      })

      ::continue::
    end
  end)
end

-- value at cursor using treesitter matches
local function value_at_cursor(bufnr)
  unpack = table.unpack or unpack
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  row = row - 1
  local found

  for_each_php_tree(bufnr, function(root, b)
    for _, match, _ in PHP_CALLS_Q:iter_matches(root, b) do
      local fn, method, key, callnode
      local default_value = nil

      for id, nodes in pairs(match) do
        local cap = PHP_CALLS_Q.captures[id]
        local node = nodes[1]
        local node_text = ts.get_node_text(node, b)

        if cap == "fn_name" then
          fn = node_text
        end
        if cap == "method" then
          method = node_text
        end
        if cap == "key_str" then
          key = node_text
        end
        if cap == "default_str" then
          default_value = node_text
        end
        callnode = callnode or find_enclosing_call(node)
      end

      if callnode then
        local sr, sc, er, ec = callnode:range()
        if row >= sr and row <= er and col >= sc and col <= ec then
          local kind = (fn == "env") and "env" or "config"
          if method and (method == "get" or method == "set") then
            kind = "config"
          end
          found = {
            fn = fn,
            method = method,
            key = key,
            callnode = callnode,
            default_value = default_value,
            kind = kind,
          }
          return
        end
      end
    end
  end)

  if not found then
    return nil
  end

  return format_value_for_display(found.key, found.default_value, found.kind)
end

-- Parse a small PHP expression string and format the resolved value
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

      return format_value_for_display(key, default_value, kind)
    end
  end

  return nil
end

-- Use Blade context extraction when inside blade files
local function get_value_for_blade()
  local text = textnode.get_text_node()
  if not text or text == "" then
    return nil
  end
  return format_value_from_target(text)
end

-- Toggle show and clear extmarks when hiding
function M.toggle_show()
  config.show = not config.show
  if config.show then
    render_buffer(vim.api.nvim_get_current_buf())
    log.debug("Values enabled")
    return
  end

  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) then
      pcall(vim.api.nvim_buf_clear_namespace, b, ns, 0, -1)
    end
  end

  log.debug("Values disabled")
end

function M.refresh(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  render_buffer(bufnr)
end

function M.clear_cache()
  require("blade-nav.utils.cache").clear()
  log.debug("BladeNav: caches cleared")
end

-- keep last created BladeNav float window so KK focuses it
local last_float = { win = nil, buf = nil }

-- Store original vim.notify to restore later
local original_notify = vim.notify
local suppress_notify_until = 0

-- Custom notify that suppresses "No information available" during our hover attempts
local function conditional_notify(msg, level, opts)
  if suppress_notify_until > 0 and uv.now() < suppress_notify_until then
    if type(msg) == "string" and msg:match("No information available") then
      return
    end
  end
  return original_notify(msg, level, opts)
end

-- Check if we have a config/env value at cursor position
local function has_value_at_cursor(bufnr)
  local ft = vim.bo[bufnr].filetype
  if ft == "blade" then
    return get_value_for_blade() ~= nil
  end

  return value_at_cursor(bufnr) ~= nil
end

-- on_K: try LSP hover (if supported), fallback to our value if hover empty / "No information available"
function M.on_K()
  local bufnr = vim.api.nvim_get_current_buf()
  local clients = vim.lsp.get_clients({ bufnr = bufnr })

  local supports_hover = false
  for _, client in ipairs(clients) do
    if client.server_capabilities and client.server_capabilities.hoverProvider then
      supports_hover = true
      break
    end
  end

  if not supports_hover then
    local ft = vim.bo[bufnr].filetype
    local text = (ft == "blade" and get_value_for_blade()) or value_at_cursor(bufnr)
    if not text then
      return
    end

    if last_float.win and vim.api.nvim_win_is_valid(last_float.win) then
      vim.api.nvim_set_current_win(last_float.win)
      return
    end

    local bufn, win = vim.lsp.util.open_floating_preview({ text }, "markdown", { border = "rounded" })
    pcall(function()
      vim.bo[bufn].filetype = "lsp-hover"
    end)
    last_float = { buf = bufn, win = win }
    return
  end

  local has_fallback = has_value_at_cursor(bufnr)

  local before_wins = {}
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    before_wins[w] = true
  end

  if has_fallback then
    suppress_notify_until = uv.now() + (config.hover_suppress_ms or 500)
    vim.notify = conditional_notify
  end

  M._suppress_until = uv.now() + (config.hover_suppress_ms or 500)
  pcall(vim.lsp.buf.hover)

  vim.defer_fn(function()
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
      local ft = vim.bo[bufnr].filetype
      local text = (ft == "blade" and get_value_for_blade()) or value_at_cursor(bufnr)
      if not text then
        return
      end

      if last_float.win and vim.api.nvim_win_is_valid(last_float.win) then
        vim.api.nvim_set_current_win(last_float.win)
        return
      end

      local bufn, win = vim.lsp.util.open_floating_preview({ text }, "markdown", { border = "rounded" })
      pcall(function()
        vim.bo[bufn].filetype = "lsp-hover"
      end)
      last_float = { buf = bufn, win = win }
    end
  end, 100)
end

-- Setup: merge defaults with core config and wire commands/autocmds
function M.setup()
  local core = require("blade-nav.core.config")
  local core_cfg = core.get() or {}
  config = core_cfg.annotations

  render_debounced = debounce(function(buf)
    render_buffer(buf)
  end, config.debounce_ms or 120)

  local WEB_FILETYPES = { "php", "blade", "html", "javascript", "vue" }
  local grp = vim.api.nvim_create_augroup("BladeNavValues", { clear = true })
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
    group = grp,
    callback = function(args)
      local ft = vim.bo[args.buf].filetype
      if vim.tbl_contains(WEB_FILETYPES, ft) then
        render_debounced(args.buf)
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "TextChanged", "InsertLeave", "BufWritePost" }, {
    group = grp,
    callback = function(args)
      local ft = vim.bo[args.buf].filetype
      if vim.tbl_contains(WEB_FILETYPES, ft) then
        render_debounced(args.buf)
      end
    end,
  })

  vim.api.nvim_create_user_command("BladeNavToggleShowValues", function()
    M.toggle_show()
  end, {
    desc = "Toggle BladeNav config/env annotations in current project",
  })
  vim.api.nvim_create_user_command("BladeNavClearCache", function()
    M.clear_cache()
  end, {
    desc = "Clear BladeNav config/env caches",
  })

  if config.create_keymaps then
    vim.keymap.set("n", "K", M.on_K, { desc = "BladeNav: show config/env value" })
    vim.keymap.set("n", "<leader>bv", M.toggle_show, { desc = "BladeNav: toggle show annotations" })
    vim.keymap.set("n", "<leader>bcc", M.clear_cache, { desc = "BladeNav: clear cache" })
  end

  log.debug("BladeNav: annotations setup with: %s", vim.inspect(config))
end

return M
