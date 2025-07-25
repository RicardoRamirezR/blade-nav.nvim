-- lua/blade-nav/targets/xcomponent.lua (Simplified handler)

local log = require("blade-nav.utils.log")
local ts_utils = require("blade-nav.utils.treesitter")
local laravel_utils = require("blade-nav.utils.laravel")
-- local fs = require("blade-nav.utils.fs") -- No longer needed directly here

local M = {}

--- Gets target information for an <x-...> component.
--- Delegates path/choice calculation to laravel_utils.get_component_paths.
--- @param context BladeNavContext Context created by context.lua
--- @return BladeNavTargetInfo|nil { type = "xcomponent", name = "...", choices = { ... } } or nil
function M.get_target(context)
  if context.filetype ~= "blade" then
    log.debug("Not a Blade file.")
    return nil
  end

  local line = context.line
  if not line then
    log.debug("Invalid line.")
    return nil
  end

  log.debug("Processing line for <x-...> component: %s", line)

  local component_identifier = ts_utils.extract_component(line, "^x")

  if not component_identifier or component_identifier == "" then
    log.debug("No <x-...> component found on line by utility.")
    return nil
  end

  log.debug("Matched component identifier: %s", component_identifier)

  -- --- Get the appropriate choices from the shared Laravel utility ---
  local config = require("blade-nav.core.config").get() -- Get current config
  local custom_paths = config.laravel_components_paths or {}

  -- Call the utility function that now encapsulates the full logic
  local choices = laravel_utils.get_component_paths(component_identifier, custom_paths)

  if not choices or #choices == 0 then
    log.warn("No choices calculated for component '%s'.", component_identifier)
    -- Returning nil stops processing by this handler
    return nil
  end

  -- Package the target information. The 'choices' list is already prepared.
  return {
    type = "xcomponent",
    name = component_identifier,
    choices = choices, -- This list is correctly prepared by the utility
  }
end

--- Resolves the component target.
--- The core logic is in laravel_utils.get_component_paths called by get_target.
--- This function might handle edge cases or specific resolve actions not covered by choices.
--- @param target_info BladeNavTargetInfo The target info returned by get_target.
--- @return boolean True if successfully opened/action taken, false otherwise.
function M.resolve(target_info)
  -- If get_target correctly provided 'choices', the core system (targets/init.lua)
  -- should handle showing them or opening a single file.
  -- This resolve function is called if choices don't lead to direct action
  -- or if target_info.resolved ~= true.

  if not target_info or target_info.type ~= "xcomponent" then
    log.warn("xcomponent resolve called with invalid target_info: %s", vim.inspect(target_info))
    return false
  end

  -- If we reach here, it implies the core system decided to call resolve,
  -- perhaps because choices logic wasn't sufficient or returned a special state.
  -- For the standard case handled by get_component_paths, this might just log
  -- and return false, letting the core decide the next step based on the original target_info.

  log.debug(
    "xcomponent resolve called for target: %s. This handler relies on core system resolution via choices.",
    target_info.name or "unknown"
  )

  -- Example: If the utility returned choices but the core system wants
  -- the handler to have the final say in resolution (e.g., based on more context),
  -- that logic would go here. Otherwise, it's often a no-op or fallback.

  -- For now, let the core system handle it based on the choices provided by get_target.
  -- If the core logic is correct (resolve_target checks choices if resolve returns false),
  -- returning false here should be fine.
  return false
end

return M
