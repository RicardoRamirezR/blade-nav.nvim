-- lua/blade-nav/integrations/coq.lua
local log = require("blade-nav.utils.log")

local M = {}

--- Setup the coq.nvim integration.
function M.setup()
  -- Check if coq.nvim is available
  local has_coq, _ = pcall(require, "coq")
  if not has_coq then
    log.debug("coq.nvim not found, skipping BladeNav coq source setup.")
    return
  end

  -- If coq is available, load the source definition
  -- The source itself seems to be defined in a separate file like coq_all.lua
  -- in the provided snippets. We just need to trigger its loading.
  local ok, err = pcall(require, "blade-nav.integrations.coq_source") -- Or coq_all
  if not ok then
    log.error("Failed to load BladeNav coq source: %s", tostring(err))
  else
    log.info("BladeNav coq.nvim source registered.")
  end
end

return M
