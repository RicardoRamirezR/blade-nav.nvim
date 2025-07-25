-- lua/blade-nav/targets/config.lua
-- Target handler for Laravel config references like config('app.name'), Config::get('database.default').

local log = require("blade-nav.utils.log")
local ts_utils = require("blade-nav.utils.treesitter") -- Import the updated TS utility
local fs = require("blade-nav.utils.fs")               -- For file operations in resolve

local M = {}

--- Gets target information if the cursor is on a config reference.
--- Uses the line-based parsing utility function.
--- @param context BladeNavContext Context created by context.lua
--- @return BladeNavTargetInfo|nil { type = "config", name = "key.name" } or { type = "env", name = "VAR_NAME" } or nil
--- Gets target information if the cursor is on a config reference.
--- Uses the line-based parsing utility function and specific pattern matching for cursor position.
--- Supports config(), env(), Config::get(), Config::set().
--- @param context BladeNavContext Context created by context.lua
--- @return BladeNavTargetInfo|nil { type = "config", name = "key.name" } or { type = "env", name = "VAR_NAME" } or nil
function M.get_target(context)
  local line = context.line
  local col_1 = context.cursor_col_1 -- 1-based column
  local filetype = context.filetype

  if not line or col_1 <= 0 then
    log.debug("Invalid line or cursor position.")
    return nil
  end

  log.debug("Processing line for config/env reference: %s", line)

  -- --- Find Keys using Utility Functions ---
  -- These calls use the updated ts_utils.extract_keys_from_code.
  -- When called with "config", it finds keys from config(), Config::get(), Config::set().
  -- When called with "env", it finds keys from env().

  -- 1. Find potential 'config(...)', 'Config::get(...)', 'Config::set(...)' keys
  local found_keys_config = ts_utils.extract_keys_from_code(line, "config")
  log.debug("Found keys for 'config/get/set': %s", vim.inspect(found_keys_config))

  -- 2. Find potential 'env(...)' keys
  local found_keys_env = ts_utils.extract_keys_from_code(line, "env")
  log.debug("Found keys for 'env': %s", vim.inspect(found_keys_env))

  -- --- Aggregate Keys with Accurate Position Matching ---
  -- Combine all found keys and use specific patterns to find their exact
  -- locations on the line for accurate cursor position checking.

  local all_found_key_infos = {} -- Stores { key = "...", type = "...", start_pos = ..., end_pos = ... }

  -- Helper function to process found keys with specific search patterns
  -- Ensures accurate start/end positions for cursor matching.
  local function process_and_add_keys(keys_list, target_type, search_patterns)
    if keys_list and type(keys_list) == "table" then
      for _, key in ipairs(keys_list) do
        for _, pattern_info in ipairs(search_patterns) do
          local start_pos, end_pos = 0, 0
          -- Escape special regex characters in the key name
          local escaped_key = key:gsub("([^%w%.])", "%%%1") -- Escape . \ + * ? [ ^ $ ( ) % -
          log.debug("Escaped key for pattern matching: '%s' -> '%s'", key, escaped_key)

          -- Construct the full search pattern by substituting the escaped key
          -- into the pattern template.
          -- The pattern_info.pattern uses "{{{KEY}}}" as a placeholder.
          -- Example pattern: "config%s*%(%s*['\"]{{{KEY}}}['\"]"
          local full_pattern = pattern_info.pattern:gsub("{{{KEY}}}", escaped_key)
          log.debug("Constructed full pattern for key '%s': '%s'", key, full_pattern)

          repeat
            -- Use the constructed full_pattern for string.find
            start_pos, end_pos = line:find(full_pattern, end_pos + 1)
            if start_pos and end_pos then
              table.insert(all_found_key_infos, {
                key = key,
                type = target_type,
                start_pos = start_pos,
                end_pos = end_pos,
                pattern_source = pattern_info.source or "unknown",
              })
              log.debug(
                "Added key info: key='%s', type='%s', range=[%d, %d], source='%s'",
                key,
                target_type,
                start_pos,
                end_pos,
                pattern_info.source or "unknown"
              )
            else
              -- Only log if we were searching (start_pos was 0 initially)
              if end_pos == 0 then
                log.debug("Pattern '%s' not found for key '%s' on line.", full_pattern, key)
              end
            end
          until not start_pos
        end
      end
    end
  end

  -- Define search patterns using a unique placeholder "{{{KEY}}}"
  -- These patterns are designed for string.find and use % for regex escaping.
  local config_search_patterns = {
    { pattern = "config%s*%(%s*['\"]{{{KEY}}}['\"]",      source = "config" },
    { pattern = "Config::get%s*%(%s*['\"]{{{KEY}}}['\"]", source = "Config::get" },
    { pattern = "Config::set%s*%(%s*['\"]{{{KEY}}}['\"]", source = "Config::set" },
  }
  local env_search_patterns = {
    { pattern = "env%s*%(%s*['\"]{{{KEY}}}['\"]", source = "env" },
  }

  -- Process each set of found keys with their respective accurate patterns
  process_and_add_keys(found_keys_config, "config", config_search_patterns)
  process_and_add_keys(found_keys_env, "env", env_search_patterns)

  -- Debug: Log all aggregated key infos for inspection
  log.debug("Final aggregated key infos for cursor check: %s", vim.inspect(all_found_key_infos))

  if #all_found_key_infos == 0 then
    log.debug("No config/env keys found on line by utility.")
    return nil
  end

  -- --- Cursor Position Check ---
  -- Iterate through the aggregated list and check if the cursor is within
  -- the range (start_pos to end_pos) of any found key occurrence.
  for _, key_info in ipairs(all_found_key_infos) do
    -- Check if the 1-based cursor column is within the inclusive range of the match
    if col_1 >= key_info.start_pos and col_1 <= key_info.end_pos then
      log.debug(
        "Cursor (col %d) is within range for key '%s' (type: %s, range: [%d, %d], source: %s).",
        col_1,
        key_info.key,
        key_info.type,
        key_info.start_pos,
        key_info.end_pos,
        key_info.pattern_source
      )
      -- Return the standard target information structure
      return {
        type = key_info.type, -- "config" or "env"
        name = key_info.key,  -- The extracted config key or env var name
        -- pattern_source = key_info.pattern_source -- Optional: if resolve needs it
      }
    else
      log.debug(
        "Cursor (col %d) NOT within range for key '%s' (type: %s, range: [%d, %d], source: %s).",
        col_1,
        key_info.key,
        key_info.type,
        key_info.start_pos,
        key_info.end_pos,
        key_info.pattern_source
      )
    end
  end

  log.debug("Cursor position did not match any found config/env key range.")
  return nil
end

--- Resolves and opens/navigates to the config definition or .env file, including in-file navigation.
--- @param target_info BladeNavTargetInfo The target info returned by get_target.
--- @return boolean True if successfully opened or action taken.
function M.resolve(target_info)
  if not target_info or (target_info.type ~= "config" and target_info.type ~= "env") or not target_info.name then
    log.warn("config resolve called with invalid target_info: %s", vim.inspect(target_info))
    return false
  end

  local target_type = target_info.type -- "config" or "env"
  local key_name = target_info.name    -- e.g., "app.name", "APP_KEY"

  if target_type == "env" then
    return M._resolve_env(key_name)
  elseif target_type == "config" then
    return M._resolve_config(key_name)
  else
    log.warn("BladeNav Config: Unknown target type '%s'.", target_type)
    return false
  end
end

--- Internal function to resolve and navigate within an .env file.
--- @param key_name string The environment variable name (e.g., "APP_KEY").
--- @return boolean True if successfully opened/navigated.
function M._resolve_env(key_name)
  local env_file_path = "./.env"
  if fs.path_exists(env_file_path) and not fs.is_dir(env_file_path) then
    -- Edit the file. This switches the current buffer/window context.
    vim.cmd("edit " .. vim.fn.fnameescape(env_file_path))
    -- The current buffer is now the .env file

    -- --- Use Tree-sitter to find the key ---
    local ts_status, ts = pcall(require, "vim.treesitter")
    if not ts_status or not ts then
      log.warn("BladeNav Config (env): vim.treesitter not available for .env navigation.")
      return true -- File opened
    end

    -- Get parser for the current buffer (0) using 'bash' language
    local parser_ok, parser = pcall(ts.get_parser, 0, "bash")
    if not parser_ok or not parser then
      log.warn("BladeNav Config (env): Could not get 'bash' parser for .env file buffer.")
      return true -- File opened
    end

    -- Parse the buffer
    local tree_ok, tree = pcall(function()
      return parser:parse()[1]
    end)
    if not tree_ok or not tree then
      log.warn("BladeNav Config (env): Could not parse .env file buffer with 'bash' parser.")
      return true -- File opened
    end
    local root = tree:root()

    -- Create the Tree-sitter query to find the variable_assignment with the specific name
    local query_string = string.format(
      [[
            (variable_assignment
              name: (variable_name) @name
              (#eq? @name "%s"))
            ]],
      key_name -- Assumes key_name doesn't contain characters needing escaping for the query
    )

    local query_ok, query = pcall(ts.query.parse, "bash", query_string)
    if not query_ok or not query then
      log.error("BladeNav Config (env): Failed to parse TS query for key '%s'. Error: %s", key_name, tostring(query))
      return true -- File opened, but navigation failed
    end

    -- Iterate captures to find the matching node
    local iter_ok, iter_result_or_err = pcall(function()
      for id, node, _ in query:iter_captures(root, 0) do -- bufnr 0 for current buffer
        local capture_name = query.captures[id]
        if capture_name == "name" then
          -- Found the variable_name node matching the key
          local start_row, start_col, _, _ = node:range()
          -- Set cursor (1-based row, 0-based col is common for API, TS is 0-based)
          vim.api.nvim_win_set_cursor(0, { start_row + 1, start_col })
          vim.cmd("normal! zz") -- Center the line
          log.info("BladeNav Config (env): Navigated to key '%s' using Tree-sitter.", key_name)
          -- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
          -- CRITICAL CHANGE: Return true immediately upon successful navigation
          -- This prevents falling through to the "not found" log/print statements.
          return true -- Signal success and exit the pcall/function
          -- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
        end
      end
      -- If loop completes without finding the key, implicitly return nil/false-y
      return false -- Signal failure to find key
    end)

    if not iter_ok then
      log.error(
        "BladeNav Config (env): Error during TS query iteration for key '%s'. Error: %s",
        key_name,
        tostring(iter_result_or_err)
      )
      return true -- File opened, but navigation failed
    else
      -- The pcall was successful. Check the result returned from inside the pcall.
      if iter_result_or_err == true then
        -- Navigation was successful (returned true from inside pcall)
        -- The log message "Navigated to key..." was already printed inside the loop.
        return true
      else
        -- Iteration completed, but key was not found (returned false or nil)
        log.info("BladeNav Config (env): Key '%s' not found in .env file via Tree-sitter query.", key_name)
        return true -- File was opened, even if key wasn't found
      end
    end
  else
    log.warn("BladeNav Config (env): .env file not found at '%s'.", env_file_path)
    return false
  end
end

--- Internal function to resolve and navigate within a Laravel config file.
--- @param full_config_key string The full config key (e.g., "app.debug", "services.whatsapp.token").
--- @return boolean True if successfully opened/navigated.
function M._resolve_config(full_config_key)
  log.debug("Resolving config key: %s", full_config_key)

  -- 1. Split the key to get the config file name and sub-keys
  local parts = vim.split(full_config_key, ".", { plain = true })
  if #parts == 0 then
    log.error("BladeNav Config: Invalid config key format '%s'.", full_config_key)
    return false
  end

  local config_file_name = table.remove(parts, 1) -- First part is the file name
  local config_file_path = "./config/" .. config_file_name .. ".php"

  -- 2. Check if the config file exists
  if not fs.path_exists(config_file_path) or fs.is_dir(config_file_path) then
    log.warn("BladeNav Config: Config file '%s' not found.", config_file_path)
    return false -- Cannot resolve if file doesn't exist
  end

  -- 3. Open the config file
  local current_buf = vim.api.nvim_get_current_buf()
  local current_win = vim.api.nvim_get_current_win()
  vim.cmd("edit " .. vim.fn.fnameescape(config_file_path))
  local new_buf = vim.api.nvim_get_current_buf()
  log.info("Opened config file: %s", config_file_path)

  -- 4. Navigate to the specific key within the file using Tree-sitter
  -- This replicates the logic from working-version.txt's gf_config.lua goto_keys/goto_subkey

  if #parts > 0 then
    -- There are sub-keys to navigate to (e.g., {"debug"} or {"whatsapp", "token"})
    local ok, result = pcall(M._goto_config_keys, new_buf, parts)
    if not ok then
      log.error("BladeNav Config: Error during in-file navigation: %s", tostring(result))
      -- Even if navigation failed, opening the file was successful.
      return true
    elseif result == true then
      log.info("BladeNav Config: Successfully navigated to key '%s' in '%s'.", full_config_key, config_file_path)
      return true
    else
      log.info(
        "BladeNav Config: Opened file '%s'. Navigation to key '%s' did not find a match.",
        config_file_path,
        full_config_key
      )
      return true -- File opened, navigation attempted
    end
  else
    -- Only the file name was specified (e.g., config('app'))
    log.info("BladeNav Config: Located and opened config file '%s'.", config_file_path)
    return true
  end
  -- Should not reach here
  return false
end

--- Internal function to navigate to nested keys within a PHP config file using Tree-sitter.
--- Inspired by working-version.txt's gf_config.lua goto_keys and goto_subkey.
--- @param bufnr integer Buffer number of the opened config file.
--- @param keys table List of remaining key parts (e.g., {"whatsapp", "token"}).
--- @return boolean True if navigation was successful, false otherwise.
function M._goto_config_keys(bufnr, keys)
  if not keys or type(keys) ~= "table" or #keys == 0 then
    log.debug("BladeNav Config (_goto_config_keys): No keys provided for navigation.")
    return false
  end

  -- Get Tree-sitter parser and root for the buffer
  local ts_status, ts = pcall(require, "vim.treesitter")
  if not ts_status then
    log.warn("BladeNav Config (_goto_config_keys): vim.treesitter not available.")
    return false
  end

  local parser = ts.get_parser(bufnr, "php")
  if not parser then
    log.warn("BladeNav Config (_goto_config_keys): Could not get PHP parser for buffer %d.", bufnr)
    return false
  end

  local tree = parser:parse()[1]
  if not tree then
    log.warn("BladeNav Config (_goto_config_keys): Could not parse buffer %d.", bufnr)
    return false
  end
  local root = tree:root()

  -- Start navigating from the root, looking for the first key
  local current_key = table.remove(keys, 1) -- Get the first key to find
  log.debug(
    "BladeNav Config (_goto_config_keys): Searching for key '%s'. Remaining keys: %s",
    current_key,
    vim.inspect(keys)
  )

  -- Corrected Query: Find array_element_initializer with a specific key string.
  -- This query matches the structure seen in new-version.txt's gf_config.lua.
  -- It looks for an array_element_initializer node that has:
  -- 1. A child node which is a string, whose content matches current_key (captured as @key_node).
  -- 2. A child node which is the value (captured as @value_node).
  local query_string = string.format(
    [[
        (array_element_initializer
            (string (string_content) @key_node (#eq? @key_node "%s")) ; Match the key string content
            (_) @value_node ; Capture the value node (could be array, string, number, etc.)
        )
    ]],
    current_key
  )

  local ok_query, query = pcall(ts.query.parse, "php", query_string)
  if not ok_query or not query then
    log.error(
      "BladeNav Config (_goto_config_keys): Failed to parse TS query for key '%s'. Error: %s",
      current_key,
      tostring(query)
    )
    return false
  end

  -- Iterate through matches for the current key
  for _, match, _ in query:iter_matches(root, bufnr) do
    -- In the returned `match` table, keys are capture IDs, values are tables of nodes.
    -- Find the nodes associated with our named captures @key_node and @value_node.
    local key_node = nil
    local value_node = nil

    for id, nodes in pairs(match) do
      local capture_name = query.captures[id]
      if capture_name == "key_node" and nodes and nodes[1] then
        key_node = nodes[1]   -- Get the first (and likely only) node for @key_node
      elseif capture_name == "value_node" and nodes and nodes[1] then
        value_node = nodes[1] -- Get the first (and likely only) node for @value_node
      end
    end

    if key_node then
      -- Found a matching key node
      log.debug("BladeNav Config (_goto_config_keys): Found key node for '%s'.", current_key)

      if #keys == 0 then
        -- This is the final key in the path. Move cursor to the key node.
        local start_row, start_col, _, _ = key_node:range()
        -- Set cursor (1-based row, 0-based col)
        vim.api.nvim_win_set_cursor(0, { start_row + 1, start_col })
        vim.cmd("normal! zz") -- Center the line
        log.debug("BladeNav Config (_goto_config_keys): Navigated to final key '%s'.", current_key)
        return true           -- Success
      else
        -- There are more keys to navigate. The value node should be an array.
        if value_node and value_node:type() == "array_creation_expression" then
          log.debug("BladeNav Config (_goto_config_keys): Value for '%s' is an array. Descending...", current_key)
          -- Descend into the value_node (which is the array) to search for the next key.
          -- We need to run the *same* query logic, but on the `value_node` as the new root.
          -- This is the recursive step.

          -- Re-call the navigation logic for the remaining keys within the value_node's subtree.
          -- We can achieve this by calling _goto_config_keys recursively,
          -- but we need to adjust how the query is run.
          -- A simpler way is to inline the logic slightly or pass the parent node context.
          -- Let's try a cleaner recursive call by adjusting the function
          -- to accept a node context. However, the current signature uses bufnr and keys.
          -- Let's adapt the query run for the subtree.

          -- Get the root of the value subtree (which is the array)
          local next_root = value_node
          -- Construct the query for the *next* key within this array subtree.
          local next_key = keys[1] -- Peek at the next key to find
          if next_key then
            local sub_query_string = string.format(
              [[
                            (array_element_initializer
                                (string (string_content) @key_node (#eq? @key_node "%s"))
                                (_) @value_node
                            )
                        ]],
              next_key
            )

            local ok_sub_query, sub_query = pcall(ts.query.parse, "php", sub_query_string)
            if ok_sub_query and sub_query then
              -- Iterate matches for the *next* key within the *current value* (array) node
              for _, sub_match, _ in sub_query:iter_matches(next_root, bufnr) do
                local sub_key_node = nil
                local sub_value_node = nil
                for id, nodes in pairs(sub_match) do
                  local capture_name = sub_query.captures[id]
                  if capture_name == "key_node" and nodes and nodes[1] then
                    sub_key_node = nodes[1]
                  elseif capture_name == "value_node" and nodes and nodes[1] then
                    sub_value_node = nodes[1]
                  end
                end

                if sub_key_node then
                  -- If this is the final key in the *original* list, navigate here.
                  if #keys == 1 then -- Because we peeked `next_key` and only removed one level
                    local s_row, s_col, _, _ = sub_key_node:range()
                    vim.api.nvim_win_set_cursor(0, { s_row + 1, s_col })
                    vim.cmd("normal! zz")
                    log.debug("BladeNav Config (_goto_config_keys): Navigated to nested final key '%s'.", next_key)
                    return true
                  else
                    -- More keys exist, check if sub_value is an array and recurse further.
                    -- This is getting complex to inline correctly.
                    -- For a robust solution, a cleaner recursive helper or iterative approach is better.
                    -- Let's acknowledge the need for recursion and handle one more level manually,
                    -- or simplify by navigating to the found intermediate key.

                    -- For now, if we can go one level deeper, do it.
                    -- If #keys > 1 after finding sub_key_node, and sub_value_node is an array,
                    -- we could theoretically recurse again.
                    -- Let's try a simplified recursive call within the value subtree.
                    -- Remove the key we just processed.
                    local keys_copy = vim.deepcopy(keys)
                    table.remove(keys_copy, 1) -- Remove the key we just found (next_key)
                    if #keys_copy > 0 and sub_value_node and sub_value_node:type() == "array_creation_expression" then
                      -- Recursive call: search for remaining keys within sub_value_node
                      -- We need to adapt _goto_config_keys or create a helper.
                      -- Let's assume a helper function `_search_in_node` exists conceptually.
                      -- For direct implementation, we can try pcall with adjusted parameters conceptually.
                      -- Easier: Just navigate to the deepest key we can find manually for 2-3 levels.
                      -- Or, implement a cleaner recursion.

                      -- Simplified manual handling for one more level:
                      local next_next_key = keys_copy[1]
                      if next_next_key then
                        local sub_sub_query_string = string.format(
                          [[
                                                    (array_element_initializer
                                                        (string (string_content) @key_node (#eq? @key_node "%s"))
                                                        (_) @value_node
                                                    )
                                                ]],
                          next_next_key
                        )
                        local ok_sub_sub_query, sub_sub_query = pcall(ts.query.parse, "php", sub_sub_query_string)
                        if ok_sub_sub_query and sub_sub_query then
                          for _, sub_sub_match, _ in sub_sub_query:iter_matches(sub_value_node, bufnr) do
                            local sub_sub_key_node = nil
                            for id, nodes in pairs(sub_sub_match) do
                              if sub_sub_query.captures[id] == "key_node" and nodes and nodes[1] then
                                sub_sub_key_node = nodes[1]
                                break
                              end
                            end
                            if sub_sub_key_node then
                              if #keys_copy == 1 then -- Final key in the 3rd level
                                local ss_row, ss_col, _, _ = sub_sub_key_node:range()
                                vim.api.nvim_win_set_cursor(0, { ss_row + 1, ss_col })
                                vim.cmd("normal! zz")
                                log.debug(
                                  "BladeNav Config (_goto_config_keys): Navigated to 3rd level final key '%s'.",
                                  next_next_key
                                )
                                return true
                              else
                                -- Navigate to the key even if deeper levels exist
                                local ss_row, ss_col, _, _ = sub_sub_key_node:range()
                                vim.api.nvim_win_set_cursor(0, { ss_row + 1, ss_col })
                                vim.cmd("normal! zz")
                                log.debug(
                                  "BladeNav Config (_goto_config_keys): Navigated to 3rd level key '%s'.",
                                  next_next_key
                                )
                                return true
                              end
                            end
                          end
                        end
                      else
                        -- Navigate to the 2nd level key if it's the final one or we can't go deeper easily
                        local s_row, s_col, _, _ = sub_key_node:range()
                        vim.api.nvim_win_set_cursor(0, { s_row + 1, s_col })
                        vim.cmd("normal! zz")
                        log.debug("BladeNav Config (_goto_config_keys): Navigated to 2nd level key '%s'.", next_key)
                        return true
                      end
                    else
                      -- Navigate to the 2nd level key if it's the final one or value isn't an array
                      local s_row, s_col, _, _ = sub_key_node:range()
                      vim.api.nvim_win_set_cursor(0, { s_row + 1, s_col })
                      vim.cmd("normal! zz")
                      log.debug("BladeNav Config (_goto_config_keys): Navigated to 2nd level key '%s'.", next_key)
                      return true
                    end
                  end
                end
              end
            end
          end
          -- If we reach here, the next key wasn't found in the current value array.
          log.debug(
            "BladeNav Config (_goto_config_keys): Key '%s' not found within the array value of '%s'.",
            keys[1] or "UNKNOWN",
            current_key
          )
          -- Move cursor to the key we found, even if we can't go deeper.
          local start_row, start_col, _, _ = key_node:range()
          vim.api.nvim_win_set_cursor(0, { start_row + 1, start_col })
          vim.cmd("normal! zz")
          return true -- Navigated to the key we could find
        else
          log.debug(
            "BladeNav Config (_goto_config_keys): Value for '%s' is not an array, cannot descend further.",
            current_key
          )
          -- Move cursor to the key we found.
          local start_row, start_col, _, _ = key_node:range()
          vim.api.nvim_win_set_cursor(0, { start_row + 1, start_col })
          vim.cmd("normal! zz")
          return true -- Navigated to the key we could find
        end
      end
    end
  end

  log.debug("BladeNav Config (_goto_config_keys): Key '%s' not found in the config file.", current_key)
  return false -- Key not found
end

return M
