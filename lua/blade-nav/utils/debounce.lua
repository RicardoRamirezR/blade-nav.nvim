-- lua/blade-nav/utils/debounce.lua
local uv = vim.uv
-- LuaJIT has no table.unpack; fall back to the global unpack (deprecated in Lua 5.2+).
---@diagnostic disable-next-line: deprecated
local unpack = table.unpack or unpack -- luacheck: ignore 143

local M = {}

local function debounce(fn, ms)
  local timer = nil
  return function(...)
    local args = { ... }
    if timer then
      timer:stop()
      timer:close()
    end
    timer = uv.new_timer()
    timer:start(ms, 0, function()
      timer:stop()
      timer:close()
      timer = nil
      vim.schedule(function()
        fn(unpack(args))
      end)
    end)
  end
end

--- Per-key debounce: each distinct `key` gets its own timer, so calls keyed
--- by e.g. bufnr no longer cancel/delay pending work for other keys.
--- @param fn fun(key: any, ...: any)
--- @param ms integer
--- @return fun(key: any, ...: any) wrapped debounced function
--- @return fun() cancel_all cancels and closes every pending timer
local function debounce_per_key(fn, ms)
  local timers = {}

  local function cancel(key)
    local timer = timers[key]
    if timer then
      timer:stop()
      timer:close()
      timers[key] = nil
    end
  end

  local function cancel_all()
    for key in pairs(timers) do
      cancel(key)
    end
  end

  local function wrapped(key, ...)
    local args = { ... }
    cancel(key)
    local timer = uv.new_timer()
    timers[key] = timer
    timer:start(ms, 0, function()
      timer:stop()
      timer:close()
      timers[key] = nil
      vim.schedule(function()
        fn(key, unpack(args))
      end)
    end)
  end

  return wrapped, cancel_all
end

M.debounce_per_key = debounce_per_key

setmetatable(M, {
  __call = function(_, fn, ms)
    return debounce(fn, ms)
  end,
})

return M
