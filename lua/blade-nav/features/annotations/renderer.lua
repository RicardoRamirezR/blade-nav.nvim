local M = {}

local uv = vim.loop
local ts = vim.treesitter
local log = require("blade-nav.utils.log")
local values = require("blade-nav.features.annotations.values")

local ns = values.ns
local PHP_CALLS_Q = values.PHP_CALLS_Q
local JS_CALLS_Q = values.JS_CALLS_Q
local for_each_php_tree = values.for_each_php_tree
local for_each_js_tree = values.for_each_js_tree
local find_enclosing_call = values.find_enclosing_call
local find_enclosing_js_call = values.find_enclosing_js_call
local format_value = values.format_value
local truncate = values.truncate

local config = {}
local processing_queue = {}
local processing_timer = nil
local is_processing = false
local max_processing_time_ms = 5
local processing_batch_size = 10

function M.set_config(cfg)
  config = cfg
end

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
    if fn == "__" or fn == "trans" then
      kind = "lang"
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
    if fn == "__" or fn == "trans" then
      kind = "lang"
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

local function render_matches_batch(matches, start_idx, batch_size)
  local end_idx = math.min(start_idx + batch_size - 1, #matches)

  for i = start_idx, end_idx do
    local match = matches[i]

    if not vim.api.nvim_buf_is_valid(match.bufnr) or not vim.api.nvim_buf_is_loaded(match.bufnr) then
      goto continue
    end

    local value_txt = format_value(match.key, match.default_value, match.kind)
    local vt = config.prefix .. truncate(value_txt, config.max_len)

    local ok, err = pcall(vim.api.nvim_buf_set_extmark, match.bufnr, ns, match.row, match.col, {
      virt_text = { { vt, config.hl } },
      virt_text_pos = "eol",
      hl_mode = "combine",
    })

    if not ok then
      log.debug("Failed to set extmark: %s", err)
    end

    ::continue::
  end

  return end_idx
end

local function process_queue_batch()
  if not processing_timer or is_processing then
    return
  end

  vim.schedule(function()
    is_processing = true
    local start_time = uv.hrtime()

    while #processing_queue > 0 do
      local item = processing_queue[1]

      local elapsed = (uv.hrtime() - start_time) / 1000000
      if elapsed > max_processing_time_ms then
        break
      end

      if not vim.api.nvim_buf_is_valid(item.bufnr) then
        table.remove(processing_queue, 1)
        goto continue
      end

      if item.type == "collect" then
        local all_matches = {}

        for_each_php_tree(item.bufnr, function(root, bufnr)
          local matches = collect_php_matches(root, bufnr)
          for _, match in ipairs(matches) do
            table.insert(all_matches, match)
          end
        end)

        for_each_js_tree(item.bufnr, function(root, bufnr)
          local matches = collect_js_matches(root, bufnr)
          for _, match in ipairs(matches) do
            table.insert(all_matches, match)
          end
        end)

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
        local last_idx = render_matches_batch(item.matches, item.batch_start, processing_batch_size)

        if last_idx < #item.matches then
          item.batch_start = last_idx + 1
        else
          table.remove(processing_queue, 1)
        end
      end

      ::continue::
    end

    is_processing = false

    if #processing_queue > 0 then
      processing_timer:start(1, 0, process_queue_batch)
    else
      processing_timer:stop()
    end
  end)
end

local function queue_buffer_processing(bufnr)
  for i = #processing_queue, 1, -1 do
    if processing_queue[i].bufnr == bufnr then
      table.remove(processing_queue, i)
    end
  end

  table.insert(processing_queue, {
    type = "collect",
    bufnr = bufnr,
  })

  if not processing_timer then
    processing_timer = uv.new_timer()
  end

  if not is_processing and processing_timer then
    processing_timer:start(1, 0, process_queue_batch)
  end
end

function M.render_buffer(bufnr, use_background)
  if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
    return
  end

  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  if not config.show then
    return
  end

  if use_background == false then
    for_each_php_tree(bufnr, function(root, b)
      local matches = collect_php_matches(root, b)
      render_matches_batch(matches, 1, #matches)
    end)

    for_each_js_tree(bufnr, function(root, b)
      local matches = collect_js_matches(root, b)
      render_matches_batch(matches, 1, #matches)
    end)
  else
    queue_buffer_processing(bufnr)
  end
end

function M.cleanup_timer()
  if processing_timer then
    processing_timer:stop()
    processing_timer:close()
    processing_timer = nil
  end
end

function M.clear_queue()
  processing_queue = {}
  if processing_timer then
    processing_timer:stop()
  end
end

function M.get_processing_queue()
  return processing_queue
end

return M
