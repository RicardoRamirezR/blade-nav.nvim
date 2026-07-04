-- lua/blade-nav/utils/cmd.lua
local log = require("blade-nav.utils.log")

local M = {}

--- Checks if command exists
--- @param name string
--- @return boolean
function M.exists(name)
  local result = vim.fn.executable(name) == 1
  log.debug("Command '%s' exists: %s", name, tostring(result))
  return result
end

--- Normalize a vim.system() result into (output, ok).
--- @param ok_call boolean Whether the pcall'd vim.system/:wait() succeeded
--- @param obj table|any vim.SystemCompleted, or the pcall error value
--- @return string, boolean
local function normalize_result(ok_call, obj)
  if not ok_call then
    return tostring(obj), false
  end

  if obj.code ~= 0 then
    local output = (obj.stdout or "") .. (obj.stderr or "")
    return output, false
  end

  return obj.stdout, true
end

--- Executes system command silently (combining stdout/stderr).
--- @param cmd table Command as an argv list { "command", "arg1", ... }
--- @param opts? table Options for vim.system (e.g., { cwd = "/path", timeout = ms })
--- @return string,boolean Output (stdout/stderr combined) or nil, success flag
function M.execute_silent(cmd, opts)
  assert(type(cmd) == "table", "cmd must be an argv list")

  if not M.exists(cmd[1]) then
    log.debug("Command not found: " .. cmd[1])
    return "", false
  end

  opts = vim.tbl_extend("force", { text = true }, opts or {})
  local timeout = opts.timeout or 5000

  local ok, obj = pcall(function()
    return vim.system(cmd, opts):wait(timeout)
  end)

  return normalize_result(ok, obj)
end

--- Executes system command asynchronously, invoking callback(output, ok).
--- @param cmd table Command as an argv list { "command", "arg1", ... }
--- @param opts? table Options for vim.system (e.g., { cwd = "/path" })
--- @param callback fun(output: string, ok: boolean)
function M.execute_async(cmd, opts, callback)
  assert(type(cmd) == "table", "cmd must be an argv list")

  if not M.exists(cmd[1]) then
    log.debug("Command not found: " .. cmd[1])
    callback("", false)
    return
  end

  opts = vim.tbl_extend("force", { text = true }, opts or {})

  vim.system(cmd, opts, function(obj)
    local output, ok = normalize_result(true, obj)
    vim.schedule(function()
      callback(output, ok)
    end)
  end)
end

return M
