-- tests/minimal_init.lua

-- Get the current directory (project root)
local project_root = vim.fn.getcwd()

-- Add project to runtimepath
vim.opt.runtimepath:prepend(project_root)

-- The plugins installed in site/pack/vendor/start will be loaded automatically
-- No need to manually add them to runtimepath

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
    -- Disable other potentially problematic features
    autopairs = { enable = false },
    autotag = { enable = false },
  })
end)
