-- lua/blade-nav/targets/livewire.lua

local fs = require("blade-nav.utils.fs")
local log = require("blade-nav.utils.log")
local shared = require("blade-nav.targets.shared")
local string_utils = require("blade-nav.utils.string")
local treesitter = require("blade-nav.utils.treesitter")

local M = {}

--- Pascal-cases each dot segment of a component identifier.
--- e.g. "admin.user-list" -> "Admin/UserList"
--- @param name string
--- @return string
local function pascal_case_path(name)
  local segments = vim.split(name, ".", { plain = true })
  local pascal_segments = {}
  for _, segment in ipairs(segments) do
    if segment ~= "" then
      table.insert(pascal_segments, string_utils.kebab_to_pascal(segment))
    end
  end
  return table.concat(pascal_segments, "/")
end

function M.get_capabilities()
  return {
    targets = { "livewire", "@livewire" },
    filetypes = { "blade" },
  }
end

--- Extracts the Livewire component identifier from the given line.
--- @param line string
--- @return string|nil Livewire component identifier, or nil if not found
local function extract_component_identifier(line)
  if not line or not line:find("livewire") then
    log.debug("Line does not contain 'livewire'. Skipping handler.")
    return nil
  end

  local directive_name, arguments = treesitter.extract_first_blade_argument(line, "@livewire")
  log.debug(
    "Tried extract_first_blade_argument('@livewire'), got directive: '%s', args: %s",
    tostring(directive_name),
    vim.inspect(arguments)
  )

  local component_identifier = nil
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

  return component_identifier
end

--- Gets target information if the cursor is on a Livewire component reference.
--- Supports <livewire:name />, @livewire('name'), Livewire::mount('name').
--- @param context BladeNavContext Context created by context.lua
--- @return BladeNavTargetInfo|nil { type = "livewire", name = "component.name", choices = { ... } } or nil
function M.get_target(context)
  if context.filetype ~= "blade" then
    log.debug("Not a Blade file.")
    return nil
  end
  if context.target and context.target ~= "livewire" and context.target ~= "@livewire" then
    return nil
  end

  local component_identifier
  if context.first_arg and context.target then
    component_identifier = context.first_arg
  else
    component_identifier = extract_component_identifier(context.line)
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

  local pascal_path = pascal_case_path(normalized_component_name)
  local kebab_case_name = normalized_component_name
  local root = fs.get_root_dir()

  local potential_paths = {
    string.format("%s/app/Livewire/%s.php", root, pascal_path),
    string.format("%s/app/Http/Livewire/%s.php", root, pascal_path),
    string.format("%s/resources/views/livewire/%s.blade.php", root, kebab_case_name:gsub("%.", "/")),
  }

  log.debug("Calculated potential paths for '%s': %s", normalized_component_name, vim.inspect(potential_paths))

  local final_choices, found_existing = shared.existing_or_all(fs, potential_paths)
  if not found_existing then
    log.debug("No existing Livewire files found. Returning potential paths and creation command.")
    table.insert(final_choices, {
      label = string.format("php artisan make:livewire %s", pascal_path),
      cmd = { "php", "artisan", "make:livewire", pascal_path },
    })
  else
    log.debug("Found %d existing Livewire file(s). Returning them.", #final_choices)
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
M.resolve = shared.noop_resolve("Livewire")

return M
