-- lua/blade-nav/targets/lang.lua
-- Target handler for Laravel localization references __()

local fs = require("blade-nav.utils.fs")
local log = require("blade-nav.utils.log")
local choice = require("blade-nav.utils.choice")

local M = {}

function M.get_capabilities()
  return {
    targets = { "__", "trans" },
    filetypes = { "blade", "php", "html", "javascript", "vue" },
  }
end

local function basename_no_ext(path)
  return vim.fn.fnamemodify(path, ":t:r")
end

local function file_exists(path)
  return fs and fs.path_exists and fs.path_exists(path)
end

local function strip_bom(text)
  if not text or #text < 3 then
    return text
  end
  local b1, b2, b3 = text:byte(1, 3)
  if b1 == 239 and b2 == 187 and b3 == 191 then
    return text:sub(4)
  end
  return text
end

-- Scan resources/lang recursively and return full candidate files.
-- Each entry: { locale = "en", path = "/full/path/to/resources/lang/..." }
local function get_available_locale_files()
  local results = {}
  local lang_dir = fs.get_root_dir() .. "/resources/lang"

  if not file_exists(lang_dir) then
    return results
  end

  local function scan_dir(dir)
    local handle = vim.loop.fs_scandir(dir)
    if not handle then
      return
    end

    while true do
      local name, t = vim.loop.fs_scandir_next(handle)
      if not name then
        break
      end

      local full_path = dir .. "/" .. name
      if t == "directory" then
        scan_dir(full_path)
      elseif name:match("%.php$") or name:match("%.json$") then
        -- detect a locale-ish segment from path parts (best-effort)
        local parts = vim.split(full_path, "/")
        local locale = nil
        for _, segment in ipairs(parts) do
          if segment:match("^[%a_%-]+$") and #segment <= 8 then
            -- heuristic: short alpha/underscore/hyphen segment
            locale = segment
          end
        end
        table.insert(results, { locale = locale or "unknown", path = fs.abs_path(full_path) })
      end
    end
  end

  scan_dir(lang_dir)
  return results
end

-- Key existence checks json
local function json_key_exists(filepath, key)
  local ok, lines = pcall(vim.fn.readfile, filepath)
  if not ok or not lines or #lines == 0 then
    return false
  end

  local text = strip_bom(table.concat(lines, "\n"))
  local ok_json, data = pcall(vim.json.decode, text)
  if ok_json and type(data) == "table" then
    return data[key] ~= nil
  end

  local esc_key = vim.fn.escape(key, "\\/.*$^~[]")
  local pattern = '\\v"' .. esc_key .. '"\\s*:'
  if vim.fn.match(text, pattern) >= 0 then
    return true
  end

  local lower_text = vim.fn.tolower(text)
  local lower_key = vim.fn.tolower(key)
  local pattern_ci = '\\v"' .. vim.fn.escape(lower_key, "\\/.*$^~[]") .. '"\\s*:'
  return vim.fn.match(lower_text, pattern_ci) >= 0
end

-- Key existence checks php
local function php_key_exists(filepath, key)
  if not key or key == "" then
    return true
  end

  local ok, lines = pcall(vim.fn.readfile, filepath)
  if not ok or not lines then
    return false
  end

  local text = strip_bom(table.concat(lines, "\n"))
  local esc_key = vim.fn.escape(key, "\\/.*$^~[]+?{}|()")
  local pattern = "\\v['\"]" .. esc_key .. "['\"]\\s*=>"

  local ok_match, result = pcall(vim.fn.match, text, pattern)
  if ok_match and result >= 0 then
    return true
  end

  -- fallback case-insensitive
  local lower_text = vim.fn.tolower(text)
  local lower_key = vim.fn.tolower(key)
  local esc_lower = vim.fn.escape(lower_key, "\\/.*$^~[]+?{}|()")
  local pattern_ci = "\\v['\"]" .. esc_lower .. "['\"]\\s*=>"

  local ok_match_ci, result_ci = pcall(vim.fn.match, lower_text, pattern_ci)
  return ok_match_ci and result_ci >= 0
end

-- Navigation (move cursor to key). These functions will open file
-- only if it's not already the current buffer.
local function ensure_buffer_open(filepath)
  local cur = vim.api.nvim_buf_get_name(0)
  if fs.abs_path(cur) ~= fs.abs_path(filepath) then
    vim.cmd("edit " .. vim.fn.fnameescape(filepath))
    vim.cmd("filetype detect")
  end
end

local function navigate_to_json_key(filepath, key_name)
  ensure_buffer_open(filepath)

  local bufnr = vim.api.nvim_get_current_buf()
  local ts_ok, ts = pcall(require, "vim.treesitter")
  if ts_ok and ts then
    local ok_p, parser = pcall(ts.get_parser, bufnr, "json")
    if ok_p and parser then
      local ok_parse, tree = pcall(function()
        return parser:parse()[1]
      end)
      if ok_parse and tree then
        local root = tree:root()
        local query_str = string.format(
          [[
            (pair
              key: (string (string_content) @keyname (#eq? @keyname "%s"))
            )
          ]],
          key_name
        )
        local ok_q, query = pcall(ts.query.parse, "json", query_str)
        if ok_q and query then
          for _, node in query:iter_captures(root, bufnr) do
            local start_row, start_col = node:range()
            vim.api.nvim_win_set_cursor(0, { start_row + 1, start_col })
            vim.cmd("normal! zz")
            return
          end
        end
      end
    end
  end

  -- fallback textual search
  local text_search_pattern = string.format('"%s"\\s*:', vim.fn.escape(key_name, '"'))

  local line_num = vim.fn.search(text_search_pattern, "nw")
  if line_num > 0 then
    vim.api.nvim_win_set_cursor(0, { line_num, 0 })
    vim.cmd("normal! zz")
  else
    log.info("Key '%s' exists (or file opened) but could not be visually located in %s", key_name, filepath)
  end
end

local function navigate_to_php_key(filepath, key_name)
  ensure_buffer_open(filepath)

  if not key_name or key_name == "" then
    return
  end

  local pattern = string.format("[\"']%s[\"']%s*=>", vim.fn.escape(key_name, "\"'"), "%s*")
  local line_num = vim.fn.search(pattern, "nw")
  if line_num > 0 then
    vim.api.nvim_win_set_cursor(0, { line_num, 0 })
    vim.cmd("normal! zz")
  else
    log.info("Could not locate PHP key '%s' in %s", key_name, filepath)
  end
end

function M.get_target(context)
  if not context or not context.target or not context.first_arg then
    return nil
  end

  if context.target and context.target ~= "__" and context.target ~= "trans" then
    return nil
  end

  local key = context.first_arg
  if not key or key == "" then
    return nil
  end

  local mode = key:find("%.") and "php" or "json"
  return { type = mode, name = key }
end

function M.resolve(target_info)
  if not target_info or not target_info.name then
    log.warn("Invalid target_info in localization.resolve: %s", vim.inspect(target_info))
    return false
  end

  local files = get_available_locale_files()
  if #files == 0 then
    log.warn("No localization files found in resources/lang")
    return false
  end

  local all_files = {}

  if target_info.type == "json" then
    for _, entry in ipairs(files) do
      if entry.path:match("%.json$") then
        local has_key = json_key_exists(entry.path, target_info.name)
        table.insert(all_files, {
          locale = entry.locale,
          path = entry.path,
          has_key = has_key,
          display = (has_key and "✓ " or "✗ ") .. fs.project_relative(entry.path),
        })
      end
    end
  else
    local parts = vim.split(target_info.name, ".", { plain = true })
    local file_name = table.remove(parts, 1)
    local key_name = table.concat(parts, ".")
    for _, entry in ipairs(files) do
      if entry.path:match("%.php$") then
        local base = basename_no_ext(entry.path)
        if base == file_name then
          local has_key = php_key_exists(entry.path, key_name)
          table.insert(all_files, {
            locale = entry.locale,
            path = entry.path,
            has_key = has_key,
            display = (has_key and "✓ " or "✗ ") .. fs.project_relative(entry.path),
          })
        end
      end
    end
  end

  if #all_files == 0 then
    log.warn("No localization files found for key '%s'", target_info.name)
    return false
  end

  table.sort(all_files, function(a, b)
    if a.has_key ~= b.has_key then
      return a.has_key
    end
    return a.path < b.path
  end)

  local choices = {}
  for _, f in ipairs(all_files) do
    table.insert(choices, f.display)
  end

  choice.select_file("Select locale/file for " .. target_info.name, choices, function(opened_filename)
    if not opened_filename or opened_filename == "" then
      return
    end

    local opened_abs = fs.abs_path(opened_filename)
    local chosen = nil
    for _, f in ipairs(all_files) do
      if fs.abs_path(f.path) == opened_abs then
        chosen = f
        break
      end
    end

    if not chosen then
      -- As fallback try matching by suffix
      for _, f in ipairs(all_files) do
        if opened_abs:sub(- #f.path) == f.path then
          chosen = f
          break
        end
      end
    end

    if not chosen then
      log.warn("Could not resolve chosen file for %s", opened_filename)
      return
    end

    if chosen.path:match("%.json$") then
      navigate_to_json_key(chosen.path, target_info.name)
    elseif chosen.path:match("%.php$") then
      -- For php we need the nested key (filename removed)
      local parts = vim.split(target_info.name, ".", { plain = true })
      table.remove(parts, 1) -- remove filename prefix
      local key_name = table.concat(parts, ".")
      navigate_to_php_key(chosen.path, key_name)
    end
  end)

  return true
end

return M
