-- lua/blade-nav/targets/inertia.lua
-- Target handler for Laravel inertia references like inertia('home'), Inertia::render('user.profile').

local cache = require("blade-nav.utils.cache")
local choice = require("blade-nav.utils.choice")
local cmd = require("blade-nav.utils.cmd")
local extractor = require("blade-nav.utils.inertia-path-extractor")
local fs = require("blade-nav.utils.fs")
local log = require("blade-nav.utils.log")
local ts_utils = require("blade-nav.utils.treesitter")

local uv = vim.uv
local M = {}

local app_watcher = nil

function M.get_capabilities()
  return {
    targets = { "inertia", "Inertia::render" },
    filetypes = { "php", "vue" },
  }
end

-- Forward declaration (defined below); used to locate the pages directory.
local resolve_pages_path

local function extract_page_name_from_buffer()
  local bufname = vim.api.nvim_buf_get_name(0)
  if bufname == "" then
    return nil
  end
  bufname = vim.fs.normalize(bufname)

  local root = fs.get_root_dir()
  local rel = bufname:gsub("^" .. vim.pesc(root) .. "/", "")

  -- Capture whatever comes after the configured pages directory (default
  -- "Pages"), no matter how deep it sits under resources/js.
  local pages_path = resolve_pages_path()
  local page_name = rel:match("resources/js/" .. vim.pesc(pages_path) .. "/(.+)%.[^.]+$")
  if not page_name then
    return nil
  end

  return page_name
end

--- Gets target information if the cursor is on an inertia reference.
--- @param context BladeNavContext Context created by context.lua
--- @return BladeNavTargetInfo|nil
function M.get_target(context)
  if context.filetype == "vue" then
    local page_name = extract_page_name_from_buffer()
    if page_name then
      return {
        type = "inertia_reverse",
        name = page_name,
        ft = context.filetype,
      }
    end
    return nil
  end

  if context.filetype ~= "php" then
    log.debug("Invalid context for inertia handler.")
    return nil
  end

  if context.target and not vim.tbl_contains({ "inertia", "Inertia::render" }, context.target) then
    return nil
  end

  if context.first_arg and context.target then
    return {
      type = "inertia",
      name = context.first_arg,
      ft = context.filetype,
    }
  end

  local line = context.line

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
      return table.concat(lines, "\n"), file_path
    end
  end

  return nil, string.format("Neither app.js nor app.ts found in %s/resources/js/", root)
end

local function get_pages_path()
  local config = require("blade-nav.core.config")
  local user_path = config.get("inertia_pages_path")
  if user_path then
    return user_path
  end

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

local function invalidate_pages_cache()
  cache.clear("pages_path")
  log.debug("Invalidated pages_path cache")
end

local function watch_app_file()
  if app_watcher and not app_watcher:is_closing() then
    log.debug("App file watcher already active, reusing.")
    return
  end
  app_watcher = nil

  local root = fs.get_root_dir()
  local js_dir = root .. "/resources/js"

  if not fs.is_dir(js_dir) then
    return
  end

  local handle, err = uv.new_fs_event()
  if not handle then
    log.error("Failed to create fs_event handle for app.js: %s", err or "unknown")
    return
  end

  local ok, start_err = pcall(handle.start, handle, js_dir, {}, function(err2, fname)
    if err2 then
      vim.schedule(function()
        log.error("App file watcher error: %s", err2)
      end)
      return
    end

    if fname and (fname == "app.js" or fname == "app.ts") then
      vim.schedule(function()
        log.debug("Detected change in %s, invalidating pages_path cache", fname)
        invalidate_pages_cache()
      end)
    end
  end)

  if not ok then
    log.error("Failed to start fs_event for resources/js: %s", tostring(start_err))
    if not handle:is_closing() then
      handle:close()
    end
  else
    app_watcher = handle
    log.debug("Watching resources/js for app.js/app.ts changes")
  end
end

resolve_pages_path = function()
  local config = require("blade-nav.core.config")
  local timeout = config.get("cache_timeout") or 50000

  local path = cache.get("pages_path", timeout)
  if not path then
    path = get_pages_path()
    cache.set("pages_path", path)
    watch_app_file()
  end

  return path
end

local function get_path(page_name)
  local path = resolve_pages_path()

  page_name = page_name:gsub("[%s\"'()]", "")
  page_name = page_name:gsub("%.", "/")

  local config = require("blade-nav.core.config")
  local extensions = config.get("inertia_extensions") or { "vue", "tsx", "jsx", "ts" }
  if #extensions == 0 then
    extensions = { "vue", "tsx", "jsx", "ts" }
  end

  local root = fs.get_root_dir()
  for _, ext in ipairs(extensions) do
    local file_path = root .. "/resources/js/" .. path .. "/" .. page_name .. "." .. ext
    if vim.fn.filereadable(file_path) == 1 then
      return file_path
    end
  end

  -- Folder-style pages: Page/index.<ext>
  for _, ext in ipairs(extensions) do
    local file_path = root .. "/resources/js/" .. path .. "/" .. page_name .. "/index." .. ext
    if vim.fn.filereadable(file_path) == 1 then
      return file_path
    end
  end

  return root .. "/resources/js/" .. path .. "/" .. page_name .. "." .. extensions[1]
end

local ERE_SPECIAL_CHARS = {
  ["."] = true,
  ["^"] = true,
  ["$"] = true,
  ["*"] = true,
  ["+"] = true,
  ["?"] = true,
  ["("] = true,
  [")"] = true,
  ["["] = true,
  ["]"] = true,
  ["{"] = true,
  ["}"] = true,
  ["|"] = true,
  ["\\"] = true,
}

--- Escapes ERE (extended regular expression) metacharacters for use in an
--- `rg`/`grep -E` pattern.
--- @param str string
--- @return string
local function escape_ere(str)
  return (str:gsub(".", function(c)
    if ERE_SPECIAL_CHARS[c] then
      return "\\" .. c
    end
    return c
  end))
end

local function find_controller_for_page(page_name)
  local root = fs.get_root_dir()
  local dot_name = page_name:gsub("/", ".")
  local slash_name = page_name:gsub("%.", "/")

  -- Anchor the page name with a closing quote so 'Admin/User' does not also
  -- match 'Admin/UserList'.
  local pattern = table.concat({
    "inertia\\(.*['\"]" .. escape_ere(slash_name) .. "['\"]",
    "inertia\\(.*['\"]" .. escape_ere(dot_name) .. "['\"]",
    "Inertia::render\\(.*['\"]" .. escape_ere(slash_name) .. "['\"]",
    "Inertia::render\\(.*['\"]" .. escape_ere(dot_name) .. "['\"]",
  }, "|")

  local grep_cmd
  if fs.command_exists("rg") then
    grep_cmd = { "rg", "--files-with-matches", "--glob", "*.php", "--glob", "!vendor/**", "-e", pattern, root }
  elseif fs.command_exists("grep") then
    grep_cmd = { "grep", "-rlE", "--include=*.php", "--exclude-dir=vendor", pattern, root }
  else
    return {}
  end

  local output, ok = cmd.execute_silent(grep_cmd, { cwd = root })
  if not ok or not output or output == "" then
    return {}
  end

  local files = vim.split(output, "\n", { trimempty = true })
  local results = {}
  for _, f in ipairs(files) do
    local rel = fs.project_relative(f)
    if rel and rel ~= "" then
      table.insert(results, rel)
    end
  end

  return results
end

local function resolve_reverse(target_info)
  local page_name = target_info.name
  log.debug("Reverse resolving inertia page: %s", page_name)

  -- The reverse lookup greps the whole project synchronously; cache the
  -- result per buffer so repeated gf on the same page is cheap.
  local bufname = vim.api.nvim_buf_get_name(0)
  local cache_key = "inertia_reverse:" .. (bufname ~= "" and bufname or page_name)
  local controllers = cache.get(cache_key)
  if not controllers then
    controllers = find_controller_for_page(page_name)
    cache.set(cache_key, controllers)
  end

  if #controllers == 0 then
    log.debug("No controller found for inertia page: %s", page_name)
    return false
  end

  if #controllers == 1 then
    vim.cmd("edit " .. vim.fn.fnameescape(controllers[1]))
    return true
  end

  choice.select_file("Select controller for " .. page_name, controllers)
  return true
end

--- Resolves and opens/navigates to the inertia definition.
--- @param target_info BladeNavTargetInfo The target info returned by get_target.
--- @return boolean True if successfully opened.
function M.resolve(target_info)
  if not target_info or not target_info.name then
    log.warn("inertia resolve called with invalid target_info: %s", vim.inspect(target_info))
    return false
  end

  if target_info.type == "inertia_reverse" then
    return resolve_reverse(target_info)
  end

  if target_info.type ~= "inertia" then
    return false
  end

  local inertia_name = target_info.name
  log.debug("Resolving inertia: %s", inertia_name)

  local file_path = get_path(inertia_name)
  log.debug("File path: %s", file_path)

  if file_path and vim.fn.filereadable(file_path) == 1 then
    vim.cmd("edit " .. vim.fn.fnameescape(file_path))
    return true
  end

  return false
end

return M
