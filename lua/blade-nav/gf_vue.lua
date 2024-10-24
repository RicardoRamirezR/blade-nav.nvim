-- Vue Imports Module
-- Provides functionality to analyze and resolve Vue component imports using treesitter
-- @module vue-imports

local M = {}
local ts = vim.treesitter
local api = vim.api
local fn = vim.fn
local uv = vim.loop

---@class Config
---@field jsconfig_path string Path to jsconfig.json
---@field debug boolean Enable debug logging
---@field cache_timeout number Cache timeout in milliseconds
local DEFAULT_CONFIG = {
  jsconfig_path = "./jsconfig.json",
  debug = false,
  cache_timeout = 5000, -- 5 seconds
}

-- Cache management
local cache = {
  imports = {},
  jsconfig = nil,
  last_updated = 0,
}

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

-- Improved logging with levels and formatting
local log = {
  debug = function(msg, ...)
    if M.config.debug then
      print(string.format("[Vue Import Debug] " .. msg, ...))
    end
  end,
  error = function(msg, ...)
    vim.notify(string.format("[Vue Import Error] " .. msg, ...), vim.log.levels.ERROR)
  end,
}

---Safely read and parse a file
---@param path string File path
---@return string|nil content File content or nil if failed
local function safe_read_file(path)
  local ok, fd = pcall(uv.fs_open, path, "r", 438)
  if not ok then
    log.debug("Failed to open file: %s", path)
    return nil
  end

  local stat = assert(uv.fs_fstat(fd))
  local data = assert(uv.fs_read(fd, stat.size, 0))
  uv.fs_close(fd)

  return data
end

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

---Analyze imports in a Vue file
---@param bufnr number? Buffer number (optional, defaults to current buffer)
---@return table imports Table of imports
function M.analyze_imports(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()

  -- Check cache first
  local cache_key = tostring(bufnr)
  local now = uv.now()
  if cache.imports[cache_key] and (now - cache.imports[cache_key].timestamp) < M.config.cache_timeout then
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

  -- Update cache
  cache.imports[cache_key] = {
    data = imports,
    timestamp = now,
  }

  return imports
end

---Read and parse jsconfig.json
---@return table|nil config Parsed jsconfig or nil if failed
function M.read_jsconfig()
  if cache.jsconfig and (uv.now() - cache.last_updated) < M.config.cache_timeout then
    return cache.jsconfig
  end

  local data = safe_read_file(M.config.jsconfig_path)
  if not data then
    return nil
  end

  local ok, parsed = pcall(fn.json_decode, data)
  if not ok then
    log.error("Failed to parse jsconfig.json")
    return nil
  end

  cache.jsconfig = parsed
  cache.last_updated = uv.now()
  return parsed
end

---Resolve import paths using jsconfig aliases
---@param imports table Table of imports to resolve
---@param jsconfig table Parsed jsconfig.json
function M.resolve_imports(imports, jsconfig)
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

---Get the tag name under the cursor
---@return string|nil tag_name Tag name or nil if not found
function M.get_tag_name_under_cursor()
  local ts_utils = require("nvim-treesitter.ts_utils")
  local node = ts_utils.get_node_at_cursor()

  while node do
    if node:type() == "element" then
      for child in node:iter_children() do
        if child:type() == "start_tag" or child:type() == "self_closing_tag" then
          for tag_name in child:iter_children() do
            if tag_name:type() == "tag_name" then
              return ts.get_node_text(tag_name, 0)
            end
          end
        end
      end
    end
    node = node:parent()
  end

  return nil
end

---Resolve the import path under the cursor
---@return string|nil path Resolved path or nil if not found
function M.resolve_path_under_cursor()
  local tag_name = M.get_tag_name_under_cursor()
  if not tag_name then
    log.debug("No tag found under cursor")
    return nil
  end

  local imports = M.analyze_imports()
  local jsconfig = M.read_jsconfig()

  if jsconfig then
    M.resolve_imports(imports, jsconfig)
  end

  return imports[tag_name]
end

---Setup the module with custom configuration
---@param opts table? Optional configuration table
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", DEFAULT_CONFIG, opts or {})
end

---Go to file under cursor command implementation
---@return boolean success Whether the operation was successful
function M.gf()
  if vim.bo.filetype ~= "vue" then
    return false
  end

  local path = M.resolve_path_under_cursor()
  if path then
    local ok, err = pcall(vim.cmd, "edit " .. path)
    if not ok then
      log.error("Failed to open file: %s", err)
      return false
    end
    return true
  end
  return false
end

-- Initialize with default config
M.setup()

return M
