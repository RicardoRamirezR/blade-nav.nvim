-- lua/blade-nav/targets/directive.lua (Updated get_target function)

local config_module = require("blade-nav.core.config")
local fs = require("blade-nav.utils.fs")
local log = require("blade-nav.utils.log")
local shared = require("blade-nav.targets.shared")
local treesitter = require("blade-nav.utils.treesitter")

local M = {}

local STANDARD_VIEW_DIR = "resources/views/"
local DIRECTIVE_MULTI_PARAMS = {
  "@includeWhen",
  "@includeUnless",
  "@includeFirst",
}

function M.get_capabilities()
  return {
    targets = {
      "@component",
      "@each",
      "@extends",
      "@includeUnless",
      "@includeFirst",
      "@includeWhen",
      "@includeIf",
      "@include",
    },
    filetypes = { "blade" },
  }
end

--- Gets target information if the cursor is on a Blade directive that references a view.
--- Calculates potential file paths for the view name(s).
--- Implements logic: if file(s) exist, return them; else, return all potential paths.
--- Uses the sophisticated TS utility for parsing directive arguments.
--- @param context BladeNavContext Context created by context.lua
--- @return BladeNavTargetInfo|nil { type = "directive", name = "...", choices = { "path/1", "path/2" } } or nil
function M.get_target(context)
  if context.filetype ~= "blade" then
    log.debug("Invalid context for Blade directive handler.")
    return nil
  end

  if context.target and not vim.tbl_contains(M.get_capabilities().targets, context.target) then
    return nil
  end

  local directive_name, params = nil, nil
  if context.first_arg and not vim.tbl_contains(DIRECTIVE_MULTI_PARAMS, context.target) then
    directive_name = context.target
    params = { context.first_arg }
  else
    local line = context.line
    log.debug("Processing line for Blade directive: %s, target %s", line, context.target)
    directive_name, params = treesitter.extract_first_blade_argument(line, context.target)
  end

  if not directive_name or not params then
    log.debug("No matching navigable Blade directive found on line.")
    return nil
  end

  log.debug("Navigable directive '%s' found with params: %s", directive_name, vim.inspect(params))

  local root = fs.get_root_dir()
  local view_dirs_to_check = { root .. "/" .. STANDARD_VIEW_DIR }
  local config = config_module.get()

  local user_laravel_components_paths = config.laravel_components_paths or {}

  if type(user_laravel_components_paths) == "table" then
    for _, user_path in ipairs(user_laravel_components_paths) do
      if type(user_path) == "string" and user_path ~= "" then
        local normalized_path = user_path:gsub("/+$", "") .. "/"
        table.insert(view_dirs_to_check, root .. "/" .. normalized_path)
        log.debug("Added user-defined path to search list: %s", normalized_path)
      end
    end
  else
    log.debug("laravel_components_paths in config is not a table: %s", type(user_laravel_components_paths))
  end

  log.debug("Final view directories to check: %s", vim.inspect(view_dirs_to_check))

  local all_calculated_paths = {}
  local first_raw_name = nil

  for i, param_element in ipairs(params) do
    if type(param_element) == "string" then
      if not first_raw_name then
        first_raw_name = param_element
      end
      local candidates = shared.build_view_paths(param_element, view_dirs_to_check, ".blade.php")
      for _, candidate in ipairs(candidates) do
        table.insert(all_calculated_paths, candidate)
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

  local final_choices = shared.existing_or_all(fs, all_calculated_paths)

  log.debug(
    "Directive '%s' check complete. Total potentials: %d. Returning %d choice(s).",
    directive_name,
    #all_calculated_paths,
    #final_choices
  )

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
M.resolve = shared.noop_resolve("Directive")

return M
