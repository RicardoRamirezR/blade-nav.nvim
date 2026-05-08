-- lua/blade-nav/core/context.lua

local log = require("blade-nav.utils.log")
local textnode = require("blade-nav.core.textnode")

local M = {}

--- @class BladeNavContext
--- @field buffer integer Buffer number
--- @field filetype string Filetype of the buffer
--- @field line string The current line content
--- @field target string|nil Extracted target
--- @field first_arg string|nil Extracted first argument

function M.create()
  local bufnr = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_get_current_line()

  local context = {
    buffer = bufnr,
    filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr }),
    line = line,
    first_arg = nil,
    target = nil,
  }

  local ok, extracted, target, first_arg = pcall(textnode.get_text_node)
  if ok and extracted then
    context.line = extracted
    context.target = target
    context.first_arg = first_arg
    log.debug("Extracted text node: %s", extracted)
  else
    log.debug("No extracted text at cursor (error: %s)", tostring(extracted))
  end

  return context
end

return M
