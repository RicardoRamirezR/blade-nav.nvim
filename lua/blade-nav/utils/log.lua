-- lua/blade-nav/utils/log.lua
-- Assuming config is in core now, adjust path if needed
local config = require("blade-nav.core.config")

local M = {}

local function extract_function_name(info)
  if info.name then
    return info.name
  end

  -- Try to extract function name from source code
  local source_file = info.source
  if source_file:sub(1, 1) == "@" then
    source_file = source_file:sub(2) -- Remove @ prefix

    -- Try to read the line where function is defined
    local file = io.open(source_file, "r")
    if file then
      local line_num = 1
      for line in file:lines() do
        if line_num == info.linedefined then
          -- Match various function definition patterns
          local patterns = {
            "function%s+([%w_%.]+)%s*%(",               -- function name()
            "function%s+([%w_]+):([%w_]+)%s*%(",        -- function class:method()
            "([%w_]+)%s*=%s*function%s*%(",             -- name = function()
            "([%w_%.]+)%.([%w_]+)%s*=%s*function%s*%(", -- table.name = function()
          }

          for _, pattern in ipairs(patterns) do
            local match1, match2 = line:match(pattern)
            if match1 then
              if match2 then
                return match1 .. ":" .. match2             -- For method definitions
              else
                return match1:match("([^%.]+)$") or match1 -- Get last part after dots
              end
            end
          end
          break
        end
        line_num = line_num + 1
      end
      file:close()
    end
  end

  return "<anonymous>"
end

local function log_raw(level_str, message)
  local info = debug.getinfo(3, "Slnf")
  local file_path = info.source:sub(2)
  file_path = vim.fn.fnamemodify(file_path, ":t")
  local line_number = info.currentline
  local func_name = extract_function_name(info)

  vim.schedule(function()
    pcall(vim.api.nvim_echo, {
      { string.format("%s: %s:<%s>:%d: %s", level_str, file_path, func_name, line_number, message) },
    }, true, {})
  end)
end

--- Log a debug message if debug is enabled.
--- @param msg string Format string
--- @param ... any Arguments for format string and additional values to inspect
function M.debug(msg, ...)
  if not config.get().debug then
    return
  end

  local args = { ... }
  local formatted_msg = msg

  if #args > 0 then
    -- Count format specifiers in the message
    local format_count = 0
    for _ in msg:gmatch("%%[sdqfgGeioxXc]") do
      format_count = format_count + 1
    end

    -- Format the message with the appropriate number of arguments
    if format_count > 0 and format_count <= #args then
      local format_args = {}
      for i = 1, format_count do
        table.insert(format_args, args[i])
      end
      formatted_msg = string.format(msg, unpack(format_args))

      -- If there are extra arguments, inspect and append them
      if #args > format_count then
        local extra_parts = {}
        for i = format_count + 1, #args do
          table.insert(extra_parts, vim.inspect(args[i]))
        end
        formatted_msg = formatted_msg .. " " .. table.concat(extra_parts, " ")
      end
    else
      -- If no format specifiers or mismatch, just append all args as inspected
      local arg_parts = {}
      for _, arg in ipairs(args) do
        table.insert(arg_parts, vim.inspect(arg))
      end
      formatted_msg = msg .. " " .. table.concat(arg_parts, " ")
    end
  end

  log_raw("DEBUG", formatted_msg)
end

--- Log an info message.
--- @param msg string Format string
--- @param ... any Arguments for format string
function M.info(msg, ...)
  if not config.get().debug then
    return
  end

  local formatted_msg
  if select("#", ...) > 0 then
    formatted_msg = string.format("[BladeNav Info] " .. msg, ...)
  else
    formatted_msg = "[BladeNav Info] " .. msg
  end
  vim.schedule(function()
    vim.notify(formatted_msg, vim.log.levels.INFO)
  end)
end

--- Log a warning message.
--- @param msg string Format string
--- @param ... any Arguments for format string
function M.warn(msg, ...)
  if not config.get().debug then
    return
  end

  local formatted_msg
  if select("#", ...) > 0 then
    formatted_msg = string.format("[BladeNav Warn] " .. msg, ...)
  else
    formatted_msg = "[BladeNav Warn] " .. msg
  end
  vim.schedule(function()
    vim.notify(formatted_msg, vim.log.levels.WARN)
  end)
end

--- Log an error message.
--- @param msg string Format string
--- @param ... any Arguments for format string
function M.error(msg, ...)
  if not config.get().debug then
    return
  end

  local formatted_msg
  if select("#", ...) > 0 then
    formatted_msg = string.format("[BladeNav Error] " .. msg, ...)
  else
    formatted_msg = "[BladeNav Error] " .. msg
  end
  vim.schedule(function()
    vim.notify(formatted_msg, vim.log.levels.ERROR)
  end)
end

return M
