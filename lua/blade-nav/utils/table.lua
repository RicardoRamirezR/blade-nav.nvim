-- lua/blade-nav/utils/table.lua
local M = {}

--- Check if a value exists in a table.
--- @param tbl table Table to search
--- @param value any Value to find
--- @return boolean
function M.contains(tbl, value)
  if type(tbl) == "string" then
    tbl = { tbl }
  end

  return vim.tbl_contains(tbl, value)
end

return M
