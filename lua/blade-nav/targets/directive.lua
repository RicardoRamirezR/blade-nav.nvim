-- lua/blade-nav/targets/directive.lua (Updated get_target function)
local log = require("blade-nav.utils.log")
local ts_utils = require("blade-nav.utils.treesitter") -- Import the new TS utility
local fs = require("blade-nav.utils.fs")
local config_module = require("blade-nav.core.config")

local M = {}

local STANDARD_VIEW_DIR = "resources/views/"

local function type_candidate(line)
  local types = {
    "@extends",
    "@includeUnless",
    "@includeFirst",
    "@includeWhen",
    "@includeIf",
    "@include",
    "@each",
    "@component",
  }
  for _, item in ipairs(types) do
    if line:find(item, 1, true) then
      return true, item
    end
  end
  return false, nil
end

--- Gets target information if the cursor is on a Blade directive that references a view.
--- Calculates potential file paths for the view name(s).
--- Implements logic: if file(s) exist, return them; else, return all potential paths.
--- Uses the sophisticated TS utility for parsing directive arguments.
--- @param context BladeNavContext Context created by context.lua
--- @return BladeNavTargetInfo|nil { type = "directive", name = "...", choices = { "path/1", "path/2" } } or nil
function M.get_target(context)
  local line = context.line
  local is_candidate, target_type = type_candidate(line)

  if not is_candidate or not target_type then
    log.debug("Line does not contain a recognized view candidate pattern.")
    return nil
  end
  -- Early return if context is invalid for this handler
  if not context.line or context.cursor_col_1 <= 0 or context.filetype ~= "blade" then
    log.debug("Invalid context for Blade directive handler.")
    return nil
  end

  local col_1 = context.cursor_col_1
  log.debug("Processing line for Blade directive: %s, target %s", line, target_type)

  -- Use the utility to parse the directive and its arguments.
  local directive_name, params = ts_utils.extract_first_blade_argument(line, target_type)

  -- Early return if no matching directive was found
  if not directive_name or not params then
    log.debug("No matching navigable Blade directive found on line.")
    return nil
  end

  log.debug("Navigable directive '%s' found with params: %s", directive_name, vim.inspect(params))

  -- Basic check: is the cursor roughly within the directive call?
  local directive_start = line:find(directive_name, 1, true)
  if not directive_start or col_1 < directive_start or col_1 > (directive_start + #directive_name + 50) then
    log.debug("Cursor NOT within estimated directive area for '%s'.", directive_name)
    return nil
  end

  log.debug("Cursor within estimated directive area.")

  -- --- Dynamic VIEW_DIRS Construction ---
  -- Start with the standard Laravel view directory
  local view_dirs_to_check = { STANDARD_VIEW_DIR }

  -- Get the current plugin configuration
  local config = config_module.get() -- Assuming this returns the merged config table

  -- Check for user-defined additional component/search paths
  -- This corresponds to vim.g.blade_nav.laravel_components
  local user_laravel_components_paths = config.laravel_components_paths or config.laravel_components or
  {}                                                                                                       -- Check both potential names

  -- Add user-defined paths, ensuring they end with '/'
  if type(user_laravel_components_paths) == "table" then
    for _, user_path in ipairs(user_laravel_components_paths) do
      if type(user_path) == "string" and user_path ~= "" then
        local normalized_path = user_path:gsub("/+$", "") .. "/" -- Ensure trailing slash
        table.insert(view_dirs_to_check, normalized_path)
        log.debug("Added user-defined path to search list: %s", normalized_path)
      end
    end
  else
    log.debug(
      "laravel_components_paths/laravel_components in config is not a table: %s",
      type(user_laravel_components_paths)
    )
  end

  log.debug("Final view directories to check: %s", vim.inspect(view_dirs_to_check))

  -- --- Iterate through ALL elements in params to build choices ---
  local all_calculated_paths = {}
  local first_raw_name = nil

  for i, param_element in ipairs(params) do
    if type(param_element) == "string" then
      if not first_raw_name then
        first_raw_name = param_element
      end
      -- Calculate potential paths for this argument across ALL configured view directories
      local normalized_relative_path = param_element:gsub("%.", "/") .. ".blade.php"
      for _, view_dir in ipairs(view_dirs_to_check) do
        local full_path = view_dir .. normalized_relative_path
        table.insert(all_calculated_paths, full_path)
        log.debug("Calculated potential path for argument %d ('%s') in '%s': %s", i, param_element, view_dir, full_path)
      end
    else
      log.debug(
        "Ignoring non-string argument %d in params for directive '%s': %s",
        i,
        directive_name,
        type(param_element)
      )
    end
  end

  if #all_calculated_paths == 0 then
    log.debug("No valid string arguments found in params for directive '%s' to calculate paths.", directive_name)
    return nil
  end

  -- --- CORE LOGIC: Filter paths based on file existence ---
  local existing_paths = {}
  for _, path in ipairs(all_calculated_paths) do
    if fs.path_exists(path) and not fs.is_dir(path) then
      table.insert(existing_paths, path)
      log.debug("Found existing view file: %s", path)
    else
      log.debug("View file does not exist or is a directory: %s", path)
    end
  end

  -- --- Choice Selection based on existence ---
  local final_choices = (#existing_paths > 0) and existing_paths or all_calculated_paths

  log.debug(
    "Directive '%s' check complete. Existing files: %d. Total potentials: %d. Returning %d choice(s).",
    directive_name,
    #existing_paths,
    #all_calculated_paths,
    #final_choices
  )

  -- Package the result
  local result = {
    type = "directive",
    name = first_raw_name or "",
    choices = final_choices,
  }

  log.debug("Matched directive '%s'. Final choices: %s", directive_name, vim.inspect(result.choices))
  return result
end

-- The resolve function is no longer needed/used by the core system
-- because targets/init.lua handles single choices and delegates multiples to show_choices.
M.resolve = function(target_info)
  -- No-op or log if called unexpectedly
  log.warn("Directive handler resolve function called unexpectedly. Target info: %s", vim.inspect(target_info))
  return false
end

return M
