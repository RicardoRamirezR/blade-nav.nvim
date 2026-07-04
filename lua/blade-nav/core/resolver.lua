-- lua/blade-nav/core/resolver.lua
local targets = require("blade-nav.targets")
local log = require("blade-nav.utils.log")

local M = {}

--- Resolves the target based on the context.
--- @param context BladeNavContext
--- @return BladeNavTargetInfo | nil
function M.resolve(context)
  log.debug("Starting resolution process.")
  for _, handler_name in ipairs(targets.get_compatible_handlers(context)) do
    local handler = targets._handlers[handler_name]
    if handler and type(handler.get_target) == "function" then
      local ok, result = pcall(handler.get_target, context)
      if ok and result then
        log.debug("Target resolved by handler '%s': %s", handler_name, vim.inspect(result))
        return result
      elseif not ok then
        log.error("Handler '%s' failed with error: %s", handler_name, tostring(result))
      else
        log.debug("Handler '%s' did not match context.", handler_name)
      end
    else
      log.warn("Handler '%s' is invalid or missing 'get_target' function.", handler_name)
    end
  end
  log.debug("No target handler matched the context.")
  return nil
end

return M
