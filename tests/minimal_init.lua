-- tests/minimal_init.lua
-- Minimal init for running Plenary tests

-- Add project lua/ to runtime path
vim.opt.rtp:append(".")

-- Ensure plenary is available
pcall(require, "plenary")

-- (Optional) disable user config that might interfere
vim.cmd("set noswapfile")
vim.cmd("set rtp+=./lua")
