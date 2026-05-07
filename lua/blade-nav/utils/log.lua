-- lua/blade-nav/utils/log.lua
-- Assuming config is in core now, adjust path if needed
local config = require("blade-nav.core.config")

local M = {}

local function extract_function_name(info)
  if info.name then
    return info.name
  end

  local source_file = info.source
  if source_file:sub(1, 1) == "@" then
    source_file = source_file:sub(2)

    local file = io.open(source_file, "r")
    if file then
      local line_num = 1
      for line in file:lines() do
        if line_num == info.linedefined then
          local patterns = {
            "function%s+([%w_%.]+)%s*%(",
            "function%s+([%w_]+):([%w_]+)%s*%(",
            "([%w_]+)%s*=%s*function%s*%(",
            "([%w_%.]+)%.([%w_]+)%s*=%s*function%s*%(",
          }

          for _, pattern in ipairs(patterns) do
            local match1, match2 = line:match(pattern)
            if match1 then
              if match2 then
                return match1 .. ":" .. match2
              else
                return match1:match("([^%.]+)$") or match1
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

local table_unpack = table.unpack

local function count_format_specifiers(fmt)
  local i = 1
  local len = #fmt
  local count = 0
  local conv_set = {
    d = true,
    i = true,
    u = true,
    o = true,
    x = true,
    X = true,
    f = true,
    F = true,
    e = true,
    E = true,
    g = true,
    G = true,
    c = true,
    s = true,
    q = true,
    p = true,
  }
  while i <= len do
    local ch = fmt:sub(i, i)
    if ch == "%" then
      local nextch = fmt:sub(i + 1, i + 1)
      if nextch == "%" then
        -- "%%" -> literal %, skip
        i = i + 2
      else
        -- advance to conversion letter
        local j = i + 1
        while j <= len do
          local letter = fmt:sub(j, j)
          if letter:match("%a") then
            if conv_set[letter] then
              count = count + 1
            end
            break
          end
          j = j + 1
        end
        i = j + 1
      end
    else
      i = i + 1
    end
  end
  return count
end

--- Log a debug message if debug is enabled.
--- @param msg string Format string
--- @param ... any Arguments for format string and additional values to inspect
function M.debug(msg, ...)
  if not config.get().debug then
    return
  end

  local args = { ... }
  local format_count = count_format_specifiers(msg)

  for i = #args + 1, format_count do
    args[i] = "<nil>"
  end

  local fmt_args = {}
  for i = 1, math.max(#args, format_count) do
    local a = args[i]
    if a == nil then
      a = "<nil>"
    elseif type(a) == "table" or type(a) == "boolean" then
      a = vim.inspect(a)
    elseif type(a) ~= "string" and type(a) ~= "number" then
      a = tostring(a)
    end
    table.insert(fmt_args, a)
  end

  local ok, formatted_msg = pcall(string.format, msg, table_unpack(fmt_args))
  if ok then
    if #args > format_count then
      local extra_parts = {}
      for i = format_count + 1, #args do
        table.insert(extra_parts, vim.inspect(args[i]))
      end
      if #extra_parts > 0 then
        formatted_msg = formatted_msg .. " " .. table.concat(extra_parts, " ")
      end
    end
  else
    local arg_parts = {}
    for _, a in ipairs(args) do
      table.insert(arg_parts, vim.inspect(a))
    end
    if #arg_parts > 0 then
      formatted_msg = msg .. " " .. table.concat(arg_parts, " ")
    else
      formatted_msg = msg
    end
  end

  log_raw("DEBUG", formatted_msg)
end

--- Log an info message.
--- @param msg string Format string
--- @param ... any Arguments for format string
function M.info(msg, ...)
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
