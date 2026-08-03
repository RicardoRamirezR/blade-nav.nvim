--- lua/blade-nav/health.lua
-- Entry point for `:checkhealth blade-nav`. The Neovim >= 0.11 gate lives
-- here (matching the README requirement) so the rest of the report, which
-- relies on 0.11 APIs, never runs on an unsupported version.

local M = {}

function M.check()
  if vim.fn.has("nvim-0.11") == 0 then
    vim.health.error("blade-nav requires Neovim >= 0.11")
    return
  end

  require("blade-nav.integrations.health").check()
end

return M
