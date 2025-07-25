-- lua/blade-nav/core/context.lua
-- Simplified context creation, closely mirroring working-version.txt and handling TS acquisition robustly.

local log = require("blade-nav.utils.log") -- Assuming log util exists

local M = {}

--- @class BladeNavContext
--- @field buffer integer Buffer number
--- @field filetype string Filetype of the buffer
--- @field line string The current line content
--- @field cursor_row integer 0-based row
--- @field cursor_col integer 0-based column
--- @field cursor_row_1 integer 1-based row
--- @field cursor_col_1 integer 1-based column
--- @field char_under_cursor string Character under the cursor
--- @field ts_node table|nil Tree-sitter node at cursor (acquired using working-version.txt logic)

--- Creates a context object for the current state.
--- Mimics the direct approach from working-version.txt and includes robust TS node acquisition.
--- @return BladeNavContext
function M.create_context()
  -- Get basic information directly, similar to working version
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0) -- Use 0 for current window/buffer
  local line = vim.api.nvim_get_current_line()
  local char_under_cursor = line:sub(cursor[2] + 1, cursor[2] + 1)

  local context = {
    buffer = bufnr,
    filetype = vim.api.nvim_buf_get_option(bufnr, "filetype"),
    line = line,
    cursor_row = cursor[1] - 1,   -- 0-based
    cursor_col = cursor[2],       -- 0-based
    cursor_row_1 = cursor[1],     -- 1-based
    cursor_col_1 = cursor[2] + 1, -- 1-based
    char_under_cursor = char_under_cursor,
    ts_node = nil,                -- Initialize as nil
  }

  -- --- Acquire Tree-sitter node using logic from working-version.txt ---
  -- This replicates the core TS node acquisition logic seen in working-version.txt's gf_views.lua
  -- It prioritizes vim.treesitter.get_node and falls back to nvim-treesitter.ts_utils.get_node_at_cursor.
  local current_node = nil

  -- 1. Try vim.treesitter.get_node (primary method from working-version.txt)
  local has_treesitter, ts = pcall(require, "vim.treesitter")
  if has_treesitter and ts then
    -- Use pcall when calling ts.get_node to catch potential errors
    local ok_node, node_or_err = pcall(ts.get_node)
    if ok_node and node_or_err then
      current_node = node_or_err
      log.debug("TS node acquired successfully using vim.treesitter.get_node.")
    elseif not ok_node then
      -- Log the specific error from vim.treesitter.get_node
      log.debug("TS node acquisition failed (vim.treesitter.get_node error): %s", tostring(node_or_err))
    else
      -- ok_node is true, but node_or_err is nil (no node found)
      log.debug("TS node acquisition returned nil from vim.treesitter.get_node.")
    end
  else
    log.debug("vim.treesitter module not available or failed to load: %s", tostring(ts))
  end

  -- 2. Fallback to nvim-treesitter.ts_utils.get_node_at_cursor if primary method failed
  if not current_node then
    local has_ts_utils, ts_utils = pcall(require, "nvim-treesitter.ts_utils")
    if has_ts_utils and ts_utils and ts_utils.get_node_at_cursor then
      -- Use pcall when calling get_node_at_cursor to catch potential errors (like "Invalid window id")
      local ok_utils_node, utils_node_or_err = pcall(ts_utils.get_node_at_cursor, 0, true) -- Use 0 for current buffer, cross_line=true
      if ok_utils_node and utils_node_or_err then
        current_node = utils_node_or_err
        log.debug("TS node acquired successfully using nvim-treesitter.ts_utils.get_node_at_cursor.")
      elseif not ok_utils_node then
        -- Log the specific error from nvim-treesitter.ts_utils.get_node_at_cursor
        log.debug(
          "TS node acquisition failed (nvim-treesitter.ts_utils.get_node_at_cursor error): %s",
          tostring(utils_node_or_err)
        )
      else
        -- ok_utils_node is true, but utils_node_or_err is nil (no node found)
        log.debug("TS node acquisition returned nil from nvim-treesitter.ts_utils.get_node_at_cursor.")
      end
    else
      if not has_ts_utils then
        log.debug("nvim-treesitter.ts_utils module not available or failed to load: %s", tostring(ts_utils))
      elseif not ts_utils.get_node_at_cursor then
        log.debug("nvim-treesitter.ts_utils.get_node_at_cursor function not found.")
      end
    end
  end

  -- Assign the acquired node (if any) to the context
  if current_node then
    context.ts_node = current_node
  else
    log.debug(
      "Failed to acquire TS node using both vim.treesitter.get_node and nvim-treesitter.ts_utils.get_node_at_cursor."
    )
    log.debug("Falling back to line-based logic in handlers.")
  end

  return context
end

return M
