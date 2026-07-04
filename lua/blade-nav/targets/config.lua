-- lua/blade-nav/targets/config.lua
-- Target handler for Laravel config references like config('app.name'), Config::get('database.default').

local fs = require("blade-nav.utils.fs")
local log = require("blade-nav.utils.log")
local treesitter = require("blade-nav.utils.treesitter")

local M = {}

function M.get_capabilities()
  return {
    targets = { "config", "env", "Config::get", "Config::set" },
    filetypes = { "*" },
  }
end

--- Gets target information if the cursor is on a config reference.
--- Uses the line-based parsing utility function and specific pattern matching for cursor position.
--- Supports config(), env(), Config::get(), Config::set().
--- @param context BladeNavContext Context created by context.lua
--- @return BladeNavTargetInfo|nil { type = "config", name = "key.name" } or { type = "env", name = "VAR_NAME" } or nil
function M.get_target(context)
  if context.target and not vim.tbl_contains(M.get_capabilities().targets, context.target) then
    return nil
  end

  if context.first_arg and context.target then
    if context.target == "env" then
      return { type = "env", name = context.first_arg }
    end
    return { type = "config", name = context.first_arg }
  end

  local line = context.line
  log.debug("Processing line for config/env reference: %s", line)

  local found_keys_config = treesitter.extract_keys_from_code(line, "config")
  log.debug("Found keys for 'config/get/set': %s", vim.inspect(found_keys_config))

  local found_keys_env = treesitter.extract_keys_from_code(line, "env")
  log.debug("Found keys for 'env': %s", vim.inspect(found_keys_env))

  local all_keys = {}
  for i = 1, #found_keys_config do
    table.insert(all_keys, { type = "config", name = found_keys_config[i] })
  end
  for i = 1, #found_keys_env do
    table.insert(all_keys, { type = "env", name = found_keys_env[i] })
  end

  log.debug("Final aggregated keys: %s", vim.inspect(all_keys))

  if #all_keys == 0 then
    log.debug("No config/env keys found on line by utility.")
    return nil
  end

  return all_keys[1]
end

--- Resolves and opens/navigates to the config definition or .env file, including in-file navigation.
--- @param target_info BladeNavTargetInfo The target info returned by get_target.
--- @return boolean True if successfully opened or action taken.
function M.resolve(target_info)
  if not target_info or (target_info.type ~= "config" and target_info.type ~= "env") or not target_info.name then
    log.warn("config resolve called with invalid target_info: %s", vim.inspect(target_info))
    return false
  end

  local target_type = target_info.type
  local key_name = target_info.name

  if target_type == "env" then
    return M._resolve_env(key_name)
  end
  if target_type == "config" then
    return M._resolve_config(key_name)
  end

  log.warn("Unknown target type '%s'.", target_type)
  return false
end

--- Internal function to resolve and navigate within an .env file.
--- @param key_name string The environment variable name (e.g., "APP_KEY").
--- @return boolean True if successfully opened/navigated.
function M._resolve_env(key_name)
  local env_file_path = fs.get_root_dir() .. "/.env"
  local found = fs.path_exists(env_file_path) and not fs.is_dir(env_file_path)
  if not found then
    log.warn(".env file not found at '%s'.", env_file_path)
    return false
  end

  vim.cmd("edit " .. vim.fn.fnameescape(env_file_path))
  vim.cmd("filetype detect")
  -- vim.bo.filetype = "bash"

  local ts_status, ts = pcall(require, "vim.treesitter")
  if not ts_status or not ts then
    log.warn("(env): vim.treesitter not available for .env navigation.")
    return true
  end

  local parser_ok, parser = pcall(ts.get_parser, 0, "bash")
  if not parser_ok or not parser then
    log.warn("(env): Could not get 'bash' parser for .env file buffer.")
    return true
  end

  local tree_ok, tree = pcall(function()
    return parser:parse()[1]
  end)
  if not tree_ok or not tree then
    log.warn("Could not parse .env file buffer with 'bash' parser.")
    return true
  end

  local root = tree:root()
  local query_string = string.format(
    [[
            (variable_assignment
              name: (variable_name) @name
              (#eq? @name "%s"))
            ]],
    key_name
  )

  local query_ok, query = pcall(ts.query.parse, "bash", query_string)
  if not query_ok or not query then
    log.error("Failed to parse TS query for key '%s'. Error: %s", key_name, tostring(query))
    return true
  end

  local iter_ok, iter_result_or_err = pcall(function()
    for id, node, _ in query:iter_captures(root, 0) do
      local capture_name = query.captures[id]
      if capture_name == "name" then
        local start_row, start_col, _, _ = node:range()
        vim.api.nvim_win_set_cursor(0, { start_row + 1, start_col })
        vim.cmd("normal! zz")
        log.info("Navigated to key '%s' using Tree-sitter.", key_name)
        return true
      end
    end
    return false
  end)

  if not iter_ok then
    log.error("Error during TS query iteration for key '%s'. Error: %s", key_name, tostring(iter_result_or_err))
    return true
  end

  if iter_result_or_err == true then
    return true
  end

  log.info("Key '%s' not found in .env file via Tree-sitter query.", key_name)
  return true
end

--- Internal function to resolve and navigate within a Laravel config file.
--- @param full_config_key string The full config key (e.g., "app.debug", "services.whatsapp.token").
--- @return boolean True if successfully opened/navigated.
function M._resolve_config(full_config_key)
  log.debug("Resolving config key: %s", full_config_key)

  local parts = vim.split(full_config_key, ".", { plain = true })
  if #parts == 0 then
    log.error("Invalid config key format '%s'.", full_config_key)
    return false
  end

  local config_file_name = table.remove(parts, 1)
  local config_file_path = fs.get_root_dir() .. "/config/" .. config_file_name .. ".php"

  if not fs.path_exists(config_file_path) or fs.is_dir(config_file_path) then
    log.warn("Config file '%s' not found.", config_file_path)
    return false
  end

  vim.cmd("edit " .. vim.fn.fnameescape(config_file_path))
  vim.cmd("filetype detect")
  -- vim.bo.filetype = "php"

  local new_buf = vim.api.nvim_get_current_buf()
  log.info("Opened config file: %s", config_file_path)

  if #parts == 0 then
    log.info("Located and opened config file '%s'.", config_file_path)
    return true
  end

  local ok, result = pcall(M._goto_config_keys, new_buf, parts)
  if not ok then
    log.error("Error during in-file navigation: %s", tostring(result))
    return true
  end

  if result == true then
    log.info("Successfully navigated to key '%s' in '%s'.", full_config_key, config_file_path)
    return true
  end

  log.info("Opened file '%s'. Navigation to key '%s' did not find a match.", config_file_path, full_config_key)
  return true
end

-- Helper to move the cursor to a node
local function jump_to_node(node, key)
  local row, col = node:range()
  vim.api.nvim_win_set_cursor(0, { row + 1, col })
  vim.cmd("normal! zz")
  log.debug("(_goto_config_keys): Jumped to key '%s'.", key)
end

-- Build a TS query to search for a key
local function build_query(key)
  return string.format(
    [[
    (array_element_initializer
        (string (string_content) @key_node (#eq? @key_node "%s"))
        (_) @value_node
    )
  ]],
    key
  )
end

-- Search for a key in a given root
local function find_key_in_node(bufnr, root, key)
  local ts = require("vim.treesitter")
  local ok, query = pcall(ts.query.parse, "php", build_query(key))
  if not ok or not query then
    log.error("(_goto_config_keys): Failed to parse query for key '%s'. Error: %s", key, tostring(query))
    return nil, nil
  end

  for _, match, _ in query:iter_matches(root, bufnr) do
    local key_node, value_node
    for id, nodes in pairs(match) do
      local name = query.captures[id]
      if name == "key_node" then
        key_node = nodes[1]
      end
      if name == "value_node" then
        value_node = nodes[1]
      end
    end
    if key_node then
      return key_node, value_node
    end
  end

  return nil, nil
end

-- Recursive function that navigates through the keys
local function navigate_keys(bufnr, root, keys)
  local current_key = table.remove(keys, 1)
  if not current_key then
    return false
  end

  local key_node, value_node = find_key_in_node(bufnr, root, current_key)
  if not key_node then
    log.debug("(_goto_config_keys): Key '%s' not found.", current_key)
    return false
  end

  if #keys == 0 then
    jump_to_node(key_node, current_key)
    return true
  end

  if value_node and value_node:type() == "array_creation_expression" then
    log.debug("(_goto_config_keys): Descending into array for key '%s'.", current_key)
    return navigate_keys(bufnr, value_node, keys)
  else
    log.debug("(_goto_config_keys): Value for '%s' is not an array, cannot descend.", current_key)
    jump_to_node(key_node, current_key)
    return true
  end
end

--- Internal function to navigate to nested keys within a PHP config file using Tree-sitter.
--- @param bufnr integer Buffer number of the opened config file.
--- @param keys table List of remaining key parts (e.g., {"whatsapp", "token"}).
--- @return boolean True if navigation was successful, false otherwise.
function M._goto_config_keys(bufnr, keys)
  if type(keys) ~= "table" or vim.tbl_isempty(keys) then
    log.debug("(_goto_config_keys): No keys provided.")
    return false
  end

  local ok, ts = pcall(require, "vim.treesitter")
  if not ok then
    log.warn("(_goto_config_keys): Treesitter not available.")
    return false
  end

  local parser = ts.get_parser(bufnr, "php")
  if not parser then
    log.warn("(_goto_config_keys): Could not get PHP parser for buffer %d.", bufnr)
    return false
  end

  local tree = parser:parse()[1]
  if not tree then
    log.warn("(_goto_config_keys): Could not parse buffer %d.", bufnr)
    return false
  end

  return navigate_keys(bufnr, tree:root(), vim.deepcopy(keys))
end

return M
