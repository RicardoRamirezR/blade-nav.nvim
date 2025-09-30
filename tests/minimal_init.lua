-- tests/minimal_init.lua

-- Get the current directory (project root)
local project_root = vim.fn.getcwd()

-- Add project to runtimepath
vim.opt.runtimepath:prepend(project_root)

-- Determine Plenary location (try lazy.nvim first, then vendor)
local plenary_dir = vim.fn.stdpath("data") .. "/lazy/plenary.nvim"
if vim.fn.isdirectory(plenary_dir) == 0 then
  plenary_dir = vim.fn.stdpath("data") .. "/site/pack/vendor/start/plenary.nvim"
end

-- Clone Plenary if it doesn't exist (useful for CI)
if vim.fn.isdirectory(plenary_dir) == 0 then
  vim.fn.system({
    "git",
    "clone",
    "--depth=1",
    "https://github.com/nvim-lua/plenary.nvim",
    plenary_dir,
  })
end

-- Add Plenary to runtimepath
vim.opt.rtp:append(plenary_dir)

-- Configure basic settings for headless mode
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.writebackup = false

-- Load plenary commands
vim.cmd("runtime! plugin/plenary.vim")

-- Optional: configure nvim-treesitter if available but disable problematic features
pcall(function()
  require("nvim-treesitter.configs").setup({
    ensure_installed = { "blade", "php", "html", "vue" },
    sync_install = true,
    highlight = { enable = false },
    indent = { enable = false },
    autopairs = { enable = false },
    autotag = { enable = false },
  })
end)

-- Debug info (optional, puedes comentar estas líneas después)
-- print("Plenary path:", plenary_dir)
-- print("Plenary exists:", vim.fn.isdirectory(plenary_dir))
