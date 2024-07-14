local M = {}

function M.setup()
  require("blade-nav.gf").setup()
  require("blade-nav.cmp").setup()
  require("blade-nav.coq").setup()
end

return M
