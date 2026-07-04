-- lua/blade-nav/targets/component.lua

local log = require("blade-nav.utils.log")
local shared = require("blade-nav.targets.shared")
local treesitter = require("blade-nav.utils.treesitter")
local laravel = require("blade-nav.utils.laravel")

local M = {}

function M.get_capabilities()
  return {
    targets = { "component" },
    filetypes = { "blade" },
  }
end

--- Gets target information for an <x-...> component.
--- @param context BladeNavContext Context created by context.lua
--- @return BladeNavTargetInfo|nil { type = "component", name = "...", choices = { ... } } or nil
function M.get_target(context)
  if context.filetype ~= "blade" then
    log.debug("Not a Blade file.")
    return nil
  end

  if context.target and context.target ~= "component" then
    return nil
  end
  local component_identifier = nil
  if context.first_arg then
    component_identifier = context.first_arg
  else
    local line = context.line
    if not line then
      log.debug("Invalid line.")
      return nil
    end

    log.debug("Processing line for <x-...> component: %s", line)

    component_identifier = treesitter.extract_component(line, "^x")
  end

  if not component_identifier or component_identifier == "" then
    log.debug("No <x-...> component found on line by utility.")
    return nil
  end

  log.debug("Matched component identifier: %s", component_identifier)

  local config = require("blade-nav.core.config").get()
  local custom_paths = config.laravel_components_paths or {}

  local choices = laravel.get_component_paths(component_identifier, custom_paths)

  if not choices or #choices == 0 then
    log.warn("No choices calculated for component '%s'.", component_identifier)
    return nil
  end

  return {
    type = "component",
    name = component_identifier,
    choices = choices,
  }
end

--- Resolves the component target.
--- @param target_info BladeNavTargetInfo The target info returned by get_target.
--- @return boolean True if successfully opened/action taken, false otherwise.
M.resolve = shared.noop_resolve("Component")

return M
