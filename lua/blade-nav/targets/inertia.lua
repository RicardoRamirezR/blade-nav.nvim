-- lua/blade-nav/targets/inertia.lua
-- Target handler for Laravel inertia references like inertia('home'), to_inertia('user.profile').

local cache = require("blade-nav.utils.cache")
local extractor = require("blade-nav.utils.inertia-path-extractor")
local fs = require("blade-nav.utils.fs")
local log = require("blade-nav.utils.log")
local ts_utils = require("blade-nav.utils.treesitter")

local M = {}

--- Gets target information if the cursor is on an inertia reference.
--- Supports inertia(), Interia::render().
--- @param context BladeNavContext Context created by context.lua
--- @return BladeNavTargetInfo|nil { type = "interia", name = "view.name" } or nil
function M.get_target(context)
  local line = context.line
  local col_1 = context.cursor_col_1

  if not line or col_1 <= 0 then
    log.debug("Invalid line or cursor position.")
    return nil
  end

  log.debug("Processing line for inertia reference: %s", line)

  local found_keys_inertia = ts_utils.extract_php_function_keys(line, "inertia")
  log.debug("Found keys for 'inertia': %s", vim.inspect(found_keys_inertia))

  if #found_keys_inertia >= 1 then
    local key_info = found_keys_inertia[1]
    return {
      type = "inertia",
      name = key_info,
      ft = context.filetype,
    }
  end

  log.debug("Cursor position did not match any found inertia key range.")
  return nil
end

local function read_app_file()
  local root = fs.get_root_dir()

  local possible_paths = {
    root .. "/resources/js/app.js",
    root .. "/resources/js/app.ts",
  }

  for _, file_path in ipairs(possible_paths) do
    if vim.fn.filereadable(file_path) == 1 then
      local lines = {}
      for line in io.lines(file_path) do
        table.insert(lines, line)
      end
      local content = table.concat(lines, "\n")
      return content, file_path
    end
  end

  return nil, string.format("Neither app.js nor app.ts found in %s/resources/js/", root)
end

local function get_pages_path()
  local content, err = read_app_file()
  if not content then
    vim.notify("Failed to read app.js or app.ts: " .. (err or "unknown error"), vim.log.levels.WARN)
    return "Pages"
  end

  local pages_path = extractor.extract_pages_path(content)
  log.debug("Extracted Pages path: %s", pages_path)
  if not pages_path then
    vim.notify("Could not find Pages path in app.js, using default", vim.log.levels.INFO)
    return "Pages"
  end

  return pages_path
end

local function get_path(page_name)
  local path = cache.get("pages_path")
  if not path then
    path = get_pages_path()
    cache.set("pages_path", path)
  end

  page_name = page_name:gsub("['()%)]", "")
  return "resources/js/" .. path .. "/" .. page_name .. ".vue"
end

--- Resolves and opens/navigates to the inertia definition or associated controller.
--- @param target_info BladeNavTargetInfo The target info returned by get_target.
--- @return boolean True if successfully opened or action taken.
function M.resolve(target_info)
  if not target_info or target_info.type ~= "inertia" or not target_info.name then
    log.warn("inertia resolve called with invalid target_info: %s", vim.inspect(target_info))
    return false
  end

  local inertia_name = target_info.name
  log.debug("Resolving inertia: %s", inertia_name)

  local file_path = get_path(inertia_name)
  log.debug("File paths: %s", vim.inspect(file_path))

  if file_path and vim.fn.filereadable(file_path) == 1 then
    vim.cmd("edit " .. vim.fn.fnameescape(file_path))
    return true
  end

  return false
end

return M
