-- lua/blade-nav/utils/fs.lua
local uv = vim.uv
local cmd = require("blade-nav.utils.cmd")
local log = require("blade-nav.utils.log")
local cache = require("blade-nav.utils.cache")

local M = {}

--- Get the root directory of the project.
--- @return string
function M.get_root_dir()
  local cache_key = "root_dir"
  local cached = cache.get(cache_key)
  if cached then
    return cached
  end

  local root_dir, ok = cmd.execute_silent({ "git", "rev-parse", "--show-toplevel" })
  if not ok then
    root_dir = vim.fn.getcwd()
  end

  root_dir = root_dir:gsub("[\r\n]+$", "")
  if root_dir == "" then
    root_dir = vim.fn.getcwd()
  end

  return cache.set(cache_key, root_dir), ok
end

--- Safely read a file.
--- @param path string File path
--- @return string|nil, string|boolean File content or nil on error
function M.read_file(path)
  local ok, fd = pcall(uv.fs_open, path, "r", 438)
  if not ok or not fd then
    log.debug("Failed to open file for reading: %s", path)
    return nil, "cannot open file"
  end

  local ok_stat, stat = pcall(uv.fs_fstat, fd)
  if not ok_stat or not stat then
    log.debug("Failed to stat file: %s", path)
    uv.fs_close(fd)
    return nil, "cannot stat file"
  end

  local ok_read, data = pcall(uv.fs_read, fd, stat.size, 0)
  uv.fs_close(fd)

  if not ok_read then
    log.debug("Failed to read file: %s", path)
    return nil, "cannot read file"
  end

  return data, true
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
    exclude_fmt = "-not -path '%s/*'"
  end

  local exclude_cmd = ""
  if exclude_dirs and #exclude_dirs > 0 then
    local exclude_parts = {}
    for _, dir in ipairs(exclude_dirs) do
      if tool == "fd" then
        table.insert(exclude_parts, string.format(exclude_fmt, dir))
      else
        -- For find, we need to use the full path pattern
        table.insert(exclude_parts, string.format(exclude_fmt, path .. "/" .. dir))
      end
    end
    exclude_cmd = table.concat(exclude_parts, " ")
  end

  local command
  if tool == "fd" then
    command = string.format(cmd_template, extension, path, exclude_cmd)
  else
    command = string.format(cmd_template, path, extension, exclude_cmd)
  end

  -- Clean up extra spaces
  command = command:gsub("%s+", " "):gsub("%s$", "")

  local root = M.get_root_dir()
  local output, ok = cmd.execute_silent({ "sh", "-c", command }, { cwd = root })
  if not ok then
    return nil
  end

  return vim.split(output, "\n", { trimempty = true })
end

--- Get a path relative to the project root (if inside it).
--- Falls back to absolute path if outside.
--- @param path string
--- @return string
function M.project_relative(path)
  if not path or path == "" then
    return path
  end

  local root = M.get_root_dir and M.get_root_dir() or vim.uv.cwd()
  local abs = vim.fn.fnamemodify(vim.fn.resolve(path), ":p")
  local normalized_root = vim.fs.normalize(vim.fn.fnamemodify(vim.fn.resolve(root), ":p"))

  -- Ensure trailing slash for consistent comparison
  if not normalized_root:match("/$") then
    normalized_root = normalized_root .. "/"
  end

  if abs:find(normalized_root, 1, true) == 1 then
    local rel = abs:sub(#normalized_root + 1)
    return rel:gsub("^/", "")
  end

  return abs
end

function M.abs_path(p)
  if not p or p == "" then
    return p
  end
  return vim.fn.fnamemodify(p, ":p")
end

return M
