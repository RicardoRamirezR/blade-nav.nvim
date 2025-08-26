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

--- Executes system command silently (combining stdout/stderr).
--- @param cmd table|string Command as a list { "command", "arg1", ... } or string
--- @param opts? table Options for vim.system (e.g., { cwd = "/path" })
--- @return string,boolean Output (stdout/stderr combined) or nil, success flag
function M.execute_silent(cmd, opts)
  if type(cmd) == "string" then
    cmd = M.explode(" ", cmd)
  end

  if not M.exists(cmd[1]) then
    log.debug("Command not found: " .. cmd[1])
    return "", false
  end

  opts = vim.tbl_extend("force", { text = true }, opts or {})
  local timeout = opts.timeout or 5000

  local ok, obj = pcall(function()
    return vim.system(cmd, opts):wait(timeout)
  end)

  if not ok then
    return tostring(obj), false
  end

  if obj.code ~= 0 then
    local output = (obj.stdout or "") .. (obj.stderr or "")
    return output, false
  end

  return obj.stdout, true
end

return M
