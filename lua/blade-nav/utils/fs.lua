-- lua/blade-nav/utils/fs.lua
local uv = vim.loop
local cmd = require("blade-nav.utils.cmd")
local log = require("blade-nav.utils.log")

local M = {}

--- Safely read a file.
--- @param path string File path
--- @return string|nil File content or nil on error
function M.read_file(path)
  local ok, fd = pcall(uv.fs_open, path, "r", 438)
  if not ok or not fd then
    log.debug("Failed to open file for reading: %s", path)
    return nil
  end

  local ok_stat, stat = pcall(uv.fs_fstat, fd)
  if not ok_stat or not stat then
    log.debug("Failed to stat file: %s", path)
    uv.fs_close(fd)
    return nil
  end

  local ok_read, data = pcall(uv.fs_read, fd, stat.size, 0)
  uv.fs_close(fd)

  if not ok_read then
    log.debug("Failed to read file: %s", path)
    return nil
  end

  return data
end

--- Write a file
--- @param file_path string
--- @param content string
--- @return boolean|nil, string
M.write_file = function(file_path, content)
  local file = io.open(file_path, "w")
  if not file then
    return nil, "Could not open file: " .. file_path
  end
  file:write(content)
  file:close()
  return true, ""
end

--- Check if a file or directory exists.
--- @param path string Path to check
--- @return boolean True if path exists
function M.path_exists(path)
  local ok_stat, stat = pcall(uv.fs_stat, path)
  local exists = ok_stat and stat ~= nil
  log.debug("Path '%s' exists: %s", path, tostring(exists))
  return exists
end

--- Check if a path is a directory.
--- @param path string Path to check
--- @return boolean True if path is a directory
function M.is_dir(path)
  local ok_stat, stat = pcall(uv.fs_stat, path)
  local is_directory = ok_stat and stat and stat.type == "directory"
  log.debug("Path '%s' is directory: %s", path, tostring(is_directory))
  return is_directory
end

--- Check if a command exists.
--- @param cmd_name string Command name
--- @return boolean True if command exists
function M.command_exists(cmd_name)
  return cmd.exists(cmd_name)
end

--- Normalize path for current OS.
--- @param path string
--- @return string
function M.normalize_path(path)
  if path == nil then
    return ""
  end
  local result
  if vim.fn.has("win32") == 1 then
    result = path:gsub("/", "\\")
  else
    result = path:gsub("\\", "/")
  end

  return result
end

--- find files using `fd` or `find`
--- @param path string
--- @param extension string
--- @param exclude_dirs? table
--- @return string|nil
function M.fixind_files(path, extension, exclude_dirs)
  local commands = {
    fd = { cmd = "fd --type=file --extension %s . %s %s", exclude = " -E %s" },
    find = { cmd = "find ./%s -type f -name *.%s %s", exclude = " -not -path './%s/*'" },
  }
  local function build_exclude_cmd(exclude_fmt, dirs)
    local exclude_cmd = ""
    for _, dir in ipairs(dirs or {}) do
      exclude_cmd = exclude_cmd .. " " .. string.format(exclude_fmt, dir)
    end
    return exclude_cmd
  end
  local tool = M.command_exists("fd") and "fd" or "find"
  local cmd_template = commands[tool].cmd
  local exclude_template = commands[tool].exclude

  local exclude_cmd = build_exclude_cmd(exclude_template, exclude_dirs)
  local command
  if tool == "fd" then
    command = string.format(cmd_template, extension, path, exclude_cmd)
  else
    command = string.format(cmd_template, path, extension, exclude_cmd)
  end
  local result, _ = cmd.execute_silent({ "sh", "-c", command })
  return result
end

--- Find files using `fd` or `find`.
--- @param path string
--- @param extension string
--- @param exclude_dirs? string[]
--- @return string[]|nil
function M.find_files(path, extension, exclude_dirs)
  local tool, cmd_template, exclude_fmt

  if M.command_exists("fd") then
    tool = "fd"
    cmd_template = "fd --type=file --extension %s . %s %s"
    exclude_fmt = "-E %s"
  else
    tool = "find"
    cmd_template = "find %s -type f -name '*.%s' %s"
    exclude_fmt = "-not -path './%s/*'"
  end

  local exclude_cmd = ""
  if exclude_dirs and #exclude_dirs > 0 then
    exclude_cmd = table.concat(
      vim.tbl_map(function(dir)
        return string.format(exclude_fmt, dir)
      end, exclude_dirs),
      " "
    )
  end

  local command
  if tool == "fd" then
    command = string.format(cmd_template, extension, path, exclude_cmd)
  else
    command = string.format(cmd_template, path, extension, exclude_cmd)
  end

  local result = cmd.execute_silent({ "sh", "-c", command })
  if not result or result == "" then
    return nil
  end

  return vim.split(result, "\n", { trimempty = true })
end

return M
