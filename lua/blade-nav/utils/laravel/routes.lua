-- lua/blade-nav/utils/laravel/routes.lua
local uv = vim.uv

local cache = require("blade-nav.utils.cache")
local cmd = require("blade-nav.utils.cmd")
local debounce = require("blade-nav.utils.debounce")
local fs = require("blade-nav.utils.fs")
local log = require("blade-nav.utils.log")

local M = {}

local route_cache_watcher = nil
local route_cache_watcher_root = nil
local routes_watcher = nil
local routes_watcher_root = nil
local watcher_start_error_notified = false

-- Lowered bound for synchronous route:list calls (caller needs an immediate
-- result); the background re-prime path runs fully async instead.
local SYNC_TIMEOUT_MS = 2000

-- Short TTL for empty/failure route-name lists: an artisan failure must not
-- be cached forever, but the completion path should not re-run artisan on
-- every keystroke either.
local EMPTY_NAMES_TTL_MS = 2000

--- Build a project-scoped cache key so switching projects in the same
--- session does not serve another project's routes.
--- @param name string
--- @return string
local function scoped_key(name)
  return "route_list:" .. name .. ":" .. fs.get_root_dir()
end

function M.invalidate_routes_cache()
  log.debug("Invalidating all cached routes")
  cache.clear_prefix("route_list:")
end

local debounced_invalidate = debounce(function()
  M.invalidate_routes_cache()
end, 200)

local function close_watcher(handle)
  pcall(function()
    handle:stop()
    handle:close()
  end)
end

--- Watchers retry on later calls, so only the first start failure is surfaced
--- at error level; retries log at debug level to avoid notify-spam.
--- @param msg string
local function notify_watcher_failure(msg)
  if watcher_start_error_notified then
    log.debug("%s", msg)
  else
    watcher_start_error_notified = true
    log.error("%s", msg)
  end
end

local function watch_route_cache()
  local root = fs.get_root_dir()
  if route_cache_watcher then
    if route_cache_watcher_root == root then
      return
    end
    -- Project root changed (e.g. `:cd` to another project): re-anchor.
    close_watcher(route_cache_watcher)
    route_cache_watcher = nil
    route_cache_watcher_root = nil
  end

  local handle, err = uv.new_fs_event()
  if not handle then
    log.error("Failed to create fs_event handle: %s", err or "unknown")
    return
  end

  local ok, start_err = pcall(handle.start, handle, root .. "/bootstrap/cache", {}, function(err2, fname, events)
    if err2 then
      vim.schedule(function()
        log.error("Route cache dir watcher error: %s", err2)
      end)
      return
    end

    if fname and fname:match("^routes%-v%d+%.php$") then
      vim.schedule(function()
        local file_path = root .. "/bootstrap/cache/" .. fname
        local exists = vim.uv.fs_stat(file_path) ~= nil
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
    close_watcher(handle)
    notify_watcher_failure(string.format("Failed to start fs_event for bootstrap/cache: %s", tostring(start_err)))
  else
    route_cache_watcher = handle
    route_cache_watcher_root = root
    log.debug("Watching bootstrap/cache dir for route cache changes")
  end
end

local function watch_routes_dir()
  local root = fs.get_root_dir()
  if routes_watcher then
    if routes_watcher_root == root then
      return
    end
    -- Project root changed (e.g. `:cd` to another project): re-anchor.
    close_watcher(routes_watcher)
    routes_watcher = nil
    routes_watcher_root = nil
  end

  local handle, err = uv.new_fs_event()
  if not handle then
    log.error("Failed to create fs_event handle: %s", err or "unknown")
    return
  end

  local ok, start_err = pcall(handle.start, handle, root .. "/routes", {}, function(err2, filename, events)
    if err2 then
      log.error("Route watcher error: %s", err2)
      return
    end
    log.info("Detected change in routes/%s (events=%s), invalidating route cache", filename or "?", events or "?")
    debounced_invalidate()
  end)

  if not ok then
    close_watcher(handle)
    notify_watcher_failure(string.format("Failed to start fs_event on routes/: %s", tostring(start_err)))
  else
    routes_watcher = handle
    routes_watcher_root = root
    log.debug("Watching routes/ directory for changes")
  end
end

local function build_route_map(routes)
  local map = {}
  for _, r in ipairs(routes) do
    -- r.action may be vim.NIL (JSON null) or otherwise not a string.
    if r.name and type(r.action) == "string" then
      local controller_method = vim.split(r.action, "@")
      map[r.name] = {
        controller = controller_method[1],
        method = controller_method[2],
      }
    end
  end
  return map
end

local function apply_primed_routes(output, ok)
  local primed_map = {}
  if ok then
    local ok_parse, all_routes = pcall(vim.json.decode, output)
    if ok_parse and type(all_routes) == "table" then
      primed_map = build_route_map(all_routes)
      cache.set(scoped_key("primed"), primed_map)
      log.debug("Primed cache with %d routes", vim.tbl_count(primed_map))
    end
  end
  return primed_map
end

--- Prime the whole-route-list cache.
--- @param async? boolean When true, run via vim.system's callback (no blocking wait).
--- @return table Primed route map (empty table when async, since the result arrives later).
local function prime_routes(async)
  -- Ensure invalidation watchers are running regardless of which code path
  -- primed the cache first (get_route_list(name) already starts these too).
  watch_routes_dir()
  watch_route_cache()

  local root = fs.get_root_dir()
  local args = cmd.artisan_argv({ "route:list", "--json", "--columns=name,action" })

  if async then
    cmd.execute_async(args, { cwd = root }, function(output, ok)
      apply_primed_routes(output, ok)
    end)
    return {}
  end

  local all_out, ok_all = cmd.execute_silent(args, { cwd = root, timeout = SYNC_TIMEOUT_MS })
  return apply_primed_routes(all_out, ok_all)
end

function M.get_route_list(route_name)
  local primed_routes = cache.get(scoped_key("primed"), math.huge)
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
  local output, ok = cmd.execute_silent(
    cmd.artisan_argv({ "route:list", "--name=" .. route_name, "--json", "--columns=name,action" }),
    { cwd = root, timeout = SYNC_TIMEOUT_MS }
  )
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
    prime_routes(true)
  end)

  return route_map
end

--- Get all route names.
--- @param opts? { async?: boolean } When async, never block on artisan: if the
--- route list is not primed yet, kick off a background re-prime and return the
--- currently-known (possibly empty) names. Used by the completion path.
--- @return string[]
function M.get_route_names(opts)
  opts = opts or {}
  local cache_key = scoped_key("route_name")
  local cached = cache.get(cache_key, math.huge)
  if cached then
    return cached
  end

  -- Empty/failure results are cached under a separate key read with a short
  -- TTL (never long-term): artisan may simply have failed this time.
  local empty_key = scoped_key("route_name_empty")
  local cached_empty = cache.get(empty_key, EMPTY_NAMES_TTL_MS)
  if cached_empty then
    return cached_empty
  end

  local routes
  if opts.async then
    routes = cache.get(scoped_key("primed"), math.huge)
    if not routes then
      -- Not primed: trigger the async re-prime and return what is currently
      -- known (nothing) instead of blocking the caller on artisan.
      prime_routes(true)
      routes = {}
    end
  else
    routes = M.get_route_list()
  end

  local route_names = {}
  if routes and type(routes) == "table" then
    for route_name, _ in pairs(routes) do
      if route_name and route_name ~= vim.NIL then
        table.insert(route_names, route_name)
      end
    end
  end

  table.sort(route_names)

  if #route_names == 0 then
    return cache.set(empty_key, route_names)
  end

  return cache.set(cache_key, route_names)
end

M.__test_build_route_map = build_route_map

return M
