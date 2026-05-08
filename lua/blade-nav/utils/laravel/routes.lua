-- lua/blade-nav/utils/laravel/routes.lua
local uv = vim.loop

local cache = require("blade-nav.utils.cache")
local cmd = require("blade-nav.utils.cmd")
local debounce = require("blade-nav.utils.debounce")
local fs = require("blade-nav.utils.fs")
local log = require("blade-nav.utils.log")

local M = {}

local route_cache_watcher = nil
local routes_watcher = nil

function M.invalidate_routes_cache()
  log.debug("Invalidating all cached routes")
  cache.clear_prefix("route_list:")
end

local debounced_invalidate = debounce(function()
  M.invalidate_routes_cache()
end, 200)

local function watch_route_cache()
  if route_cache_watcher then
    return
  end

  local handle, err = uv.new_fs_event()
  if not handle then
    log.error("Failed to create fs_event handle: %s", err or "unknown")
    return
  end

  local root = fs.get_root_dir()
  local ok, start_err = pcall(handle.start, handle, root .. "/bootstrap/cache", {}, function(err2, fname, events)
    if err2 then
      vim.schedule(function()
        log.error("Route cache dir watcher error: %s", err2)
      end)
      return
    end

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

local function watch_routes_dir()
  if routes_watcher then
    return
  end

  local handle, err = uv.new_fs_event()
  if not handle then
    log.error("Failed to create fs_event handle: %s", err or "unknown")
    return
  end

  local root = fs.get_root_dir()
  local ok, start_err = pcall(handle.start, handle, root .. "/routes", {}, function(err2, filename, events)
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
  local root = fs.get_root_dir()
  local all_out, ok_all = cmd.execute_silent({
    "php",
    "artisan",
    "route:list",
    "--json",
    "--columns=name,action",
  }, { cwd = root })

  local primed_map = {}
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

  if not route_name then
    return prime_routes()
  end

  if not fs.command_exists("php") then
    log.warn("'php' command not found.")
    return {}
  end

  watch_routes_dir()
  watch_route_cache()

  local root = fs.get_root_dir()
  local output, ok = cmd.execute_silent({
    "php",
    "artisan",
    "route:list",
    "--name=" .. route_name,
    "--json",
    "--columns=name,action",
  }, { cwd = root })
  if not ok then
    log.debug("Root: " .. root)
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

  table.sort(route_names)

  return cache.set(cache_key, route_names)
end

M.__test_build_route_map = build_route_map

return M
