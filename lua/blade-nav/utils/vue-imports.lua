-- lua/blade-nav/utils/vue-imports.lua
local config = require("blade-nav.core.config")
local log = require("blade-nav.utils.log")
local fs = require("blade-nav.utils.fs")

local ts = vim.treesitter
local api = vim.api
local fn = vim.fn

-- Module-local caches (not the shared utils/cache.lua module: these keys are
-- ad-hoc and would pollute/collide with that module's namespace).
-- imports_cache keeps only the latest changedtick entry per buffer.
local imports_cache = {}
local jsconfig_cache = nil

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
  local current_name = nil

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
      current_name = text
    elseif js_name == "source" and current_name then
      imports[current_name] = text:gsub("[\"']", "")
      current_name = nil
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

  local changedtick = api.nvim_buf_get_changedtick(bufnr)
  local cached = imports_cache[bufnr]
  if cached and cached.changedtick == changedtick then
    return cached.data
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

  imports_cache[bufnr] = {
    changedtick = changedtick,
    data = imports,
    timestamp = vim.uv.now(),
  }

  return imports
end

--- Resolve the configured jsconfig path against the project root (relative
--- config values must not depend on Neovim's cwd).
---@return string|nil
local function jsconfig_path()
  local configured = config.get("jsconfig_path")
  if not configured or configured == "" then
    return nil
  end
  if configured:sub(1, 1) ~= "/" then
    configured = fs.get_root_dir() .. "/" .. configured
  end
  return (configured:gsub("/%./", "/"))
end

---Read and parse jsconfig.json
---@return table|nil config Parsed jsconfig or nil if failed
local function read_jsconfig()
  local path = jsconfig_path()
  if not path then
    return nil
  end

  -- Invalidate the cached parse when the file changes on disk (mtime).
  local stat = vim.uv.fs_stat(path)
  local mtime_sec = stat and stat.mtime and stat.mtime.sec or nil
  local mtime_nsec = stat and stat.mtime and stat.mtime.nsec or nil

  if
    jsconfig_cache
    and jsconfig_cache.path == path
    and jsconfig_cache.mtime_sec == mtime_sec
    and jsconfig_cache.mtime_nsec == mtime_nsec
  then
    return jsconfig_cache.data
  end

  log.debug("Reading jsconfig:", path)
  local data = fs.read_file(path)
  if not data then
    return nil
  end

  local ok, parsed = pcall(fn.json_decode, data)
  if not ok then
    log.error("Failed to parse jsconfig.json")
    return nil
  end

  jsconfig_cache = {
    path = path,
    mtime_sec = mtime_sec,
    mtime_nsec = mtime_nsec,
    data = parsed,
  }
  return parsed
end

---Resolve import paths using jsconfig aliases.
---Alias targets are relative to the project root (where jsconfig.json lives),
---so matches are rewritten to root-absolute paths.
---@param imports table Table of imports to resolve
---@param jsconfig table Parsed jsconfig.json
local function resolve_imports(imports, jsconfig)
  local paths = jsconfig.compilerOptions and jsconfig.compilerOptions.paths
  if not paths then
    return
  end

  local root = fs.get_root_dir()

  for name, path in pairs(imports) do
    for alias, replacement_paths in pairs(paths) do
      local alias_pattern = alias:gsub("/%*", "/")
      if path:sub(1, #alias_pattern) == alias_pattern then
        -- An alias may map to an empty array in jsconfig; skip those.
        local first = replacement_paths[1]
        if type(first) == "string" then
          local replacement = first:gsub("/%*", "/")
          imports[name] = root .. "/" .. (path:gsub(alias_pattern, replacement))
        end
      end
    end
  end
end

-- Extensions probed for extensionless imports, in priority order.
local PROBE_EXTENSIONS = { "vue", "tsx", "jsx", "ts", "js" }

---Probe an import path for a concrete file: for extensionless paths try
---"<path>.<ext>" and "<path>/index.<ext>" for the known extensions.
---@param path string Absolute path
---@return string
local function probe_import_path(path)
  if fn.filereadable(path) == 1 then
    return path
  end
  if path:match("%.%w+$") then
    -- Already has an extension; nothing to probe.
    return path
  end
  for _, ext in ipairs(PROBE_EXTENSIONS) do
    local candidate = path .. "." .. ext
    if fn.filereadable(candidate) == 1 then
      return candidate
    end
  end
  for _, ext in ipairs(PROBE_EXTENSIONS) do
    local candidate = path .. "/index." .. ext
    if fn.filereadable(candidate) == 1 then
      return candidate
    end
  end
  return path
end

---Resolve the import path
---@param line text Line of text of the current expresion
---@return string|nil path Resolved path or nil if not found
function M.resolve_path_for(line)
  local tag_name = M.get_tag_name_for(line)
  if not tag_name then
    log.debug("No tag found under cursor")
    return nil
  end
  log.debug("Tag name: %s", tag_name)

  local bufnr = api.nvim_get_current_buf()
  local imports = analyze_imports(bufnr)
  local jsconfig = read_jsconfig()
  log.debug("Imports: %s", vim.inspect(imports))

  if jsconfig then
    resolve_imports(imports, jsconfig)
  end

  local path = imports[tag_name]
  if not path then
    return nil
  end

  if path:sub(1, 2) == "./" or path:sub(1, 3) == "../" then
    -- Relative import: resolve against the importing buffer's directory so
    -- the result does not depend on Neovim's cwd.
    local buf_name = api.nvim_buf_get_name(bufnr)
    local base = buf_name ~= "" and fn.fnamemodify(buf_name, ":p:h") or fn.getcwd()
    path = vim.fs.normalize(base .. "/" .. path)
  end

  local is_absolute = path:sub(1, 1) == "/" or path:match("^%a:[/\\]") ~= nil
  if is_absolute then
    path = probe_import_path(path)
  end

  return path
end

return M
