-- lua/blade-nav/annotations/values.lua

local M = {}

local ns = vim.api.nvim_create_namespace("blade-nav/values")
local ts = vim.treesitter
local uv = vim.loop

local config_extractor = require("blade-nav.extractors.config")
local debounce = require("blade-nav.utils.debounce")
local env_extractor = require("blade-nav.extractors.env")
local log = require("blade-nav.utils.log")
local textnode = require("blade-nav.core.textnode")

local env_map_local = nil
local cfg_map = nil

-- Function to get env_map (lazy initialization)
local function get_env_map()
  if not env_map_local then
    env_map_local = env_extractor.get_map()
  end
  return env_map_local
end

-- Function to get cfg_map (lazy initialization)
local function get_cfg_map()
  if not cfg_map then
    cfg_map = config_extractor.get_map()
  end
  return cfg_map
end

-- Function to invalidate cached maps (useful for refresh operations)
local function invalidate_maps()
  env_map_local = nil
  cfg_map = nil
end

local config = {}
local render_debounced

-- Background processing state
local processing_queue = {}
local processing_timer = nil
local is_processing = false
local max_processing_time_ms = 5 -- Max time per frame to avoid blocking
local processing_batch_size = 10 -- Max nodes to process per batch

-- Treesitter query for config/env/Config::get/Config::set in PHP
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

-- Treesitter query for config/env calls in JavaScript (for Blade files)
local JS_CALLS_Q = vim.treesitter.query.parse(
  "javascript",
  [[
  ; JavaScript call expression: config('key') or env('key', 'default')
  (call_expression
    function: (identifier) @fn_name
    arguments: (arguments
      (string (string_fragment) @key_str)
      (string (string_fragment) @default_str)?)
    (#any-of? @fn_name "config" "env"))

  ; Also catch calls in binary expressions (like in your example)
  (call_expression
    function: (identifier) @fn_name
    arguments: (arguments
      (string (string_fragment) @key_str))
    (#any-of? @fn_name "config" "env"))
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

-- Utility: iterate javascript subtrees (for embedded JS in Blade)
local function for_each_js_tree(bufnr, cb)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then
    return
  end

  parser:for_each_tree(function(tstree, langtree)
    if langtree:lang() == "javascript" then
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

-- Find enclosing call node (function_call_expression or scoped_call_expression for PHP)
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

-- Find enclosing call node for JavaScript
local function find_enclosing_js_call(node)
  while node do
    local t = node:type()
    if t == "call_expression" then
      return node
    end
    node = node:parent()
  end

  return nil
end

-- Aux common function to format values
local function format_value(key, default_value, kind)
  if kind == "env" then
    local env_map_local = get_env_map()
    local env_value = env_map_local[key]
    if not env_value or env_value == "" then
      return default_value or "(not found)"
    end
    return env_value
  end
  local cfg_map_local = get_cfg_map()
  local config_entry = cfg_map_local[key]
  if not config_entry then
    return "(not found)"
  end
  if config_entry.kind == "array" then
    return string.format("[array: %d]", config_entry.array_size or 0)
  end
  if config_entry.kind == "env_ref" then
    local env_map_local = get_env_map()
    local referenced_env_value = env_map_local[config_entry.ref] or "(not found)"
    return string.format("%s", referenced_env_value)
  end
  return config_entry.text
end

local function format_value_for_display(key, default_value, kind)
  if kind == "env" then
    local env_map_local = get_env_map()
    local env_value = env_map_local[key]
    if not env_value or env_value == "" then
      return ("env(%s) = %s"):format(key, default_value or "(not found)")
    end
    return ("env(%s) = %s"):format(key, env_value)
  end
  local cfg_map_local = get_cfg_map()
  local config_entry = cfg_map_local[key]
  if not config_entry then
    return ("config(%s) = (not found)"):format(key)
  end
  if config_entry.kind == "array" then
    return ("config(%s) = [array: %d]"):format(key, config_entry.array_size or 0)
  end
  if config_entry.kind == "env_ref" then
    local env_map_local = get_env_map()
    local referenced_env_value = env_map_local[config_entry.ref] or "(not found)"
    return ("config(%s) = %s"):format(key, referenced_env_value)
  end
  return ("config(%s) = %s"):format(key, config_entry.text)
end

-- Background processing: collect matches without rendering
local function collect_php_matches(root, bufnr)
  local matches = {}
  local processed_nodes = {}

  for _, match, _ in PHP_CALLS_Q:iter_matches(root, bufnr) do
    local fn, method, key, callnode
    local default_value = nil

    for id, nodes in pairs(match) do
      local cap = PHP_CALLS_Q.captures[id]
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

    table.insert(matches, {
      bufnr = bufnr,
      row = er,
      col = ec,
      key = key,
      default_value = default_value,
      kind = kind,
    })

    ::continue::
  end

  return matches
end

-- Background processing: collect JavaScript matches
local function collect_js_matches(root, bufnr)
  local matches = {}
  local processed_nodes = {}

  for _, match, _ in JS_CALLS_Q:iter_matches(root, bufnr) do
    local fn, key, callnode
    local default_value = nil

    for id, nodes in pairs(match) do
      local cap = JS_CALLS_Q.captures[id]
      local node = nodes[1]
      local node_text = ts.get_node_text(node, bufnr)

      if cap == "fn_name" then
        fn = node_text
      elseif cap == "key_str" then
        key = node_text
      elseif cap == "default_str" then
        default_value = node_text
      end

      callnode = callnode or find_enclosing_js_call(node)
    end

    if not key or not callnode or not fn then
      goto continue
    end

    local sr, sc, er, ec = callnode:range()
    local node_range = string.format("%d:%d-%d:%d", sr, sc, er, ec)

    if processed_nodes[node_range] then
      goto continue
    end

    processed_nodes[node_range] = true

    local kind = (fn == "env") and "env" or "config"

    table.insert(matches, {
      bufnr = bufnr,
      row = er,
      col = ec,
      key = key,
      default_value = default_value,
      kind = kind,
    })

    ::continue::
  end

  return matches
end

-- Background processing: render a batch of matches
local function render_matches_batch(matches, start_idx, batch_size)
  local end_idx = math.min(start_idx + batch_size - 1, #matches)

  for i = start_idx, end_idx do
    local match = matches[i]

    -- Skip if buffer is no longer valid
    if not vim.api.nvim_buf_is_valid(match.bufnr) or not vim.api.nvim_buf_is_loaded(match.bufnr) then
      goto continue
    end

    local value_txt = format_value(match.key, match.default_value, match.kind)
    local vt = config.prefix .. truncate(value_txt, config.max_len)

    pcall(vim.api.nvim_buf_set_extmark, match.bufnr, ns, match.row, match.col, {
      virt_text = { { vt, config.hl } },
      virt_text_pos = "eol",
      hl_mode = "combine",
    })

    ::continue::
  end

  return end_idx
end

-- Background processing timer function
local function process_queue_batch()
  if not processing_timer or is_processing then
    return
  end

  -- Use vim.schedule to move to main event loop context
  vim.schedule(function()
    is_processing = true
    local start_time = uv.hrtime()

    while #processing_queue > 0 do
      local item = processing_queue[1]

      -- Check if we've exceeded our time budget
      local elapsed = (uv.hrtime() - start_time) / 1000000 -- Convert to ms
      if elapsed > max_processing_time_ms then
        break
      end

      -- Skip if buffer is no longer valid
      if not vim.api.nvim_buf_is_valid(item.bufnr) then
        table.remove(processing_queue, 1)
        goto continue
      end

      if item.type == "collect" then
        -- Collect matches for this buffer
        local all_matches = {}

        -- Collect PHP matches
        for_each_php_tree(item.bufnr, function(root, bufnr)
          local matches = collect_php_matches(root, bufnr)
          for _, match in ipairs(matches) do
            table.insert(all_matches, match)
          end
        end)

        -- Collect JavaScript matches
        for_each_js_tree(item.bufnr, function(root, bufnr)
          local matches = collect_js_matches(root, bufnr)
          for _, match in ipairs(matches) do
            table.insert(all_matches, match)
          end
        end)

        -- Add render job to queue
        if #all_matches > 0 then
          table.insert(processing_queue, {
            type = "render",
            bufnr = item.bufnr,
            matches = all_matches,
            batch_start = 1,
          })
        end

        table.remove(processing_queue, 1)
      elseif item.type == "render" then
        -- Render a batch of matches
        local last_idx = render_matches_batch(item.matches, item.batch_start, processing_batch_size)

        if last_idx < #item.matches then
          -- More to render, update batch start
          item.batch_start = last_idx + 1
        else
          -- Finished rendering this buffer
          table.remove(processing_queue, 1)
        end
      end

      ::continue::
    end

    is_processing = false

    -- Schedule next processing if queue not empty
    if #processing_queue > 0 then
      processing_timer:start(1, 0, process_queue_batch) -- Process again in 1ms
    else
      processing_timer:stop()
    end
  end)
end

-- Queue a buffer for background processing
local function queue_buffer_processing(bufnr)
  -- Remove any existing items for this buffer
  for i = #processing_queue, 1, -1 do
    if processing_queue[i].bufnr == bufnr then
      table.remove(processing_queue, i)
    end
  end

  -- Add new processing job
  table.insert(processing_queue, {
    type = "collect",
    bufnr = bufnr,
  })

  -- Start processing if not already running
  if not processing_timer then
    processing_timer = uv.new_timer()
  end

  if not is_processing and processing_timer then
    processing_timer:start(1, 0, process_queue_batch) -- Start in 1ms
  end
end

-- Enhanced render_buffer function with background processing option
local function render_buffer(bufnr, use_background)
  if not vim.api.nvim_buf_is_loaded(bufnr) then
    return
  end

  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  if not config.show then
    return
  end

  if use_background == false then
    -- Synchronous rendering for immediate needs (like on_K)
    for_each_php_tree(bufnr, function(root, b)
      local matches = collect_php_matches(root, b)
      render_matches_batch(matches, 1, #matches)
    end)

    for_each_js_tree(bufnr, function(root, b)
      local matches = collect_js_matches(root, b)
      render_matches_batch(matches, 1, #matches)
    end)
  else
    -- Background processing (default)
    queue_buffer_processing(bufnr)
  end
end

-- Enhanced value_at_cursor to handle JavaScript contexts
local function value_at_cursor(bufnr)
  unpack = table.unpack or unpack
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  row = row - 1
  local found

  -- First try PHP trees
  for_each_php_tree(bufnr, function(root, b)
    if found then
      return
    end

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

  -- If not found in PHP, try JavaScript trees
  if not found then
    for_each_js_tree(bufnr, function(root, b)
      if found then
        return
      end

      for _, match, _ in JS_CALLS_Q:iter_matches(root, b) do
        local fn, key, callnode
        local default_value = nil

        for id, nodes in pairs(match) do
          local cap = JS_CALLS_Q.captures[id]
          local node = nodes[1]
          local node_text = ts.get_node_text(node, b)

          if cap == "fn_name" then
            fn = node_text
          elseif cap == "key_str" then
            key = node_text
          elseif cap == "default_str" then
            default_value = node_text
          end

          callnode = callnode or find_enclosing_js_call(node)
        end

        if callnode and key and fn then
          local sr, sc, er, ec = callnode:range()
          if row >= sr and row <= er and col >= sc and col <= ec then
            local kind = (fn == "env") and "env" or "config"
            found = {
              fn = fn,
              method = nil,
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
  end

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
    render_buffer(vim.api.nvim_get_current_buf(), true) -- Use background processing
    log.debug("Values enabled")
    return
  end

  -- Clear processing queue
  processing_queue = {}
  if processing_timer then
    processing_timer:stop()
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
  render_buffer(bufnr, true) -- Use background processing
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

-- Check if we have a config/env value at cursor position (enhanced for JS)
local function has_value_at_cursor(bufnr)
  local ft = vim.bo[bufnr].filetype
  if ft == "blade" then
    -- Try the textnode approach first
    local blade_value = get_value_for_blade()
    if blade_value then
      return true
    end
    -- Also try the treesitter approach
    return value_at_cursor(bufnr) ~= nil
  end

  return value_at_cursor(bufnr) ~= nil
end

-- on_K: try LSP hover (if supported), fallback to our value if hover empty / "No information available"
function M.on_K()
  local bufnr = vim.api.nvim_get_current_buf()

  -- Ensure current buffer has up-to-date annotations for immediate cursor lookup
  if config.show then
    render_buffer(bufnr, false) -- Force synchronous rendering for immediate response
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
    render_buffer(buf, true) -- Use background processing for debounced renders
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

  -- Cleanup on exit
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = grp,
    callback = function()
      if processing_timer then
        processing_timer:stop()
        processing_timer:close()
        processing_timer = nil
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
