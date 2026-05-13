-- /lua/blade-nav/extractors/config.lua

local uv = vim.uv
local ts = vim.treesitter
local fs = require("blade-nav.utils.fs")
local cache = require("blade-nav.utils.cache")
local env = require("blade-nav.extractors.env")

local M = {}

local env_map = nil
local watcher = nil

local function get_env_map()
  if not env_map then
    env_map = env.get_map() or {}
  end
  return env_map
end

--- Evaluate a PHP value node into a simplified representation.
--- Supports: string, number, boolean, null, array, env('KEY', default).
--- @param content string
--- @param node TSNode
--- @return { kind:string, text:string, array_size?:integer, ref?:string }
local function eval_value(content, node)
  local t = node:type()

  if t == "string" or t == "encapsed_string" then
    local raw = ts.get_node_text(node, content)
    local txt = raw:gsub("^%s*[\"']", ""):gsub("[\"']%s*$", "")
    return { kind = "scalar", text = txt }
  end

  if t == "integer" or t == "float" or t == "decimal" or t == "octal" or t == "hexadecimal" then
    return { kind = "scalar", text = ts.get_node_text(node, content) }
  end

  if t == "boolean" then
    local v = ts.get_node_text(node, content)
    return { kind = "scalar", text = (v == "true" and "true" or "false") }
  end

  if t == "null" then
    return { kind = "scalar", text = "null" }
  end

  if t == "array_creation_expression" then
    local count = 0
    for child in node:iter_children() do
      if child:type() == "array_element_initializer" then
        count = count + 1
      end
    end
    return { kind = "array", text = string.format("[array: %d]", count), array_size = count }
  end

  if t == "function_call_expression" then
    local name_node = node:child(0)
    if name_node and name_node:type() == "name" then
      local fname = ts.get_node_text(name_node, content)
      if fname == "env" then
        local args = node:child(1)
        if args and args:type() == "arguments" then
          local arg_nodes = {}
          for ch in args:iter_children() do
            if ch:type() == "argument" then
              table.insert(arg_nodes, ch)
            end
          end

          local key_inner = arg_nodes[1] and arg_nodes[1]:named_child(0)
          local def_inner = arg_nodes[2] and arg_nodes[2]:named_child(0)

          if key_inner then
            local key = ts.get_node_text(key_inner, content)
            key = key:gsub("^[\"']", ""):gsub("[\"']$", "")

            local val = get_env_map()[key]
            if val and val ~= "" then
              return { kind = "env_ref", ref = key, text = val }
            elseif def_inner then
              local def_eval = eval_value(content, def_inner)
              return { kind = "scalar", text = def_eval.text }
            else
              return { kind = "env_ref", ref = key, text = "(not found)" }
            end
          end
        end
      end
    end
    return { kind = "expr", text = "(expr)" }
  end

  return { kind = "expr", text = "(expr)" }
end

--- Build a key->value map from a config/*.php file
--- @param filepath string
--- @return table<string,{kind:string,text:string,array_size?:number,ref?:string}>, string
local function extract_config_file_map(filepath)
  local basename = filepath:match("([^/]+)%.php$")

  -- Read file content using fs.read_file
  local content = fs.read_file(filepath)
  if not content then
    return {}, basename
  end

  -- Create a parser from the string content
  local parser = ts.get_string_parser(content, "php")
  if not parser then
    return {}, basename
  end

  local tree = parser:parse()[1]
  local root = tree:root()
  local map = {}

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
            local sub_element_count = 0
            for sub_child in v_node:iter_children() do
              if sub_child:type() == "array_element_initializer" then
                sub_element_count = sub_element_count + 1
              end
            end

            map[full_key] = {
              kind = "array",
              text = "[array]",
              array_size = sub_element_count,
            }

            walk_array(file_content, v_node, full_key)
          else
            local evaluated = eval_value(file_content, v_node)
            map[full_key] = evaluated
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

  return map, basename
end

--- Get all config keys
--- @return string[]
function M.get_keys()
  local map = M.get_map()
  local keys = vim.tbl_keys(map)
  table.sort(keys)
  return keys
end

--- Get config map with evaluated values
--- @return table<string,{kind:string,text:string,array_size?:number,ref?:string}>
function M.get_map()
  local cache_key = "config_kv_map"
  local cached = cache.get(cache_key)
  if cached then
    return cached
  end

  local root = fs.get_root_dir()
  local config_dir = fs.normalize_path(root .. "/config")
  if not fs.is_dir(config_dir) then
    return {}
  end

  local files = fs.find_files(config_dir, "php") or {}
  local map = {}

  for _, f in ipairs(files) do
    local partial, basename = extract_config_file_map(f)
    if basename then
      for k, v in pairs(partial) do
        map[basename .. "." .. k] = v
      end
    end
  end

  cache.set(cache_key, map)

  if not watcher then
    watcher = uv.new_fs_event()
    watcher:start(config_dir, { recursive = true }, function()
      cache.clear(cache_key)
      env_map = nil
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

return M
