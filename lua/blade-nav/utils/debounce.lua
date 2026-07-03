-- lua/blade-nav/utils/debounce.lua
local uv = vim.uv
local unpack = table.unpack or unpack ---@diagnostic disable-line: deprecated

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

return debounce
