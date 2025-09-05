-- lua/blade-nav/targets/livewire.lua

local fs = require("blade-nav.utils.fs")
local log = require("blade-nav.utils.log")
local string_utils = require("blade-nav.utils.string")
local treesitter = require("blade-nav.utils.treesitter")

local M = {}

--- Gets target information if the cursor is on a Livewire component reference.
--- Supports <livewire:name />, @livewire('name'), Livewire::mount('name').
--- @param context BladeNavContext Context created by context.lua
--- @return BladeNavTargetInfo|nil { type = "livewire", name = "component.name", choices = { ... } } or nil
function M.get_target(context)
  local line = context.line
  if not line or not line:find("livewire") then
    log.debug("Line does not contain 'livewire'. Skipping handler.")
    return nil
  end

  local component_identifier = nil
  local directive_name, arguments = treesitter.extract_first_blade_argument(line, "@livewire")
  log.debug(
    "Tried extract_first_blade_argument('@livewire'), got directive: '%s', args: %s",
    tostring(directive_name),
    vim.inspect(arguments)
  )

  if directive_name and arguments and type(arguments) == "table" and #arguments > 0 then
    local first_arg = arguments[1]
    if type(first_arg) == "string" and first_arg ~= "" then
      component_identifier = first_arg
      log.debug("Successfully extracted component identifier from @livewire: '%s'", component_identifier)
    end
  end

  if not component_identifier or component_identifier == "" then
    component_identifier = treesitter.extract_component(line, "livewire")
    log.debug("Tried extract_component('livewire'), got: %s", tostring(component_identifier))
  end

  if not component_identifier or component_identifier == "" then
    log.debug("No Livewire component identifier found on line by utility functions.")
    return nil
  end

  log.debug("Matched Livewire component identifier: %s", component_identifier)

  local normalized_component_name = component_identifier
  if component_identifier:sub(1, #"livewire:") == "livewire:" then
    normalized_component_name = component_identifier:sub(#"livewire:" + 1)
  end

  normalized_component_name = normalized_component_name:gsub("^['\"](.*)['\"]$", "%1"):gsub("^%s+", ""):gsub("%s+$", "")
  log.debug("Normalized component name: %s", normalized_component_name)

  if normalized_component_name == "" then
    log.debug("Normalized component name is empty.")
    return nil
  end

  local pascal_case_name = string_utils.kebab_to_pascal(normalized_component_name)
  local kebab_case_name = normalized_component_name

  local potential_paths = {
    string.format("app/Livewire/%s.php", pascal_case_name:gsub("%.", "/")),
    string.format("app/Http/Livewire/%s.php", pascal_case_name:gsub("%.", "/")),
    string.format("resources/views/livewire/%s.blade.php", kebab_case_name:gsub("%.", "/")),
  }

  log.debug("Calculated potential paths for '%s': %s", normalized_component_name, vim.inspect(potential_paths))

  local existing_paths = {}
  for _, path in ipairs(potential_paths) do
    if fs.path_exists(path) and not fs.is_dir(path) then
      table.insert(existing_paths, path)
      log.debug("Found existing Livewire file: %s", path)
    else
      log.debug("Livewire file does not exist: %s", path)
    end
  end

  local final_choices = {}
  if #existing_paths > 0 then
    log.debug("Found %d existing Livewire file(s). Returning them.", #existing_paths)
    final_choices = existing_paths
  else
    log.debug("No existing Livewire files found. Returning potential paths and creation command.")
    for _, path in ipairs(potential_paths) do
      table.insert(final_choices, path)
    end
    table.insert(final_choices, string.format("php artisan make:livewire %s", pascal_case_name))
  end

  local result = {
    type = "livewire",
    name = normalized_component_name,
    choices = final_choices,
  }

  log.debug("Returning target info with choices: %s", vim.inspect(result))
  return result
end

-- The resolve function is no needed/used by the core system
-- because targets/init.lua handles single choices and delegates multiples to show_choices.
M.resolve = function(target_info)
  -- No-op or log if called unexpectedly
  log.warn("Directive handler resolve function called unexpectedly. Target info: %s", vim.inspect(target_info))
  return false
end

return M
