-- lua/blade-nav/extractors/env.lua

local uv = vim.uv

local cache = require("blade-nav.utils.cache")
local fs = require("blade-nav.utils.fs")
local log = require("blade-nav.utils.log")

local M = {}

local watcher = nil

local function start_watcher(env_file)
  if watcher then
    return
  end
  -- Watch the parent directory rather than the file itself: editors that
  -- save atomically (write a temp file, then rename over the original)
  -- replace the watched inode, silently detaching a direct file watch.
  local dir = vim.fn.fnamemodify(env_file, ":h")
  local env_basename = vim.fn.fnamemodify(env_file, ":t")
  watcher = uv.new_fs_event()
  watcher:start(dir, {}, function(err, fname)
    if err then
      return
    end
    if fname == env_basename then
      cache.clear("env_keys")
      cache.clear("env_kv_map")
    end
  end)
end

--- Parse .env keys with Tree-sitter bash parser
--- @param bufnr integer
--- @return string[]
local function parse_with_treesitter(bufnr)
  log.debug("Parsing .env with treesitter")
  local ok_parser, parser = pcall(vim.treesitter.get_parser, bufnr, "bash")
  if not ok_parser or not parser then
    return {}
  end

  local tree = parser:parse()[1]
  local root = tree:root()
  local acc = {}

  for node in root:iter_children() do
    log.debug("Node type: %s", node:type())
    if node:type() == "variable_assignment" then
      local name_node = node:field("name")[1]
      if name_node then
        local key = vim.treesitter.get_node_text(name_node, bufnr)
        if key and key ~= "" then
          table.insert(acc, key)
        end
      end
    end
  end

  return acc
end

--- Fallback parser with regex if bash parser is missing
--- @param filepath string
--- @return string[]
local function parse_with_regex(filepath)
  local results = {}
  local file = io.open(filepath, "r")
  if not file then
    return results
  end
  for line in file:lines() do
    local key = line:match("^%s*([A-Z0-9_]+)%s*=")
    if key then
      table.insert(results, key)
    end
  end
  file:close()
  return results
end

--- Return env keys from .env (cached, with fs watcher)
--- @return string[]
function M.get_keys()
  log.debug("Getting env keys")
  local cache_key = "env_keys"
  local cached = cache.get(cache_key)
  if cached then
    return cached
  end

  local root = fs.get_root_dir()
  local env_file = fs.normalize_path(root .. "/.env")
  if not fs.path_exists(env_file) then
    return {}
  end

  local bufnr = vim.fn.bufadd(env_file)
  vim.fn.bufload(bufnr)

  local results = parse_with_treesitter(bufnr)
  if #results == 0 then
    results = parse_with_regex(env_file)
  end

  cache.set(cache_key, results)

  start_watcher(env_file)

  return results
end

--- Return env key->value map from .env (cached, with fs watcher), using treesitter if available.
--- @return table<string, string>
function M.get_map()
  local cache_key = "env_kv_map"
  local cached = cache.get(cache_key)
  if cached then
    return cached
  end

  local root = fs.get_root_dir()
  local env_file = fs.normalize_path(root .. "/.env")
  if not fs.path_exists(env_file) then
    return {}
  end

  local bufnr = vim.fn.bufadd(env_file)
  vim.fn.bufload(bufnr)

  local ok_parser, parser = pcall(vim.treesitter.get_parser, bufnr, "bash")
  local map = {}

  if ok_parser and parser then
    local tree = parser:parse()[1]
    local root_node = tree and tree:root()
    if root_node then
      local ok_q, query = pcall(
        vim.treesitter.query.parse,
        "bash",
        [[
        (variable_assignment
          name: (variable_name) @name
          value: (_) @val)?
      ]]
      )
      if ok_q and query then
        for _, match, _ in query:iter_matches(root_node, bufnr) do
          local name_node, val_node
          for id, nodes in pairs(match) do
            local cap = query.captures[id]
            if cap == "name" then
              name_node = nodes[1]
            end
            if cap == "val" then
              val_node = nodes[1]
            end
          end

          if name_node then
            local key = vim.treesitter.get_node_text(name_node, bufnr)
            local val = val_node and vim.treesitter.get_node_text(val_node, bufnr) or ""
            val = val:gsub("^%s*['\"]", ""):gsub("['\"]%s*$", "")
            map[key] = val
          end
        end
      end
    end
  end

  if vim.tbl_isempty(map) then
    local file = io.open(env_file, "r")
    if file then
      for line in file:lines() do
        local key, val = line:match("^%s*([A-Z0-9_]+)%s*=%s*(.*)")
        if key then
          val = val:gsub("^%s*['\"]", ""):gsub("['\"]%s*$", ""):gsub("%s+$", "")
          map[key] = val
        end
      end
      file:close()
    end
  end

  cache.set(cache_key, map)

  start_watcher(env_file)

  return map
end

function M.stop_watcher()
  if watcher and not watcher:is_closing() then
    watcher:stop()
    watcher:close()
  end
  watcher = nil
end

return M
