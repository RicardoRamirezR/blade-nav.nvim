local M = {}

local ns = vim.api.nvim_create_namespace("blade-nav/values")

local config_extractor = require("blade-nav.extractors.config")
local env_extractor = require("blade-nav.extractors.env")
local lang_extractor = require("blade-nav.extractors.lang")
local log = require("blade-nav.utils.log")

local env_map_local = nil
local cfg_map = nil
local lang_map = nil

local function get_env_map()
  if not env_map_local then
    env_map_local = env_extractor.get_map()
  end
  return env_map_local
end

local function get_cfg_map()
  if not cfg_map then
    cfg_map = config_extractor.get_map()
  end
  return cfg_map
end

local function get_lang_map()
  if not lang_map then
    lang_map = lang_extractor.get_map()
  end
  return lang_map
end

local function invalidate_maps()
  env_map_local = nil
  cfg_map = nil
  lang_map = nil
end

-- Treesitter query for config/env/Config::get/Config::set/__() in PHP
local PHP_CALLS_Q = vim.treesitter.query.parse(
  "php",
  [[
  ; Standard function call: env('key', 'default') or env('key')
  (function_call_expression
    function: (name) @fn_name
    arguments: (arguments
      (argument
        (string (string_content) @key_str))
      (argument
        (string (string_content) @default_str))?)
    (#eq? @fn_name "env"))

  ; Standard function call: config('key')
  (function_call_expression
    function: (name) @fn_name
    arguments: (arguments
      (argument
        (string (string_content) @key_str)))
    (#eq? @fn_name "config"))

  ; Standard function call: __('key') or trans('key')
  (function_call_expression
    function: (name) @fn_name
    arguments: (arguments
      (argument
        (string (string_content) @key_str)))
    (#any-of? @fn_name "__" "trans"))

  ; Scoped call: Config::get('key', 'default') or Config::get('key')
  (scoped_call_expression
    scope: (name) @scope
    name: (name) @method
    arguments: (arguments
      (argument
        (string (string_content) @key_str))
      (argument
        (string (string_content) @default_str))?)
    (#eq? @scope "Config")
    (#any-of? @method "get" "set"))
]]
)

-- Treesitter query for config/env/__() calls in JavaScript (for Blade files)
local JS_CALLS_Q = vim.treesitter.query.parse(
  "javascript",
  [[
  ; JavaScript call expression: config('key'), env('key', 'default'), or __('key')
  (call_expression
    function: (identifier) @fn_name
    arguments: (arguments
      (string (string_fragment) @key_str)
      (string (string_fragment) @default_str)?)
    (#any-of? @fn_name "config" "env" "__" "trans"))

  ; Also catch calls in binary expressions
  (call_expression
    function: (identifier) @fn_name
    arguments: (arguments
      (string (string_fragment) @key_str))
    (#any-of? @fn_name "config" "env" "__" "trans"))
]]
)

assert(PHP_CALLS_Q, "Failed to parse PHP treesitter query")
assert(JS_CALLS_Q, "Failed to parse JavaScript treesitter query")

local function for_each_php_tree(bufnr, cb)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then
    return
  end
  parser:for_each_tree(function(tstree, langtree)
    if langtree:lang() == "php" then
      cb(tstree:root(), bufnr)
    end
  end)
end

local function for_each_js_tree(bufnr, cb)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then
    return
  end
  parser:for_each_tree(function(tstree, langtree)
    if langtree:lang() == "javascript" then
      cb(tstree:root(), bufnr)
    end
  end)
end

local function truncate(s, n)
  if not s or #s <= n then
    return s or ""
  end
  return s:sub(1, n - 1) .. "…"
end

local function find_enclosing_call(node)
  while node do
    local t = node:type()
    if t == "function_call_expression" or t == "scoped_call_expression" then
      return node
    end
    node = node:parent()
  end
  return nil
end

local function find_enclosing_js_call(node)
  while node do
    local t = node:type()
    if t == "call_expression" then
      return node
    end
    node = node:parent()
  end
  return nil
end

local function format_value(key, default_value, kind)
  if kind == "env" then
    local env_map_local = get_env_map()
    local env_value = env_map_local[key]
    if not env_value or env_value == "" then
      return default_value or "(not found)"
    end
    return env_value
  end

  if kind == "lang" then
    local maps = lang_extractor.get_map_all_locales()
    if not maps or vim.tbl_isempty(maps) then
      return "(no locales)"
    end

    local locales = vim.tbl_keys(maps)
    table.sort(locales)

    local parts = {}
    for _, locale in ipairs(locales) do
      local v = maps[locale] and maps[locale][key]
      if v and v ~= "" then
        table.insert(parts, string.format("%s: %s", locale, v))
      else
        table.insert(parts, string.format("%s: (missing)", locale))
      end
    end

    return table.concat(parts, " → ")
  end
  local cfg_map_local = get_cfg_map()
  local config_entry = cfg_map_local[key]
  if not config_entry then
    return "(not found)"
  end
  if config_entry.kind == "array" then
    return string.format("[array: %d]", config_entry.array_size or 0)
  end
  if config_entry.kind == "env_ref" then
    local env_map_local = get_env_map()
    local referenced_env_value = env_map_local[config_entry.ref] or "(not found)"
    return string.format("%s", referenced_env_value)
  end
  return config_entry.text
end

local function format_value_for_display(key, default_value, kind)
  if kind == "env" then
    local env_map_local = get_env_map()
    local env_value = env_map_local[key]
    if not env_value or env_value == "" then
      return ("env(%s) = %s"):format(key, default_value or "(not found)")
    end
    return ("env(%s) = %s"):format(key, env_value)
  end

  if kind == "lang" then
    local lang_map_local = get_lang_map()
    local lang_value = lang_map_local[key]
    if not lang_value or lang_value == "" then
      return ("__('%s') = (not found)"):format(key)
    end
    return ("__('%s') = %s"):format(key, lang_value)
  end

  local cfg_map_local = get_cfg_map()
  local config_entry = cfg_map_local[key]
  if not config_entry then
    return ("config(%s) = (not found)"):format(key)
  end
  if config_entry.kind == "array" then
    return ("config(%s) = [array: %d]"):format(key, config_entry.array_size or 0)
  end
  if config_entry.kind == "env_ref" then
    local env_map_local = get_env_map()
    local referenced_env_value = env_map_local[config_entry.ref] or "(not found)"
    return ("config(%s) = %s"):format(key, referenced_env_value)
  end
  return ("config(%s) = %s"):format(key, config_entry.text)
end

M.ns = ns
M.get_env_map = get_env_map
M.get_cfg_map = get_cfg_map
M.get_lang_map = get_lang_map
M.invalidate_maps = invalidate_maps
M.PHP_CALLS_Q = PHP_CALLS_Q
M.JS_CALLS_Q = JS_CALLS_Q
M.for_each_php_tree = for_each_php_tree
M.for_each_js_tree = for_each_js_tree
M.truncate = truncate
M.find_enclosing_call = find_enclosing_call
M.find_enclosing_js_call = find_enclosing_js_call
M.format_value = format_value
M.format_value_for_display = format_value_for_display

return M
