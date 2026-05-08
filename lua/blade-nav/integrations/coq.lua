-- lua/blade-nav/integrations/coq.lua
local log = require("blade-nav.utils.log")

local M = {}

function M.setup()
  local has_coq, _ = pcall(require, "coq")
  if not has_coq then
    log.debug("coq.nvim not found, skipping BladeNav coq source setup.")
    return
  end

  local ok, err = pcall(require, "blade-nav.integrations.coq_source")
  if not ok then
    log.error("Failed to load BladeNav coq source: %s", tostring(err))
  else
    log.info("BladeNav coq.nvim source registered.")
  end
end

return M
