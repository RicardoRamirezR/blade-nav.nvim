local M = {}

function M.setup()
  require("blade-nav.gf").setup()
  require("blade-nav.cmp_blade").setup()
  require("blade-nav.cmp_php").setup()
end

return M
