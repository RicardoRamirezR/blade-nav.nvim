-- lua/blade-nav/targets/route.lua
-- Target handler for Laravel route references like route('home'), to_route('user.profile').

local fs = require("blade-nav.utils.fs")
local laravel_utils = require("blade-nav.utils.laravel")
local log = require("blade-nav.utils.log")
local ts_utils = require("blade-nav.utils.treesitter")

local M = {}

function M.get_capabilities()
  return {
    targets = { "route", "to_route" },
    filetypes = { "*" },
  }
end

--- Resolves the controller path based on PSR-4 mappings.
--- @param controller string The full controller class name (e.g., App\Http\Controllers\UserController).
--- @param psr4_mappings table The PSR-4 mappings from composer.json.
--- @return string|nil The resolved file path or nil.
local function resolve_controller_path(controller, psr4_mappings)
  if not psr4_mappings or vim.tbl_isempty(psr4_mappings) then
    log.debug("(resolve_controller_path): No PSR-4 mappings, using default conversion.")
    return controller:sub(1, 1):lower() .. controller:sub(2):gsub("\\", "/") .. ".php"
  end

  for namespace, path in pairs(psr4_mappings) do
    if controller:sub(1, #namespace) == namespace then
      local relative_path = controller:sub(#namespace + 1):gsub("\\", "/") .. ".php"
      local resolved_path = path .. "/" .. relative_path
      log.debug("(resolve_controller_path): Matched namespace '%s'. Resolved path: %s", namespace, resolved_path)
      return resolved_path
    end
  end

  log.debug("(resolve_controller_path): Controller '%s' not matched by any PSR-4 mapping.", controller)
  return nil
end

--- Navigates to a specific method within the current buffer using Tree-sitter.
--- @param method_name string The name of the method to find.
local function goto_method(method_name)
  local root, lang = ts_utils.gets_root_and_lang()
  if not root or not lang then
    log.warn("(goto_method): Could not get TS root/lang for current buffer.")
    return
  end

  if not method_name or method_name == "" then
    method_name = "__invoke"
    log.debug("No method specified, defaulting to '__invoke'.")
  end

  log.debug("Searching for method '%s'.", method_name)

  local query_template = [[
        (method_declaration
          (visibility_modifier) @vis (#eq? @vis "public")
          name: (name) @name (#eq? @name "%s")
        ) @method
    ]]
  local query_string = string.format(query_template, method_name)

  local ts_status, ts = pcall(require, "vim.treesitter")
  if not ts_status or not ts then
    log.warn("vim.treesitter not available.")
    return
  end

  local query_status, query = pcall(ts.query.parse, lang, query_string)
  if not query_status or not query then
    log.error("Failed to parse TS query for method '%s'. Error: %s", method_name, tostring(query))
    return
  end

  for _, matches, _ in query:iter_matches(root, 0) do
    for id, nodes in pairs(matches) do
      local capture_name = query.captures[id]
      if capture_name == "name" then
        for _, node in ipairs(nodes) do
          if node then
            local start_row, start_col, _, _ = node:range()
            vim.api.nvim_win_set_cursor(0, { start_row + 1, start_col })
            vim.cmd("normal! zz")
            log.info("Navigated to method '%s'.", method_name)
            return
          end
        end
      end
    end
  end

  log.info("Method '%s' not found in current buffer.", method_name)
end

--- Gets target information if the cursor is on a route reference.
--- Supports route(), to_route().
--- @param context BladeNavContext Context created by context.lua
--- @return BladeNavTargetInfo|nil { type = "route", name = "route.name" } or nil
function M.get_target(context)
  if context.target and not vim.tbl_contains(M.get_capabilities().targets, context.target) then
    return nil
  end

  if context.first_arg and context.target then
    return {
      type = "route",
      name = context.first_arg,
    }
  end

  local line = context.line

  log.debug("Processing line for route reference: %s", line)

  local found_keys_route = ts_utils.extract_keys_from_code(line, "route")
  log.debug("Found keys for 'route': %s", vim.inspect(found_keys_route))

  if #found_keys_route >= 1 then
    local key_info = found_keys_route[1]
    return {
      type = "route",
      name = key_info,
    }
  end

  local found_keys_to_route = ts_utils.extract_keys_from_code(line, "to_route")
  log.debug("Found keys for 'to_route': %s", vim.inspect(found_keys_to_route))

  if #found_keys_to_route >= 1 then
    local key_info = found_keys_to_route[1]
    return {
      type = "route",
      name = key_info,
    }
  end

  log.debug("Cursor position did not match any found route key range.")
  return nil
end

--- Resolves and opens/navigates to the route definition or associated controller.
--- @param target_info BladeNavTargetInfo The target info returned by get_target.
--- @return boolean True if successfully opened or action taken.
function M.resolve(target_info)
  if not target_info or target_info.type ~= "route" or not target_info.name then
    log.warn("route resolve called with invalid target_info: %s", vim.inspect(target_info))
    return false
  end

  local route_name = target_info.name
  log.debug("Resolving route: %s", route_name)

  local route_map = laravel_utils.get_route_list(route_name)
  if not route_map or not route_map[route_name] then
    log.warn("Route definition for '%s' not found.", route_name)
    return false
  end

  local route_definition = route_map[route_name]
  local controller = route_definition.controller
  local method = route_definition.method

  if not controller or controller == "" then
    log.warn("No controller defined for route '%s'.", route_name)
    return false
  end

  log.debug("Found definition for '%s': controller=%s, method=%s", route_name, controller, method)

  local psr4_mappings = laravel_utils.get_psr4_mappings()
  if not psr4_mappings then
    log.error("Failed to get PSR-4 mappings.")
    return false
  end

  local controller_path = resolve_controller_path(controller, psr4_mappings)
  if not controller_path or not fs.path_exists(controller_path) or fs.is_dir(controller_path) then
    log.warn("Controller file for '%s' not found or invalid: %s", controller, controller_path or "nil")
    return false
  end

  local escaped_path = vim.fn.fnameescape(controller_path)
  vim.cmd("edit " .. escaped_path)
  log.info("Opened controller file: %s", controller_path)

  goto_method(method)
  return true
end

return M
