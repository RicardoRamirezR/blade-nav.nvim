-- lua/blade-nav/extractors/lang.lua

local uv = vim.loop
local fs = require("blade-nav.utils.fs")
local cache = require("blade-nav.utils.cache")
local log = require("blade-nav.utils.log")

local M = {}

local watcher = nil

--- Remove UTF-8 BOM from beginning of text if present
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

--- Parse JSON translation file
--- @param filepath string
--- @return table<string, string>
local function parse_json_translations(filepath)
  local translations = {}

  local ok, lines = pcall(vim.fn.readfile, filepath)
  if not ok or not lines or #lines == 0 then
    return translations
  end

  local text = table.concat(lines, "\n")
  text = strip_bom(text)

  local ok_json, data = pcall(vim.json.decode, text)
  if ok_json and type(data) == "table" then
    for key, value in pairs(data) do
      if type(value) == "string" then
        translations[key] = value
      end
    end
  end

  return translations
end

--- Parse PHP translation file
--- @param filepath string
--- @return table<string, string>
local function parse_php_translations(filepath)
  local translations = {}

  local content = fs.read_file(filepath)
  if not content then
    return translations
  end

  local ts = vim.treesitter
  local parser = ts.get_string_parser(content, "php")
  if not parser then
    return translations
  end

  local tree = parser:parse()[1]
  local root = tree:root()

  local function walk_array(file_content, arr_node, current_prefix)
    for child in arr_node:iter_children() do
      if child:type() == "array_element_initializer" then
        local k_node, v_node
        for gc in child:iter_children() do
          if not k_node and (gc:type() == "string" or gc:type() == "encapsed_string") then
            k_node = gc
          elseif not v_node and gc:type() ~= "=>" and gc:type() ~= "," then
            v_node = gc
          end
        end

        if k_node and v_node then
          local key = ts.get_node_text(k_node, file_content):gsub("^[\"']", ""):gsub("[\"']$", "")
          local full_key = current_prefix and (current_prefix .. "." .. key) or key

          if v_node:type() == "array_creation_expression" then
            walk_array(file_content, v_node, full_key)
          elseif v_node:type() == "string" or v_node:type() == "encapsed_string" then
            local value = ts.get_node_text(v_node, file_content):gsub("^[\"']", ""):gsub("[\"']$", "")
            translations[full_key] = value
          end
        end
      end
    end
  end

  for child in root:iter_children() do
    if child:type() == "return_statement" then
      for grand in child:iter_children() do
        if grand:type() == "array_creation_expression" then
          walk_array(content, grand, nil)
        end
      end
    end
  end

  return translations
end

--- Get translation value for a key
--- @param key string
--- @return string|nil
function M.get_translation(key)
  local map = M.get_map()
  return map[key]
end

--- Get all translation keys
--- @return string[]
function M.get_keys()
  local map = M.get_map()
  local keys = vim.tbl_keys(map)
  table.sort(keys)
  return keys
end

--- Get complete translation map
--- @return table<string, string>
function M.get_map()
  local cache_key = "lang_translations_map"
  local cached = cache.get(cache_key)
  if cached then
    return cached
  end

  local root = fs.get_root_dir()
  local lang_dir = fs.normalize_path(root .. "/resources/lang")

  if not fs.is_dir(lang_dir) then
    return {}
  end

  local map = {}

  -- Get default locale from config (fallback to 'en')
  local default_locale = "en"
  local app_config = fs.normalize_path(root .. "/config/app.php")
  if fs.path_exists(app_config) then
    local content = fs.read_file(app_config)
    if content then
      local locale_match = content:match("'locale'%s*=>%s*'([^']+)'")
      if locale_match then
        default_locale = locale_match
      end
    end
  end

  -- Scan for locales
  local handle = uv.fs_scandir(lang_dir)
  if not handle then
    return {}
  end

  local locales = {}
  while true do
    local name, t = uv.fs_scandir_next(handle)
    if not name then
      break
    end

    if t == "directory" then
      table.insert(locales, name)
    elseif name:match("^(%a+)%.json$") then
      local locale = name:match("^(%a+)%.json$")
      if not vim.tbl_contains(locales, locale) then
        table.insert(locales, locale)
      end
    end
  end

  -- Prioritize default locale
  if vim.tbl_contains(locales, default_locale) then
    table.sort(locales, function(a, b)
      if a == default_locale then
        return true
      end
      if b == default_locale then
        return false
      end
      return a < b
    end)
  end

  -- Parse translations from default locale first
  for _, locale in ipairs(locales) do
    -- JSON files (simple keys)
    local json_path = fs.normalize_path(lang_dir .. "/" .. locale .. ".json")
    if fs.path_exists(json_path) then
      local json_trans = parse_json_translations(json_path)
      for key, value in pairs(json_trans) do
        if not map[key] or locale == default_locale then
          map[key] = value
        end
      end
    end

    -- PHP files (namespaced keys like "messages.welcome")
    local locale_dir = fs.normalize_path(lang_dir .. "/" .. locale)
    if fs.is_dir(locale_dir) then
      local php_files = fs.find_files(locale_dir, "php") or {}
      for _, php_file in ipairs(php_files) do
        local basename = php_file:match("([^/]+)%.php$")
        if basename then
          local php_trans = parse_php_translations(php_file)
          for key, value in pairs(php_trans) do
            local full_key = basename .. "." .. key
            if not map[full_key] or locale == default_locale then
              map[full_key] = value
            end
          end
        end
      end
    end

    -- Only process default locale for initial map
    if locale == default_locale then
      break
    end
  end

  cache.set(cache_key, map)

  -- Watch for changes
  if not watcher then
    watcher = uv.new_fs_event()
    watcher:start(lang_dir, { recursive = true }, function()
      cache.clear(cache_key)
    end)
  end

  return map
end

function M.stop_watcher()
  if watcher and not watcher:is_closing() then
    watcher:stop()
    watcher:close()
  end
  watcher = nil
end

-- Returns a table: { locale1 = { key = value, ... }, locale2 = { ... } }
function M.get_map_all_locales()
  local cache_key = "lang_translations_map_all_locales"
  local cached = cache.get(cache_key)
  if cached then
    return cached
  end

  local root = fs.get_root_dir()
  local lang_dir = fs.normalize_path(root .. "/resources/lang")
  if not fs.is_dir(lang_dir) then
    return {}
  end

  local maps = {}

  local handle = uv.fs_scandir(lang_dir)
  if not handle then
    return {}
  end

  local locales = {}
  while true do
    local name, t = uv.fs_scandir_next(handle)
    if not name then
      break
    end
    if t == "directory" then
      table.insert(locales, name)
    elseif name:match("^(%a+)%.json$") then
      local locale = name:match("^(%a+)%.json$")
      if not vim.tbl_contains(locales, locale) then
        table.insert(locales, locale)
      end
    end
  end

  table.sort(locales)

  for _, locale in ipairs(locales) do
    local locale_map = {}

    -- json file (locale.json)
    local json_path = fs.normalize_path(lang_dir .. "/" .. locale .. ".json")
    if fs.path_exists(json_path) then
      local json_trans = parse_json_translations(json_path)
      for k, v in pairs(json_trans) do
        locale_map[k] = v
      end
    end

    -- php files inside locale dir
    local locale_dir = fs.normalize_path(lang_dir .. "/" .. locale)
    if fs.is_dir(locale_dir) then
      local php_files = fs.find_files(locale_dir, "php") or {}
      for _, php_file in ipairs(php_files) do
        local basename = php_file:match("([^/]+)%.php$")
        if basename then
          local php_trans = parse_php_translations(php_file)
          for k, v in pairs(php_trans) do
            local full_key = basename .. "." .. k
            locale_map[full_key] = v
          end
        end
      end
    end

    maps[locale] = locale_map
  end

  cache.set(cache_key, maps)

  if not watcher then
    watcher = uv.new_fs_event()
    watcher:start(lang_dir, { recursive = true }, function()
      cache.clear(cache_key)
      cache.clear("lang_translations_map") -- keep other cache in sync
    end)
  end

  return maps
end

return M
