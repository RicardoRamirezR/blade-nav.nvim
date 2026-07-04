-- tests/helpers.lua
-- Test helper to create an isolated scratch buffer, set filetype, force tree-sitter parse,
-- run a callback and clean up. All comments/code in English.

local M = {}

--- with_buffer(lines, opts?, fn)
-- lines: string or table of strings (each line).
-- opts: optional table:
--   filetype = "blade" (default)
--   parse = true|false (default true)
--   cursor = { row, col } (optional initial cursor; col is 0-based)
-- fn: function(bufnr) -> any
function M.with_buffer(lines, opts, fn)
  -- signature flexibility: with_buffer(lines, fn) or with_buffer(lines, opts, fn)
  if type(opts) == "function" then
    fn = opts
    opts = {}
  end
  opts = opts or {}

  -- normalize lines to table
  if type(lines) == "string" then
    lines = vim.split(lines, "\n", { plain = true })
  elseif type(lines) ~= "table" then
    error("with_buffer: expected string or table for lines, got " .. type(lines))
  end

  -- create scratch buffer (unlisted, wipe on delete)
  local bufnr = vim.api.nvim_create_buf(false, true)
  assert(bufnr and bufnr > 0, "with_buffer: failed to create buffer")

  -- set basic buffer options
  vim.api.nvim_buf_set_option(bufnr, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(bufnr, "buftype", "")
  local ft = opts.filetype or "blade"
  vim.api.nvim_buf_set_option(bufnr, "filetype", ft)

  -- set contents
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  -- switch to buffer in current window
  vim.api.nvim_set_current_buf(bufnr)

  -- set initial cursor if provided (row 1-indexed, col 0-indexed)
  if opts.cursor then
    vim.api.nvim_win_set_cursor(0, { opts.cursor[1], opts.cursor[2] })
  else
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
  end

  -- attempt to get parser and optionally force parse
  if opts.parse ~= false then
    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, ft)
    if ok and parser then
      pcall(function()
        parser:parse()
      end)
    end
  end

  -- run user's function, capture return value and errors
  local result
  local ok, err = pcall(function()
    result = fn(bufnr)
  end)

  -- always attempt to delete buffer
  pcall(vim.api.nvim_buf_delete, bufnr, { force = true })

  if not ok then
    error(err)
  end
  return result
end

return M
