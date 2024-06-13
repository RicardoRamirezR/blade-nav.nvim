-- Custom opener for Laravel components

local M = {}
local rhs

local registered = false

local function get_keymap_rhs(mode, lhs)
  local mappings = vim.api.nvim_get_keymap(mode)
  for _, mapping in ipairs(mappings) do
    if mapping.lhs == lhs then
      return mapping.rhs:gsub("<[lL][tT]>", "<")
    end
  end

  return nil
end

local function exec_native_gf()
  if rhs then
    rhs = rhs:gsub("<[cC][fF][iI][lL][eE]>", M.cfile)
    rhs = rhs:gsub("<[cC][rR]>", "")
    vim.cmd(rhs)
  else
    vim.fn.execute("normal! gf")
  end
end

function M.gf()
  if vim.bo.filetype == "blade" then
    if require("blade-nav.gf_blade").gf() then
      return
    end
  end

  if vim.bo.filetype == "php" then
    if require("blade-nav.gf_php").gf() then
      return
    end
  end

  exec_native_gf()
end

M.setup = function()
  if registered then
    return
  end

  registered = true

  rhs = get_keymap_rhs("n", "gf")

  vim.keymap.set("n", "gf", function()
    M.cfile = vim.fn.expand("<cfile>")
    M.gf()
  end, { noremap = true, silent = true, desc = "BladeNav: Open file under cursor" })
end

return M
