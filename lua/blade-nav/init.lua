local M = {}

function M.setup(opts)
  opts = opts or {}
  require("blade-nav.gf").setup()
  require("blade-nav.cmp").setup(opts)
  require("blade-nav.coq").setup()
end

return M
