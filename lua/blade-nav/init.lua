local M = {}

function M.setup(user_opts)
  require("blade-nav.gf").setup()
  require("blade-nav.cmp").setup(user_opts)
  require("blade-nav.coq").setup()
end

return M
