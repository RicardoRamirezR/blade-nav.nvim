local M = {}

function M.setup(opts)
  opts = opts or {}
  require("blade-nav.gf").setup()
  require("blade-nav.cmp").setup(opts)
  require("blade-nav.coq").setup()
  -- Loading the blink integration is not required
end

return M
