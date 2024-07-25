local utils = require("blade-nav.utils")

local M = {}

local function get_routes(route_name)
  local result = M.execute_command_silent({
    "php",
    "artisan",
    "route:list",
    "--name=",
    route_name,
    "--json",
    "--columns=name,action",
  })

  if result:find("Your application doesn't have any routes matching the given criteria") then
    vim.notify("No matching routes found for the given criteria")
    return {}
  end

  local ok, routes = pcall(vim.fn.json_decode, result)
  if not ok then
    vim.notify("Error parsing JSON output")
    return {}
  end

  local route_map = {}

  for _, route in ipairs(routes) do
    if route.name and route.action then
      local controller_method = vim.split(route.action, "@")
      route_map[route.name] = {
        controller = controller_method[1],
        method = controller_method[2],
      }
    end
  end

  return route_map
end

local function resolve_controller_path(controller, psr4_mappings)
  -- If PSR-4 mappings are empty, assume default namespace
  if not psr4_mappings or vim.tbl_isempty(psr4_mappings) then
    return controller:sub(1, 1):lower() .. controller:sub(2):gsub("\\", "/") .. ".php"
  end

  -- Check PSR-4 mappings
  for namespace, path in pairs(psr4_mappings) do
    if controller:sub(1, #namespace) == namespace then
      local relative_path = controller:sub(#namespace + 1):gsub("\\", "/") .. ".php"
      return path .. "/" .. relative_path
    end
  end

  return nil
end

local function goto_method(method_name)
  local root, lang = utils.get_root_and_lang()
  if not root then
    return
  end

  if not method_name then
    method_name = "__invoke"
  end

  local ts = vim.treesitter
  local query_template = [[
    (method_declaration
      (visibility_modifier) @vis (#eq? @vis "public")
        name: (name) @name (#eq? @name "%s")
    ) @method
  ]]
  local query_string = string.format(query_template, method_name)
  local query = ts.query.parse(lang, query_string)

  for _, matches, _ in query:iter_matches(root, 0) do
    for _, node in pairs(matches) do
      local start_row, start_col, _ = node:start()
      vim.api.nvim_win_set_cursor(0, { start_row + 1, start_col })
      return
    end
  end
end

M.gf = function(route_name)
  if not route_name then
    return
  end

  local route_map = get_routes(route_name)
  local psr4_mappings = utils.get_psr4_mappings()

  if not route_map[route_name] then
    vim.notify("Route definition not found")
    return
  end

  local controller = route_map[route_name].controller
  local method = route_map[route_name].method
  local controller_path = resolve_controller_path(controller, psr4_mappings)

  if controller_path then
    vim.cmd("edit " .. controller_path)
    goto_method(method)
    return true
  end
end

return M
