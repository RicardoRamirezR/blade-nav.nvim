local M = {}

local function get_psr4_mappings()
  local file = io.open("composer.json", "r")

  if not file then
    vim.notify("Could not open composer.json")
    return
  end

  local content = file:read("*a")
  file:close()

  local decoded = vim.fn.json_decode(content)
  if not decoded or not decoded.autoload or not decoded.autoload["psr-4"] then
    return {}
  end

  return decoded.autoload["psr-4"]
end

local function get_routes(route_name)
  local handle = io.popen("php artisan route:list --name=" .. route_name .. " --json --columns=name,action")
  if not handle then
    return {}
  end

  local result = handle:read("*a")
  handle:close()

  local routes = vim.fn.json_decode(result)
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

local function extract_route_name()
  local line = vim.fn.getline(".")
  local cursor_col = vim.fn.col(".")
  local pattern = "route%s*%(%s*['\"]([%w%.%-]+)['\"]"

  local start_idx, end_idx, route_name = line:find(pattern)

  if start_idx and end_idx then
    end_idx = end_idx + 1
    if cursor_col >= start_idx and cursor_col <= end_idx then
      return route_name
    end
  end

  return nil
end

local function get_root_and_lang()
  local parsers = require("nvim-treesitter.parsers")
  local parser = parsers.get_parser()

  if not parser then
    vim.notify("Failed to parse the tree.", vim.lsp.log_levels.ERROR)
    return nil, nil
  end

  local tree = parser:parse()[1]

  if not tree then
    vim.notify("Failed to parse the tree.", vim.lsp.log_levels.ERROR)
    return nil, nil
  end

  local root = tree:root()
  local lang = parser:lang()

  if lang ~= "php" then
    vim.notify("Info: works only on PHP.")
    return nil, nil
  end

  return root, lang
end

local function goto_method(method_name)
  local root, lang = get_root_and_lang()
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

M.gf = function()
  local route_name = extract_route_name()

  if not route_name then
    vim.notify("Route definition not found")
    return
  end

  local route_map = get_routes(route_name)
  local psr4_mappings = get_psr4_mappings()

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
