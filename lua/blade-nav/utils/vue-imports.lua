-- lua/blade-nav/utils/vue-imports.lua
local config = require("blade-nav.core.config")
local cache = require("blade-nav.utils.cache")
local log = require("blade-nav.utils.log")
local fs = require("blade-nav.utils.fs")

local ts = vim.treesitter
local api = vim.api
local fn = vim.fn
--
-- Query definitions with proper documentation
local QUERIES = {
  -- Matches Vue script setup blocks
  vue = [[
    (script_element
      (start_tag
        (attribute
          (attribute_name) @setup
          (#eq? @setup "setup")))
      (raw_text) @script_content)
  ]],
  -- Matches ES6 import statements
  javascript = [[
    (program
      (import_statement
        (import_clause
          (identifier) @name)
        source: (string
          (string_fragment) @source)))
  ]],
}

-- Pre-compile queries for better performance
local cached_queries = setmetatable({}, {
  __index = function(self, key)
    self[key] = ts.query.parse(key, QUERIES[key])
    return self[key]
  end,
})

---Parse JavaScript content for imports
---@param content string JavaScript content
---@return table imports Table of imports
local function parse_javascript_content(content)
  local imports = {}

  local js_parser = ts.get_string_parser(content, "javascript")
  if not js_parser then
    log.error("Failed to create JavaScript parser")
    return imports
  end

  local js_tree = js_parser:parse()[1]
  local js_root = js_tree:root()

  for js_id, js_node in cached_queries.javascript:iter_captures(js_root, content) do
    local js_name = cached_queries.javascript.captures[js_id]
    local text = ts.get_node_text(js_node, content)

    if js_name == "name" then
      imports.current_name = text
    elseif js_name == "source" and imports.current_name then
      imports[imports.current_name] = text:gsub("[\"']", "")
      imports.current_name = nil
    end
  end

  return imports
end

local M = {}

local function clean_text(text)
  return text and text:gsub("^%s*(.-)%s*$", "%1") or nil
end

local function find_tagname(node, src)
  if node:type() == "tag_name" then
    return ts.get_node_text(node, src)
  end
  for child in node:iter_children() do
    local result = find_tagname(child, src)
    if result then
      return result
    end
  end
end

---Get the tag name under the cursor
---@param line text Line of text of the current expresion
---@return string|nil tag_name Tag name or nil if not found
function M.get_tag_name_for(line)
  if not line or line == "" then
    return nil
  end

  local ok, parser = pcall(ts.get_string_parser, line, "html")
  if not ok or not parser then
    return nil
  end

  local tree = parser:parse()[1]
  if not tree then
    return nil
  end

  local root = tree:root()
  local tagname = find_tagname(root, line)

  return clean_text(tagname)
end

---Analyze imports in a Vue file
---@param bufnr number? Buffer number (optional, defaults to current buffer)
---@return table imports Table of imports
local function analyze_imports(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()

  local cache_key = tostring(bufnr)
  if cache.imports[cache_key] then
    return cache.imports[cache_key].data
  end

  local parser = ts.get_parser(bufnr, "vue")
  if not parser then
    log.error("Failed to get Vue parser")
    return {}
  end

  local imports = {}
  local tree = parser:parse()[1]
  local root = tree:root()

  for id, node in cached_queries.vue:iter_captures(root, bufnr) do
    local name = cached_queries.vue.captures[id]
    if name == "script_content" then
      imports = parse_javascript_content(ts.get_node_text(node, bufnr))
      break
    end
  end

  cache.imports[cache_key] = {
    data = imports,
    timestamp = now,
  }

  return imports
end

---Read and parse jsconfig.json
---@return table|nil config Parsed jsconfig or nil if failed
local function read_jsconfig()
  if cache.jsconfig then
    return cache.jsconfig
  end

  log.debug("Reading jsconfig:", vim.inspect(config.get("jsconfig_path")))
  local data = fs.read_file(config.get("jsconfig_path"))
  if not data then
    return nil
  end

  local ok, parsed = pcall(fn.json_decode, data)
  if not ok then
    log.error("Failed to parse jsconfig.json")
    return nil
  end

  cache.jsconfig = parsed
  return parsed
end

---Resolve import paths using jsconfig aliases
---@param imports table Table of imports to resolve
---@param jsconfig table Parsed jsconfig.json
local function resolve_imports(imports, jsconfig)
  local paths = jsconfig.compilerOptions and jsconfig.compilerOptions.paths
  if not paths then
    return
  end

  for name, path in pairs(imports) do
    for alias, replacement_paths in pairs(paths) do
      local alias_pattern = alias:gsub("/%*", "/")
      if path:sub(1, #alias_pattern) == alias_pattern then
        local replacement = replacement_paths[1]:gsub("/%*", "/")
        imports[name] = path:gsub(alias_pattern, "./" .. replacement)
      end
    end
  end
end

---Resolve the import path
---@param line text Line of text of the current expresion
---@return string|nil path Resolved path or nil if not found
function M.resolve_path_for(line)
  if not cache.imports then
    cache.imports = {}
  end

  local tag_name = M.get_tag_name_for(line)
  if not tag_name then
    log.debug("No tag found under cursor")
    return nil
  end
  log.debug("Tag name: %s", tag_name)

  local imports = analyze_imports()
  local jsconfig = read_jsconfig()
  log.debug("Imports: %s", vim.inspect(imports))

  if jsconfig then
    resolve_imports(imports, jsconfig)
  end

  return imports[tag_name]
end

return M
