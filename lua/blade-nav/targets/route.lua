-- lua/blade-nav/targets/route.lua
-- Target handler for Laravel route references like route('home'), to_route('user.profile').

local log = require("blade-nav.utils.log")
local ts_utils = require("blade-nav.utils.treesitter")   -- Import the TS utility for routes
local laravel_utils = require("blade-nav.utils.laravel") -- Import Laravel utilities
local fs = require("blade-nav.utils.fs")                 -- For file operations

local M = {}

--- Resolves the controller path based on PSR-4 mappings.
--- Mirrors logic from working-version.txt's gf_routes.lua.
--- @param controller string The full controller class name (e.g., App\Http\Controllers\UserController).
--- @param psr4_mappings table The PSR-4 mappings from composer.json.
--- @return string|nil The resolved file path or nil.
local function resolve_controller_path(controller, psr4_mappings)
  -- If PSR-4 mappings are empty, assume default namespace structure
  if not psr4_mappings or vim.tbl_isempty(psr4_mappings) then
    -- Convert App\Http\Controllers\Controller to app/http/controllers/controller.php
    -- This is a fallback, might not be perfect for all cases.
    log.debug("BladeNav Route (resolve_controller_path): No PSR-4 mappings, using default conversion.")
    return controller:sub(1, 1):lower() .. controller:sub(2):gsub("\\", "/") .. ".php"
  end

  -- Check PSR-4 mappings
  for namespace, path in pairs(psr4_mappings) do
    if controller:sub(1, #namespace) == namespace then
      local relative_path = controller:sub(#namespace + 1):gsub("\\", "/") .. ".php"
      local resolved_path = path .. "/" .. relative_path
      log.debug(
        "BladeNav Route (resolve_controller_path): Matched namespace '%s'. Resolved path: %s",
        namespace,
        resolved_path
      )
      return resolved_path
    end
  end

  log.debug("BladeNav Route (resolve_controller_path): Controller '%s' not matched by any PSR-4 mapping.", controller)
  return nil
end

--- Navigates to a specific method within the current buffer using Tree-sitter.
--- @param method_name string The name of the method to find.
local function goto_method(method_name)
  -- Get Tree-sitter parser and root for the *current* buffer (where controller is opened)
  local root, lang = ts_utils.gets_root_and_lang()
  if not root or not lang then
    log.warn("BladeNav Route (goto_method): Could not get TS root/lang for current buffer.")
    return
  end

  -- Default to __invoke if no method specified (common for invokable controllers)
  if not method_name or method_name == "" then
    method_name = "__invoke"
    log.debug("BladeNav Route (goto_method): No method specified, defaulting to '__invoke'.")
  end

  log.debug("BladeNav Route (goto_method): Searching for method '%s'.", method_name)

  -- Create Tree-sitter query to find the public method declaration
  local query_template = [[
        (method_declaration
          (visibility_modifier) @vis (#eq? @vis "public")
          name: (name) @name (#eq? @name "%s")
        ) @method
    ]]
  local query_string = string.format(query_template, method_name)

  local ts_status, ts = pcall(require, "vim.treesitter")
  if not ts_status or not ts then
    log.warn("BladeNav Route (goto_method): vim.treesitter not available.")
    return
  end

  local query_status, query = pcall(ts.query.parse, lang, query_string)
  if not query_status or not query then
    log.error(
      "BladeNav Route (goto_method): Failed to parse TS query for method '%s'. Error: %s",
      method_name,
      tostring(query)
    )
    return
  end

  -- Iterate matches to find the method node
  for _, matches, _ in query:iter_matches(root, 0) do -- bufnr 0 for current buffer
    for id, nodes in pairs(matches) do
      local capture_name = query.captures[id]
      if capture_name == "name" then -- Focus on the name capture
        for _, node in ipairs(nodes) do
          if node then
            local start_row, start_col, _, _ = node:range()
            -- Set cursor (1-based row, 0-based col)
            vim.api.nvim_win_set_cursor(0, { start_row + 1, start_col })
            vim.cmd("normal! zz") -- Center the line
            log.info("BladeNav Route (goto_method): Navigated to method '%s'.", method_name)
            return                -- Success, exit function
          end
        end
      end
    end
  end

  log.info("BladeNav Route (goto_method): Method '%s' not found in current buffer.", method_name)
end

--- Gets target information if the cursor is on a route reference.
--- Uses the line-based parsing utility function and specific pattern matching.
--- Supports route(), to_route().
--- @param context BladeNavContext Context created by context.lua
--- @return BladeNavTargetInfo|nil { type = "route", name = "route.name" } or nil
function M.get_target(context)
  local line = context.line
  local col_1 = context.cursor_col_1 -- 1-based column
  local filetype = context.filetype

  if not line or col_1 <= 0 then
    log.debug("Invalid line or cursor position.")
    return nil
  end

  log.debug("Processing line for route reference: %s", line)

  -- --- Find Route Names using Utility Functions ---
  -- These calls use the (assumed) ts_utils.extract_keys_from_code which handles
  -- route() and to_route().

  -- 1. Find potential 'route(...)' names
  local found_keys_route = ts_utils.extract_keys_from_code(line, "route")
  log.debug("Found keys for 'route': %s", vim.inspect(found_keys_route))

  if #found_keys_route == 1 then
    local key_info = found_keys_route[1]
    return {
      type = "route",
      name = key_info,
    }
  end

  -- 2. Find potential 'to_route(...)' names
  local found_keys_to_route = ts_utils.extract_keys_from_code(line, "to_route")
  log.debug("Found keys for 'to_route': %s", vim.inspect(found_keys_to_route))

  if #found_keys_to_route == 1 then
    local key_info = found_keys_to_route[1]
    return {
      type = "to_route",
      name = key_info,
    }
  end

  -- Note: We are explicitly NOT including 'redirect' as requested.

  -- --- Aggregate Route Names with Accurate Position Matching ---
  -- Combine all found keys and use specific patterns to find their exact
  -- locations on the line for accurate cursor position checking.

  local all_found_key_infos = {} -- Stores { key = "...", type = "route", start_pos = ..., end_pos = ... }

  -- Helper function to process found keys with specific search patterns
  local function process_and_add_keys(keys_list, target_type, search_patterns)
    if keys_list and type(keys_list) == "table" then
      for _, key in ipairs(keys_list) do
        for _, pattern_info in ipairs(search_patterns) do
          local start_pos, end_pos = 0, 0
          -- Escape special regex characters in the key name
          local escaped_key = key:gsub("([^%w%.%-_])", "%%%1") -- Escape common route name chars if needed
          log.debug("Escaped key for pattern matching: '%s' -> '%s'", key, escaped_key)

          -- Construct the full search pattern by substituting the escaped key
          -- The pattern_info.pattern uses "{{{KEY}}}" as a placeholder.
          local full_pattern = pattern_info.pattern:gsub("{{{KEY}}}", escaped_key)
          log.debug("Constructed full pattern for key '%s': '%s'", key, full_pattern)

          repeat
            start_pos, end_pos = line:find(full_pattern, end_pos + 1)
            log.debug("line:", line, "full_pattern:", full_pattern, "start_pos:", start_pos, "end_pos:", end_pos)
            if start_pos and end_pos then
              table.insert(all_found_key_infos, {
                key = key,
                type = target_type, -- Always "route" for this handler
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
  local route_search_patterns = {
    { pattern = "route%s*%(%s*['\"]{{{KEY}}}['\"]",    source = "route" },
    { pattern = "to_route%s*%(%s*['\"]{{{KEY}}}['\"]", source = "to_route" },
    -- Add pattern for array forms if needed, e.g., route(['name' => ...])
  }

  -- Process each set of found keys with their respective accurate patterns
  -- Both route and to_route result in the same target type: "route"
  process_and_add_keys(found_keys_route, "route", route_search_patterns)
  process_and_add_keys(found_keys_to_route, "route", { route_search_patterns[2] }) -- Only to_route pattern

  -- Debug: Log all aggregated key infos for inspection
  log.debug("Final aggregated key infos for cursor check: %s", vim.inspect(all_found_key_infos))

  if #all_found_key_infos == 0 then
    log.debug("No route keys found on line by utility.")
    return nil
  end

  -- --- Cursor Position Check ---
  -- Iterate through the aggregated list and check if the cursor is within
  -- the range (start_pos to end_pos) of any found key occurrence.
  for _, key_info in ipairs(all_found_key_infos) do
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
      return {
        type = key_info.type, -- "route"
        name = key_info.key,  -- The extracted route name
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

  log.debug("Cursor position did not match any found route key range.")
  return nil
end

--- Resolves and opens/navigates to the route definition or associated controller.
--- Mirrors logic from working-version.txt's gf_routes.lua.
--- @param target_info BladeNavTargetInfo The target info returned by get_target.
--- @return boolean True if successfully opened or action taken.
function M.resolve(target_info)
  if not target_info or target_info.type ~= "route" or not target_info.name then
    log.warn("route resolve called with invalid target_info: %s", vim.inspect(target_info))
    return false
  end

  local route_name = target_info.name
  log.debug("Resolving route: %s", route_name)

  -- --- Logic to resolve the route ---
  -- This replicates or adapts logic from working-version.txt's gf_routes.lua

  -- 1. Get the route definition map (potentially cached)
  local route_map = laravel_utils.get_route_list(route_name)
  if not route_map or not route_map[route_name] then
    log.warn("BladeNav Route: Route definition for '%s' not found.", route_name)
    return false
  end

  local route_definition = route_map[route_name]
  local controller = route_definition.controller
  local method = route_definition.method

  if not controller or controller == "" then
    log.warn("BladeNav Route: No controller defined for route '%s'.", route_name)
    return false -- Cannot resolve without a controller
  end

  log.debug("BladeNav Route: Found definition for '%s': controller=%s, method=%s", route_name, controller, method)

  -- 2. Resolve the controller to a file path using PSR-4 mappings
  local psr4_mappings = laravel_utils.get_psr4_mappings() -- Assuming this exists
  if not psr4_mappings then
    log.error("BladeNav Route: Failed to get PSR-4 mappings.")
    return false
  end

  local controller_path = resolve_controller_path(controller, psr4_mappings) -- Use the local function
  if not controller_path or not fs.path_exists(controller_path) or fs.is_dir(controller_path) then
    log.warn("BladeNav Route: Controller file for '%s' not found or invalid: %s", controller, controller_path or "nil")
    return false -- Cannot resolve if controller file path is bad
  end

  -- 3. Open the controller file
  -- Use fnameescape for safety
  local escaped_path = vim.fn.fnameescape(controller_path)
  vim.cmd("edit " .. escaped_path)
  local new_buf = vim.api.nvim_get_current_buf() -- Get buffer after opening
  log.info("BladeNav Route: Opened controller file: %s", controller_path)

  -- 4. Navigate to the specific method within the controller file (Optional, complex)
  -- This uses the local goto_method function.
  if method and method ~= "" then
    -- Call goto_method. It operates on the current buffer (the newly opened controller file).
    goto_method(method)
    -- goto_method logs its own success/failure, no need to return its result here.
    -- The primary action (opening the file) was successful.
    log.info("BladeNav Route: Attempted to navigate to method '%s' in '%s'.", method, controller_path)
    return true
  else
    -- No method specified in route definition, just opening the file was the goal.
    log.info(
      "BladeNav Route: Located and opened controller file '%s'. No method specified in route definition.",
      controller_path
    )
    return true
  end

  -- Should not reach here in normal flow
  return false
end

return M
