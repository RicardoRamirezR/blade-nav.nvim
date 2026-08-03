local M = {}

local uv = vim.uv
local log = require("blade-nav.utils.log")
local values = require("blade-nav.features.annotations.values")

local ns = values.ns
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

  local query = values.get_php_query()
  if not query then
    return matches
  end

  for _, match, _ in query:iter_matches(root, bufnr) do
    local info = values.extract_call_info(query, match, bufnr, find_enclosing_call)

    if info and info.callnode then
      local sr, sc, er, ec = info.callnode:range()
      local node_range = string.format("%d:%d-%d:%d", sr, sc, er, ec)

      if not processed_nodes[node_range] then
        processed_nodes[node_range] = true

        table.insert(matches, {
          bufnr = bufnr,
          row = er,
          col = ec,
          key = info.key,
          default_value = info.default_value,
          kind = info.kind,
        })
      end
    end
  end

  return matches
end

local function collect_js_matches(root, bufnr)
  local matches = {}
  local processed_nodes = {}

  local query = values.get_js_query()
  if not query then
    return matches
  end

  for _, match, _ in query:iter_matches(root, bufnr) do
    local info = values.extract_call_info(query, match, bufnr, find_enclosing_js_call)

    if info and info.callnode then
      local sr, sc, er, ec = info.callnode:range()
      local node_range = string.format("%d:%d-%d:%d", sr, sc, er, ec)

      if not processed_nodes[node_range] then
        processed_nodes[node_range] = true

        table.insert(matches, {
          bufnr = bufnr,
          row = er,
          col = ec,
          key = info.key,
          default_value = info.default_value,
          kind = info.kind,
        })
      end
    end
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

local function collect_buffer_matches(bufnr)
  local all_matches = {}

  for_each_php_tree(bufnr, function(root, b)
    local matches = collect_php_matches(root, b)
    for _, match in ipairs(matches) do
      table.insert(all_matches, match)
    end
  end)

  for_each_js_tree(bufnr, function(root, b)
    local matches = collect_js_matches(root, b)
    for _, match in ipairs(matches) do
      table.insert(all_matches, match)
    end
  end)

  return all_matches
end

-- Process the queue entry at the head of the queue. A "collect" entry runs
-- the full tree-sitter scan for its buffer and, when matches were found,
-- queues a "render" entry; a "render" entry draws one batch of extmarks and
-- stays queued until all of its matches are drawn.
local function process_queue_item(item)
  if item.type == "collect" then
    vim.api.nvim_buf_clear_namespace(item.bufnr, ns, 0, -1)
    local all_matches = collect_buffer_matches(item.bufnr)

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
end

local process_queue_batch

local function process_queue_batch_body()
  if not processing_timer then
    is_processing = false
    return
  end

  is_processing = true
  local start_time = uv.hrtime()

  while #processing_queue > 0 do
    local item = processing_queue[1]

    -- The 5ms budget bounds this scheduled run of the collect/render phases;
    -- a single tree-sitter iteration is not chunked (one collect may exceed
    -- it on a huge buffer).
    local elapsed = (uv.hrtime() - start_time) / 1000000
    if elapsed > max_processing_time_ms then
      break
    end

    if not vim.api.nvim_buf_is_valid(item.bufnr) then
      table.remove(processing_queue, 1)
      goto continue
    end

    -- One corrupt buffer (malformed blade/vue, extractor error) must not kill
    -- the queue for every other buffer: drop the failing item and continue.
    local ok, err = pcall(process_queue_item, item)
    if not ok then
      log.error("BladeNav: dropping buffer %d from the annotation queue after an error: %s", item.bufnr, err)
      table.remove(processing_queue, 1)
    end

    ::continue::
  end

  is_processing = false

  if not processing_timer then
    return
  end

  if #processing_queue > 0 then
    processing_timer:start(1, 0, process_queue_batch)
  else
    processing_timer:stop()
  end
end

process_queue_batch = function()
  if not processing_timer or is_processing then
    return
  end

  vim.schedule(function()
    -- An error escaping this scheduled callback would leave is_processing
    -- stuck at true and the timer disarmed, silently killing annotations for
    -- the rest of the session; catch everything, drop the offending item,
    -- and keep the queue moving.
    local ok, err = xpcall(process_queue_batch_body, debug.traceback)
    if ok then
      return
    end

    log.error("BladeNav: annotation queue processing failed: %s", err)
    is_processing = false

    if #processing_queue > 0 then
      table.remove(processing_queue, 1)
    end

    if not processing_timer then
      return
    end

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

  if not config.show then
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    return
  end

  if use_background == false then
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    local matches = collect_buffer_matches(bufnr)
    render_matches_batch(matches, 1, #matches)
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
