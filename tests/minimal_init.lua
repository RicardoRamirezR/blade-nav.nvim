-- tests/minimal_init.lua
-- Minimal init for running Plenary tests

-- Add project lua/ to runtime path
vim.opt.rtp:append(".")

-- Ensure plenary is available
pcall(require, "plenary")

-- (Optional) disable user config that might interfere
vim.cmd("set noswapfile")
vim.cmd("set rtp+=./lua")

-- tests/minimal_init.lua
vim.cmd("set runtimepath=$VIMRUNTIME")
vim.cmd("set packpath^=~/.local/share/nvim/site")

-- Add lazy.nvim-style plugin paths
vim.opt.runtimepath:append("~/.local/share/nvim/lazy/plenary.nvim")
vim.opt.runtimepath:append("~/.local/share/nvim/lazy/nvim-treesitter")

-- Configure nvim-treesitter
local ok, ts_configs = pcall(require, "nvim-treesitter.configs")
if ok then
  ts_configs.setup({
    ensure_installed = { "blade", "php", "lua" },
    sync_install = true,
    highlight = { enable = false },
  })
else
  vim.api.nvim_err_writeln("nvim-treesitter not available in test runtimepath")
end
