-- lua/blade-nav/utils/laravel/init.lua
local uv = vim.uv

local cache = require("blade-nav.utils.cache")
local fs = require("blade-nav.utils.fs")
local log = require("blade-nav.utils.log")

local routes = require("blade-nav.utils.laravel.routes")
local completions = require("blade-nav.utils.laravel.completions")

local M = {}

local VIEW_DIRS = {
  "resources/views/",
}

--- Get PSR-4 mappings from composer.json.
--- @return table<string, string>|nil Map of namespace to path, or nil on error
function M.get_psr4_mappings()
  local cache_key = "psr4_mappings"
  local cached = cache.get(cache_key, math.huge)
  if cached then
    return cached
  end

  local root = fs.get_root_dir()
  local composer_data = fs.read_file(root .. "/composer.json")
  if not composer_data then
    log.warn("composer.json not found or unreadable.")
    return {}
  end

  local ok, parsed = pcall(vim.json.decode, composer_data)
  if not ok or not parsed then
    log.error("Failed to parse composer.json: %s", tostring(parsed))
    return {}
  end

  local psr4 = parsed.autoload and parsed.autoload["psr-4"]
  if not psr4 then
    log.debug("No PSR-4 mappings found in composer.json.")
    psr4 = {}
  end

  return cache.set(cache_key, psr4)
end

--- Normalize a Blade view name (dot/slash conversion).
--- @param view_name string View name (e.g., "user.profile", "user/profile")
--- @return string Normalized path (e.g., "user/profile.blade.php")
function M.normalize_view_name(view_name)
  if not view_name then
    return nil
  end

  local normalized = view_name:gsub("%.blade%.php$", "")
  normalized = normalized:gsub("%.", "/")
  if not normalized:match("%.blade%.php$") then
    normalized = normalized .. ".blade.php"
  end
  return normalized
end

--- Get all Blade view file names.
--- @return table List of view names.
function M.get_blade_files()
  local cache_key = "blade_files"
  local cached = cache.get(cache_key)
  if cached then
    return cached
  end

  local files = {}
  for _, view_dir in ipairs(VIEW_DIRS) do
    local result = fs.find_files(view_dir, "blade.php")
    if result then
      for _, file in ipairs(result) do
        local relative_path = file:match(vim.pesc(view_dir) .. "(.*)%.blade%.php$")
        if relative_path then
          local normalized_name = relative_path:gsub("/", ".")
          table.insert(files, normalized_name)
        end
      end
    end
  end

  return cache.set(cache_key, files)
end

--- If any standard path exists, returns only the existing ones.
--- If none exist, returns all standard paths plus the creation command.
--- @param component_identifier string The component name (e.g., 'button', 'input.date').
--- @param custom_search_paths? table Optional list of additional base paths to search.
--- @return table List of file paths or commands to present as choices.
function M.get_component_paths(component_identifier, custom_search_paths)
  custom_search_paths = custom_search_paths or {}
  local final_choices = {}

  if not component_identifier or component_identifier == "" then
    log.debug("get_component_paths called with empty identifier.")
    return final_choices
  end

  local base_name = component_identifier:match("^([^.]+)") or component_identifier
  local sub_path = component_identifier:gsub("^" .. vim.pesc(base_name), ""):gsub("^%.", "/")
  local studly_case_name = base_name:gsub("%-([%w])", string.upper):gsub("^%l", string.upper)

  local class_file_path = "app/View/Components/" .. studly_case_name .. sub_path .. ".php"
  local anon_view_path = "resources/views/components/" .. component_identifier:gsub("%.", "/") .. ".blade.php"
  local anon_index_path = "resources/views/components/" .. component_identifier:gsub("%.", "/") .. "/index.blade.php"

  local all_standard_paths = {
    anon_view_path,
    anon_index_path,
    class_file_path,
  }

  local existing_standard_paths = {}
  for _, path in ipairs(all_standard_paths) do
    if path == anon_index_path then
      local dir_path = path:gsub("/index%.blade%.php$", "")
      if fs.path_exists(dir_path) and fs.is_dir(dir_path) and fs.path_exists(path) and not fs.is_dir(path) then
        table.insert(existing_standard_paths, path)
      end
    else
      if fs.path_exists(path) and not fs.is_dir(path) then
        table.insert(existing_standard_paths, path)
      end
    end
  end

  if #existing_standard_paths > 0 then
    log.debug(
      "Component '%s' has %d existing standard path(s). Returning them.",
      component_identifier,
      #existing_standard_paths
    )
    final_choices = existing_standard_paths
  else
    log.debug(
      "Component '%s' has no existing standard paths. Returning all options including creation.",
      component_identifier
    )
    for _, path in ipairs(all_standard_paths) do
      table.insert(final_choices, path)
    end
    local pascal_case_component = base_name:gsub("%-([%w])", string.upper):gsub("^%l", string.upper)
    local make_command = "php artisan make:component " .. pascal_case_component
    table.insert(final_choices, make_command)
  end

  if #existing_standard_paths > 0 then
    for _, custom_base_path in ipairs(custom_search_paths) do
      local normalized_custom_path = custom_base_path:gsub("/$", "")
      local custom_view_path = normalized_custom_path
        .. "/components/"
        .. component_identifier:gsub("%.", "/")
        .. ".blade.php"
      if fs.path_exists(custom_view_path) and not fs.is_dir(custom_view_path) then
        table.insert(final_choices, custom_view_path)
      end
    end
  end

  log.debug("Final choices for component '%s': %s", component_identifier, vim.inspect(final_choices))
  return final_choices
end

--- Check if the BladeNav artisan command exists.
--- @return boolean
function M.check_blade_command()
  local cache_key = "blade_command_exists"
  local cached = cache.get(cache_key)
  if cached ~= nil then
    return cached
  end

  local root_dir = fs.get_root_dir()
  local exists = fs.path_exists(root_dir .. "/app/Console/Commands/BladeNav.php")
  return cache.set(cache_key, exists)
end

--- Get the PSR-4 application namespace.
--- @return string
function M.psr4_app()
  local psr4_mappings = M.get_psr4_mappings()
  for namespace, path in pairs(psr4_mappings) do
    if path == "app/" or path == "app" then
      return namespace
    end
  end
  return "App\\"
end

--- Modify namespace in content.
--- @param content string
--- @param psr4 string
--- @return string
function M.modify_namespace(content, psr4)
  if psr4 ~= "App\\" then
    local output, _ = content:gsub("namespace App\\Console\\Commands;", "namespace " .. psr4 .. "Console\\Commands;")
    return output
  end
  return content
end

--- Get the BladeNav.php filename.
--- @return string
function M.get_blade_nav_filename()
  local script_path = debug.getinfo(1, "S").source:sub(2)
  local script_dir = vim.fn.fnamemodify(script_path, ":p:h")
  return script_dir .. "/../../../BladeNav.php"
end

--- Convert kebab-case to PascalCase.
--- @param input string
--- @return string
function M.kebab_to_pascal(input)
  return require("blade-nav.utils.string").kebab_to_pascal(input)
end

--- Detect if current working directory looks like a Laravel project.
--- Heuristics: artisan, or composer.json with laravel/framework|lumen,
--- or typical Laravel paths.
--- @param cwd string|nil
--- @return boolean
function M.is_laravel_project(cwd)
  local root_dir = cwd or fs.get_root_dir()
  if not root_dir or root_dir == "" then
    root_dir = (uv and uv.cwd()) or vim.fn.getcwd() or "."
  end
  local function P(p)
    return root_dir .. "/" .. p
  end

  if fs.path_exists(P("artisan")) then
    return true
  end
  if fs.path_exists(P("routes/web.php")) then
    return true
  end
  if fs.path_exists(P("resources/views")) then
    return true
  end
  if fs.path_exists(P("composer.json")) then
    local contents = fs.read_file(P("composer.json"))
    if contents then
      local ok, data = pcall(vim.json.decode, contents)
      if ok and data and data.require then
        if data.require["laravel/framework"] or data.require["laravel/lumen-framework"] then
          return true
        end
      end
    end
  end
  return false
end

-- Re-exports from routes
M.get_route_list = routes.get_route_list
M.get_route_names = routes.get_route_names
M.invalidate_routes_cache = routes.invalidate_routes_cache
M.__test_build_route_map = routes.__test_build_route_map

-- Re-exports from completions
M.get_view_names = completions.get_view_names
M.__health_check_views = completions.__health_check_views

return M
