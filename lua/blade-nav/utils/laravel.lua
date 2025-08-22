-- lua/blade-nav/utils/laravel.lua
local uv = vim.loop
local fs = require("blade-nav.utils.fs")
local cmd = require("blade-nav.utils.cmd")
local cache = require("blade-nav.utils.cache")
local log = require("blade-nav.utils.log")
local tbl = require("blade-nav.utils.table")
local debounce = require("blade-nav.utils.debounce")

local M = {}

local routes_watcher = nil
local route_cache_watcher = nil
local primed = false

local VIEW_DIRS = {
  "resources/views/",
}

--- Find all views names
--- @param path string
--- @param exclude_dirs? table
--- @return table
local function find_views_names(path, exclude_dirs)
  local cache_key = "find_view_names:" .. path
  local cached = cache.get(cache_key)
  if cached then
    return cached
  end

  local result = fs.find_files(path, "blade.php", exclude_dirs)
  if not result or result == "" then
    return {}
  end

  local views = {}
  for filename in result:gmatch("[^\r\n ]+") do
    local view = filename:match(path .. "(.+)")
    if view then
      view = view:gsub("^/", ""):gsub("%.blade%.php$", ""):gsub("/", ".")
      table.insert(views, view)
    end
  end

  return cache.set(cache_key, views)
end

--- Find all components view
--- @return table
local function find_components()
  return find_views_names("resources/views/components")
end
---
--- Find all livewire views
--- @return table
local function find_livewire()
  return find_views_names("resources/views/livewire")
end

-- Find all routes
-- @return table
local function find_routes()
  return M.get_route_names()
end

--- Find all views excliding livewire abd Laravel components
--- @return table
local function find_views()
  return find_views_names("resources/views", { "resources/views/livewire", "resources/views/components" })
end

--- Get PSR-4 mappings from composer.json.
--- @return table<string, string>|nil Map of namespace to path, or nil on error
function M.get_psr4_mappings()
  local cache_key = "psr4_mappings"
  local cached = cache.get(cache_key, math.huge)
  if cached then
    return cached
  end

  local composer_data = fs.read_file("composer.json")
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

-- Invalidate *all* cached routes
local function invalidate_routes_cache()
  log.debug("Invalidating all cached routes")
  cache.clear_prefix("route_list:") -- needs support in cache module
end

local debounced_invalidate = debounce(function()
  invalidate_routes_cache()
end, 200)

-- Watch the bootstrap/cache dir and attach to any routes-v*.php file
local function watch_route_cache()
  if route_cache_watcher then
    return -- already watching
  end

  local handle, err = uv.new_fs_event()
  if not handle then
    log.error("Failed to create fs_event handle: %s", err or "unknown")
    return
  end

  local ok, start_err = pcall(handle.start, handle, "bootstrap/cache", {}, function(err2, fname, events)
    if err2 then
      vim.schedule(function()
        log.error("Route cache dir watcher error: %s", err2)
      end)
      return
    end

    -- Only care about routes-v*.php files
    if fname and fname:match("^routes%-v%d+%.php$") then
      vim.schedule(function()
        local file_path = "bootstrap/cache/" .. fname
        local exists = vim.loop.fs_stat(file_path) ~= nil
        log.debug("Route cache file event: %s exists=%s events=%s", file_path, tostring(exists), events or "?")

        debounced_invalidate()

        if not exists then
          log.debug("Route cache file removed: %s", file_path)
        else
          log.debug("Route cache file created or modified: %s", file_path)
        end
      end)
    end
  end)

  if not ok then
    log.error("Failed to start fs_event for bootstrap/cache: %s", tostring(start_err))
  else
    route_cache_watcher = handle
    log.debug("Watching bootstrap/cache dir for route cache changes")
  end
end

-- Start watching `routes/` dir
local function watch_routes_dir()
  if routes_watcher then
    return
  end

  local handle, err = uv.new_fs_event()
  if not handle then
    log.error("Failed to create fs_event handle: %s", err or "unknown")
    return
  end

  local ok, start_err = pcall(handle.start, handle, "routes", {}, function(err2, filename, events)
    if err2 then
      log.error("Route watcher error: %s", err2)
      return
    end
    log.info("Detected change in routes/%s (events=%s), invalidating route cache", filename or "?", events or "?")
    debounced_invalidate()
  end)

  if not ok then
    log.error("Failed to start fs_event on routes/: %s", tostring(start_err))
  else
    routes_watcher = handle
    log.debug("Watching routes/ directory for changes")
  end
end

local function build_route_map(routes)
  local map = {}
  for _, r in ipairs(routes) do
    if r.name and r.action then
      local controller_method = vim.split(r.action, "@")
      map[r.name] = {
        controller = controller_method[1],
        method = controller_method[2],
      }
    end
  end
  return map
end

local function prime_routes(routes)
  local all_out, ok_all = cmd.execute_silent({
    "php",
    "artisan",
    "route:list",
    "--json",
    "--columns=name,action",
  })

  local primed_map
  if ok_all then
    local ok_parse, all_routes = pcall(vim.json.decode, all_out)
    if ok_parse and type(all_routes) == "table" then
      primed_map = build_route_map(all_routes)
      cache.set("route_list:primed", primed_map)
      log.debug("Primed cache with %d routes", vim.tbl_count(primed_map))
    end
  end

  return primed_map
end

--- Get route list from `php artisan route:list --json`.
--- @param route_name string|nil Route name
--- @return table|nil List of route objects, or nil on error
function M.get_route_list(route_name)
  local primed_routes = cache.get("route_list:primed", math.huge)
  if primed_routes then
    log.debug("Cache primed")
    if route_name then
      if primed_routes[route_name] then
        return { [route_name] = primed_routes[route_name] }
      else
        return {}
      end
    end
    return primed_routes
  end

  if not route then
    return prime_routes()
  end

  if not fs.command_exists("php") then
    log.warn("'php' command not found.")
    return {}
  end

  -- Ensure watcher started
  watch_routes_dir()
  watch_route_cache()

  local output, ok = cmd.execute_silent({
    "php",
    "artisan",
    "route:list",
    "--name=" .. route_name,
    "--json",
    "--columns=name,action",
  })
  if not ok then
    log.warn("Failed to execute 'php artisan route:list --json'. Output: %s", output or "nil")
    return {}
  end

  local route_map = {}

  local ok_parse, routes = pcall(vim.json.decode, output)
  if ok_parse and type(routes) == "table" then
    route_map = build_route_map(routes)
  end

  vim.schedule(function()
    log.debug("Priming global route cache in background...")
    prime_routes()
  end)

  return route_map
end

--- Normalize a Blade view name (dot/slash conversion).
--- @param view_name string View name (e.g., "user.profile", "user/profile")
--- @return string Normalized path (e.g., "user/profile.blade.php")
function M.normalize_view_name(view_name)
  if not view_name then
    return nil
  end

  local normalized = view_name:gsub("%.blade%.php$", "") -- Remove .blade.php if present
  normalized = normalized:gsub("%.", "/")                -- Convert dots to slashes
  if not normalized:match("%.blade%.php$") then
    normalized = normalized .. ".blade.php"              -- Ensure .blade.php suffix
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
    if result and result ~= "" then
      for file in result:gmatch("[^\r\n]+") do
        local relative_path = file:match(view_dir .. "(.*)%.blade%.php$")
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

  -- 1. Calculate all potential standard paths
  local base_name = component_identifier:match("^([^.]+)") or component_identifier
  local sub_path = component_identifier:gsub("^" .. base_name, ""):gsub("^%.", "/")
  local studly_case_name = base_name:gsub("%-([%w])", string.upper):gsub("^%l", string.upper)

  local class_file_path = "app/View/Components/" .. studly_case_name .. sub_path .. ".php"
  local anon_view_path = "resources/views/components/" .. component_identifier:gsub("%.", "/") .. ".blade.php"
  local anon_index_path = "resources/views/components/" .. component_identifier:gsub("%.", "/") .. "/index.blade.php"

  local all_standard_paths = {
    anon_view_path,
    anon_index_path, -- Check index path existence
    class_file_path,
  }

  -- 2. Check for existence of standard paths
  local existing_standard_paths = {}
  for _, path in ipairs(all_standard_paths) do
    -- Special check for index path: directory must exist and contain index.blade.php
    if path == anon_index_path then
      local dir_path = path:gsub("/index%.blade%.php$", "")
      if fs.path_exists(dir_path) and fs.is_dir(dir_path) and fs.path_exists(path) and not fs.is_dir(path) then
        table.insert(existing_standard_paths, path)
      end
    else
      -- Check regular file paths
      if fs.path_exists(path) and not fs.is_dir(path) then
        table.insert(existing_standard_paths, path)
      end
    end
  end

  -- 3. Determine final choices based on existence
  if #existing_standard_paths > 0 then
    -- If any standard path exists, return only the existing ones.
    log.debug(
      "Component '%s' has %d existing standard path(s). Returning them.",
      component_identifier,
      #existing_standard_paths
    )
    final_choices = existing_standard_paths
  else
    -- If no standard paths exist, return all standard paths + creation command.
    log.debug(
      "Component '%s' has no existing standard paths. Returning all options including creation.",
      component_identifier
    )
    -- Add standard paths to choices
    for _, path in ipairs(all_standard_paths) do
      table.insert(final_choices, path)
    end
    -- Add creation command
    local pascal_case_component = base_name:gsub("%-([%w])", string.upper):gsub("^%l", string.upper)
    local make_command = "php artisan make:component " .. pascal_case_component
    table.insert(final_choices, make_command)
  end

  -- 4. Handle Custom Search Paths (if applicable)
  -- This part can be expanded if custom paths need specific existence checks or inclusion logic.
  -- For now, let's add them if they exist, or maybe always add them if configured?
  -- This depends on the exact desired behavior for custom paths.
  -- For simplicity, let's add existing custom paths to the existing list.
  if #existing_standard_paths > 0 then
    -- If standard paths exist, also check custom paths for existence and add them if found
    for _, custom_base_path in ipairs(custom_search_paths) do
      local normalized_custom_path = custom_base_path:gsub("/$", "")
      local custom_view_path = normalized_custom_path
          .. "/components/"
          .. component_identifier:gsub("%.", "/")
          .. ".blade.php"
      -- Check if this custom path exists
      if fs.path_exists(custom_view_path) and not fs.is_dir(custom_view_path) then
        table.insert(final_choices, custom_view_path)
      end
      -- Potentially check for custom index paths too
    end
  end
  -- If no standard paths exist, custom paths are likely also non-existent,
  -- so adding them might not be necessary unless the user wants them as potential locations.
  -- The primary logic for "not found" is handled above with the 4 standard options + command.

  log.debug("Final choices for component '%s': %s", component_identifier, vim.inspect(final_choices))
  return final_choices
end

--- Get all route names from the route list.
--- @return table List of route names.
function M.get_route_names()
  local cache_key = "route_list:route_name"
  local cached = cache.get(cache_key, math.huge)
  if cached then
    return cached
  end

  local routes = M.get_route_list()
  local route_names = {}

  if routes and type(routes) == "table" then
    for route_name, _ in pairs(routes) do
      if route_name and route_name ~= vim.NIL then
        table.insert(route_names, route_name)
      end
    end
  end

  return cache.set(cache_key, route_names)
end

--- Check if the BladeNav artisan command exists.
--- @return boolean
function M.check_blade_command()
  local cache_key = "blade_command_exists"
  local cached = cache.get(cache_key)
  if cached ~= nil then
    return cached
  end

  local root_dir = M.get_root_dir()
  local exists = fs.path_exists(root_dir .. "/app/Console/Commands/BladeNav.php")
  return cache.set(cache_key, exists)
end

--- Get the root directory of the project.
--- @return string
function M.get_root_dir()
  local cache_key = "root_dir"
  local cached = cache.get(cache_key)
  if cached then
    return cached
  end

  local root_dir, _ = cmd.execute_silent({ "git", "rev-parse", "--show-toplevel" })
  root_dir = root_dir:gsub("[\r\n]+$", "") -- Trim trailing newlines
  if root_dir == "" then
    root_dir = vim.fn.getcwd()
  end

  return cache.set(cache_key, root_dir)
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
  return "App\\" -- Default fallback
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
  local script_path = debug.getinfo(1, "S").source:sub(2)    -- Remove the '@'
  local script_dir = vim.fn.fnamemodify(script_path, ":p:h") -- Get directory of this file
  return script_dir .. "/../../BladeNav.php"
end

--- Convert kebab-case to PascalCase.
--- @param input string
--- @return string
function M.kebab_to_pascal(input)
  if not input then
    return ""
  end
  -- Capitalize first letter and letters after hyphens, remove hyphens
  local result = input:gsub("^%l", string.upper):gsub("%-(%w)", string.upper)
  return result
end

--- Get view names from code (placeholder, logic should be in ts_utils or view handler).
--- This function is likely superseded by ts_utils.extract_keys_from_code.
--- @param line_text string
--- @param target_type string
--- @return table
function M.get_view_names_from_code(line_text, target_type)
  -- This is a placeholder. The actual logic for extracting view names
  -- from code like Route::view('/', 'view.name') or view('view.name')
  -- should reside in ts_utils.extract_keys_from_code or be called by the view handler.
  -- Returning an empty table as it's not the primary way anymore.
  log.debug("DEBUG (laravel.lua): get_view_names_from_code is a placeholder. Use ts_utils.extract_keys_from_code.")
  return {}
end

--- Get all view names
--- @param input string
--- @return number, table
M.get_view_names = function(input, not_include_closing_tag)
  local patterns = {
    { pattern = "to_route%(",    tpl = "to_route('%s')",           ft = { "blade", "php" }, fn = find_routes },
    { pattern = "route%(",       tpl = "route('%s')",              ft = { "blade", "php" }, fn = find_routes },
    { pattern = "<x%-",          tpl = "<x-%s />",                 ft = "blade",            fn = find_components },
    { pattern = "<livewire",     tpl = "<livewire:%s />",          ft = "blade",            fn = find_livewire },
    { pattern = "@component%(",  tpl = "@component('%s')",         ft = "blade",            fn = find_views },
    { pattern = "@extends%(",    tpl = "@extends('%s')",           ft = "blade",            fn = find_views },
    { pattern = "@include%(",    tpl = "@include('%s')",           ft = "blade",            fn = find_views },
    { pattern = "@livewire%(",   tpl = "@livewire('%s')",          ft = "blade",            fn = find_livewire },
    { pattern = "Route::view%(", tpl = "Route::view('uri', '%s')", ft = "php",              fn = find_views },
    { pattern = "View::make%(",  tpl = "View::make('%s')",         ft = "php",              fn = find_views },
    { pattern = "view%(",        tpl = "view('%s')",               ft = "php",              fn = find_views },
  }
  local index
  local items = {}
  for i, p in ipairs(patterns) do
    if input:match(p.pattern) and tbl.contains(p.ft, vim.bo.filetype) then
      local names = p.fn()
      for _, name in ipairs(names) do
        if name then
          local new_text = p.tpl:format(name)
          if not_include_closing_tag then
            new_text = new_text:gsub("'%)", "")
          end
          table.insert(items, {
            filterText = input .. name,
            label = p.tpl:format(name):gsub("^%s+", ""),
            newText = new_text,
          })
        end
      end
      index = i
      break
    end
  end
  return index, items
end

--- Detect if current working directory looks like a Laravel project.
--- Heuristics: artisan, or composer.json with laravel/framework|lumen,
--- or typical Laravel paths.
--- @param cwd string|nil
--- @return boolean
function M.is_laravel_project(cwd)
  cwd = cwd or (uv and uv.cwd()) or "."
  local function P(p)
    return (cwd .. "/" .. p)
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

M.__test_build_route_map = build_route_map
M.__test_invalidate_routes_cache = invalidate_routes_cache

return M
