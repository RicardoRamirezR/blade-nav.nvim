-- lua/blade-nav/targets/view.lua

local fs = require("blade-nav.utils.fs")
local log = require("blade-nav.utils.log")
local treesitter = require("blade-nav.utils.treesitter")

local M = {}

local VIEW_DIR = "resources/views/"

function M.get_capabilities()
  return {
    targets = { "markdown", "Route::view", "View::make", "view" },
    filetypes = { "blade", "php" },
  }
end

--- Checks if the line contains a recognizable view-related function call or directive pattern.
--- @param line string The line of text.
--- @return boolean, string|nil True and the target type ("view", "route", "markdown") if found, false/nil otherwise.
local function type_candidate(line)
  -- stylua: ignore start
  local types = {
    { pattern = "Route::view" , target_type = "route" },
    { pattern = "View::make"  , target_type = "view" },
    { pattern = "view"        , target_type = "view" },
    { pattern = "markdown"    , target_type = "markdown" },
    -- stylua: ignore end
  }

  for _, item in ipairs(types) do
    if line:find(item.pattern, 1, true) then
      return true, item.target_type
    end
  end
  return false, nil
end

--- Gets target information if the cursor is on a view reference (function calls).
--- Calculates potential file paths and filters based on existence.
--- @param context BladeNavContext Context created by context.lua
--- @return BladeNavTargetInfo|nil { type = "view", name = "normalized.view.name", choices = { "path/1", ... } } or nil
function M.get_target(context)
  local line = context.line

  if not line then
    log.debug("Invalid line in context.")
    return nil
  end

  local is_candidate, target_type = type_candidate(line)
  if not is_candidate or not target_type then
    log.debug("Line does not contain a recognized view candidate pattern.")
    return nil
  end

  local raw_view_name = nil
  if context.first_arg and context.target then
    raw_view_name = context.first_arg
  end

  log.debug("Line identified as candidate type: %s", target_type)

  if not raw_view_name then
    local found_keys = treesitter.extract_keys_from_code(line, target_type)

    log.debug("Found keys: %s", vim.inspect(found_keys))
    if not found_keys or type(found_keys) ~= "table" or #found_keys == 0 then
      log.debug("No view keys found by ts_utils.extract_keys_from_code for type '%s'.", target_type)
      return nil
    end

    raw_view_name = found_keys[1]
  end

  if not raw_view_name or type(raw_view_name) ~= "string" or raw_view_name == "" then
    log.debug("Last extracted key is invalid or not a string: %s", vim.inspect(raw_view_name))
    return nil
  end

  log.debug("Extracted primary view name: %s", raw_view_name)

  local normalized_relative_path = raw_view_name:gsub("%.", "/") .. ".blade.php"
  local path = VIEW_DIR .. normalized_relative_path

  local existing_paths = {}
  if fs.path_exists(path) and not fs.is_dir(path) then
    table.insert(existing_paths, path)
    log.debug("Found existing view file: %s", path)
  else
    log.debug("View file does not exist or is a directory: %s", path)
  end

  local final_choices = {}
  if #existing_paths > 0 then
    log.debug("Found %d existing view file(s). Returning them as choices.", #existing_paths)
    final_choices = existing_paths
  else
    final_choices = { path }
  end

  local result = {
    type = "view",
    name = raw_view_name,
    choices = final_choices,
  }

  log.debug("Matched view reference. Final choices: %s", vim.inspect(result.choices))
  return result
end

-- The resolve function is no longer the primary way this handler resolves targets
-- for simple file opening. The logic is handled in get_target and delegated to the core.
-- Keeping it as a no-op or removing it is acceptable.
M.resolve = function(target_info)
  log.warn("View handler resolve function called unexpectedly. Target info: %s", vim.inspect(target_info))
  return false
end

return M
