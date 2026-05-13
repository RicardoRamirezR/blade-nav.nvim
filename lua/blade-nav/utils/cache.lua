-- lua/blade-nav/utils/cache.lua

local uv = vim.uv
local config = require("blade-nav.core.config")
local log = require("blade-nav.utils.log")

local M = {}
local cache_store = {}

--- Get a value from the cache.
--- @param key string Cache key
--- @return any|nil Cached data or nil if expired/missing
function M.get(key, ttl)
  local entry = cache_store[key]
  if not entry then
    log.debug("Cache MISS for key: %s", key)
    return nil
  end

  local cfg = config.get()
  ttl = ttl or cfg.cache_timeout or 5000

  if uv.now() - entry.timestamp > ttl then
    cache_store[key] = nil
    log.debug("Cache entry expired: %s", key)
    return nil
  end

  log.debug("Cache HIT for key: %s", key)
  return entry.data
end

--- Set a value in the cache.
--- @param key string Cache key
--- @param data any Data to cache
function M.set(key, data)
  cache_store[key] = {
    data = data,
    timestamp = uv.now(),
  }
  log.debug("Cache SET for key: %s", key)
  return data
end

--- Invalidate a specific cache entry.
--- @param key string Key to invalidate
function M.invalidate(key)
  cache_store[key] = nil
  log.debug("Cache INVALIDATED for key: %s", key)
end

--- Clear cached data (for testing/development)
--- @param key? string Specific cache key to clear
function M.clear(key)
  if key then
    cache_store[key] = nil
    log.debug("Cache cleared for key: %s", key)
    return
  end
  for k in pairs(cache_store) do
    cache_store[k] = nil
  end
  log.debug("All cache cleared.")
end

function M.clear_prefix(prefix)
  for key, _ in pairs(cache_store) do
    if key:sub(1, #prefix) == prefix then
      cache_store[key] = nil
    end
  end
end

return M
