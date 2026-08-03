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

-- Tree-sitter parsers (php, blade, html, vue) must be available on the
-- runtimepath. CI compiles them ahead of time into site/parser (see
-- .github/actions/compile-parsers); locally, install them with :TSInstall.
-- Note: nvim-treesitter's own setup() is intentionally NOT called here: on
-- its `main` branch the `configs` module no longer exists, and on `master`
-- ensure_installed would trigger synchronous network installs during tests.
