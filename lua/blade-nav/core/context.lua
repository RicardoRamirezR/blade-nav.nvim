-- lua/blade-nav/core/context.lua

local log = require("blade-nav.utils.log")
local textnode = require("blade-nav.core.textnode")

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
--- @field ts_node table|nil Tree-sitter node at cursor
--- @field extracted_text string|nil Extracted expression/directive/tag text

function M.create()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_get_current_line()
  local char_under_cursor = line:sub(cursor[2] + 1, cursor[2] + 1)

  local context = {
    buffer = bufnr,
    filetype = vim.api.nvim_buf_get_option(bufnr, "filetype"),
    line = line,
    cursor_row = cursor[1] - 1,
    cursor_col = cursor[2],
    cursor_row_1 = cursor[1],
    cursor_col_1 = cursor[2] + 1,
    char_under_cursor = char_under_cursor,
    ts_node = nil, -- si quieres, puedes seguir guardando el raw node
  }

  -- usar nuevo módulo
  local ok, extracted = pcall(textnode.get_text_node)
  if ok and extracted then
    context.line = extracted
    log.debug("Extracted text node: %s", extracted)
  else
    log.debug("No extracted text at cursor (error: %s)", tostring(extracted))
  end

  return context
end

return M
