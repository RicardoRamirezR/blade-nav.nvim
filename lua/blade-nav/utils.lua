local M = {}

--- Explode string to table by delimiter
--- @param delimiter string
--- @param text string
--- @return table
--- @usage local result = explode(".", {"foo", "bar", "baz"})
M.explode = function(delimiter, text)
  local result = {}
  local pattern = string.format("([^%s]+)", delimiter)

  for match in string.gmatch(text, pattern) do
    table.insert(result, match)
  end

  return result
end

--- Checks if command exists
--- @param name string
--- @return boolean
M.command_exists = function(name)
  return vim.fn.executable(name) == 1
end

--- Executes system command without noice
--- @param cmd table|string
--- @return string,boolean
M.execute_command_silent = function(cmd)
  if type(cmd) == "string" then
    cmd = M.explode(" ", cmd)
  end

  if not M.command_exists(cmd[1]) then
    print("Command not found: " .. cmd[1])
    return "", false
  end

  local ok, obj = pcall(function()
    return vim.system(cmd, { text = true }):wait()
  end)

  if not ok or obj.code ~= 0 then
    return "", false
  end

  return obj.stdout, true
end

--- find files using `fd` or `find`
--- @param path string
--- @param extension string
--- @param exclude_dirs? table
--- @return string
local function find_files(path, extension, exclude_dirs)
  local commands = {
    fd = { cmd = "fd --type=file --extension %s . %s %s", exclude = " -E %s" },
    find = { cmd = "find ./%s -type f -name *.%s %s", exclude = " -not -path './%s/*'" },
  }

  local function build_exclude_cmd(exclude_fmt, dirs)
    local exclude_cmd = ""
    for _, dir in ipairs(dirs or {}) do
      exclude_cmd = exclude_cmd .. " " .. string.format(exclude_fmt, dir)
    end
    return exclude_cmd
  end

  local tool = M.command_exists("fd") and "fd" or "find"
  local cmd_template = commands[tool].cmd
  local exclude_template = commands[tool].exclude

  local exclude_cmd = build_exclude_cmd(exclude_template, exclude_dirs)
  local command
  if tool == "fd" then
    command = string.format(cmd_template, extension, path, exclude_cmd)
  else
    command = string.format(cmd_template, path, extension, exclude_cmd)
  end

  return M.execute_command_silent(command)
end

--- Get all view files
--- @return table
M.get_blade_files = function()
  local result = find_files("resources/views", "blade.php")
  local files = {}

  for file in result:gmatch("[^\r\n]+") do
    local view_name = file:match("resources/views/(.*)%.blade%.php$")
    if view_name then
      view_name = view_name:gsub("/", ".")
      table.insert(files, view_name)
    end
  end

  return files
end

--- Determine prefix and suffix
--- @param input string
--- @return string|nil, string|nil
M.determine_prefix_and_suffix = function(input)
  input = input:match("^%s*(.-)%s*$")
  local prefix_map = {
    ["<x-"] = { prefix = "<x-", suffix = " />" },
    ["<live"] = { prefix = "<livewire:", suffix = " />" },
    ["@live"] = { prefix = "@livewire('", suffix = "')" },
    ["@exte"] = { prefix = "@extends('", suffix = "')" },
    ["@incl"] = { prefix = "@include('", suffix = "')" },
  }

  for key, value in pairs(prefix_map) do
    if vim.startswith(input, key) then
      return value.prefix, value.suffix
    end
  end

  return nil, nil
end

--- Get all components
--- @param prefix string
--- @return table
M.get_components = function(prefix)
  local component_dirs = {
    ["@livewire('"] = "resources/views/livewire/",
    ["<livewire:"] = "resources/views/livewire/",
    ["@include('"] = "resources/views/",
    ["@extends('"] = "resources/views/",
    ["<x-"] = "resources/views/components/",
  }

  local components_dir = component_dirs[prefix]
  local result = M.find_files(components_dir, "blade.php")

  if not result or result == "" then
    return {}
  end

  local components = {}
  for filename in result:gmatch("[^\r\n]+") do
    local component_name = filename:match(components_dir .. "(.+)")
    if component_name then
      component_name = component_name:gsub("^/", ""):gsub("%.blade%.php$", "")
      component_name = prefix .. component_name:gsub("/", ".")
      table.insert(components, { label = component_name })
    end
  end

  return components
end

--- Check if needle is in table
--- @param needle string
--- @param table table
--- @return boolean
M.in_table = function(needle, table)
  if type(table) ~= "table" then
    table = { table }
  end

  for _, value in ipairs(table) do
    if type(value) == "string" and (value == needle or needle:match(value)) then
      return true
    end
  end

  return false
end

--- Get routes
--- @param route_name string
--- @return table
M.get_routes = function(route_name)
  local result = M.execute_command_silent({
    "php",
    "artisan",
    "route:list",
    "--name=" .. route_name,
    "--json",
    "--columns=name,action",
  })

  if #result == 0 then
    return {}
  end

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

--- Get all route names
--- @return table
M.get_route_names = function()
  local result = M.execute_command_silent("php artisan route:list --json")

  if #result == 0 then
    return {}
  end

  local routes = vim.fn.json_decode(result)
  local route_map = {}

  for _, route in ipairs(routes) do
    if route.name ~= vim.NIL then
      table.insert(route_map, route.name)
    end
  end

  return route_map
end

--- Find all views names
--- @param path string
--- @param exclude_dirs? table
--- @return table
local function find_views_names(path, exclude_dirs)
  local result = find_files(path, "blade.php", exclude_dirs)

  if not result or result == "" then
    return {}
  end

  local views = {}
  for filename in result:gmatch("[^\r\n]+") do
    local view = filename:match(path .. "(.+)")
    if view then
      view = view:gsub("^/", ""):gsub("%.blade%.php$", ""):gsub("/", ".")
      table.insert(views, view)
    end
  end

  return views
end

--- Find all components view
--- @return table
local function find_components()
  return find_views_names("resources/views/components")
end

--- Find all livewire views
--- @return table
local function find_livewire()
  return find_views_names("resources/views/livewire")
end

--- Find all views excliding livewire abd Laravel components
--- @return table
local function find_views()
  return find_views_names("resources/views", { "resources/views/livewire", "resources/views/components" })
end

-- Find all routes
-- @return table
local function find_routes()
  return M.get_route_names()
end

--- Get all view names
--- @param input string
--- @return number, table
M.get_view_names = function(input, not_include_closing_tag)
  local patterns = {
    { pattern = "to_route%(",    tpl = "to_route('%s')",           ft = { "blade", "php" }, fn = find_routes },
    { pattern = "route%(",       tpl = "route('%s')",              ft = { "blade", "php" }, fn = find_routes },
    { pattern = "<x%-",          tpl = "<x-%s />",                 ft = "blade",            fn = find_components },
    { pattern = "<livewire",     tpl = "<livewire:%s />",          ft = "blade",            fn = find_livewire },
    { pattern = "@livewire%(",   tpl = "@livewire('%s')",          ft = "blade",            fn = find_livewire },
    { pattern = "@extends%(",    tpl = "@extends('%s')",           ft = "blade",            fn = find_views },
    { pattern = "@include%(",    tpl = "@include('%s')",           ft = "blade",            fn = find_views },
    { pattern = "Route::view%(", tpl = "Route::view('uri', '%s')", ft = "php",              fn = find_views },
    { pattern = "View::make%(",  tpl = "View::make('%s')",         ft = "php",              fn = find_views },
    { pattern = "view%(",        tpl = "view('%s')",               ft = "php",              fn = find_views },
  }

  local index
  local items = {}
  for i, p in ipairs(patterns) do
    if input:match(p.pattern) and M.in_table(vim.bo.filetype, p.ft) then
      local names = p.fn()
      for _, name in ipairs(names) do
        if name then
          local new_text = p.tpl:format(name)
          if not_include_closing_tag then
            new_text = new_text:gsub("'%)", "")
          end
          table.insert(items, {
            filterText = input .. name,
            label = p.tpl:format(name):gsub("^%s+", ""),
            newText = new_text,
          })
        end
      end
      index = i
      break
    end
  end

  return index, items
end

--- Get keyword pattern
--- @param include_routes boolean
--- @return string
M.get_keyword_pattern = function(include_routes)
  local components_keywords = {
    "<x-",
    "<livewire:",
  }
  local functions_keywords = {
    "@extends",
    "@include",
    "@livewire",
    "route",
    "to_route",
    "view",
    "View::make",
    "Route::view",
  }
  
  if not include_routes then
    functions_keywords = vim.tbl_filter(function(keyword)
      return not M.in_table(keyword, { "route", "to_route" })
    end, functions_keywords)
  end
  
  local functions_pattern = [[\(]] .. table.concat(functions_keywords, "\\|") .. [[\)\(('\)*\w*]]
  local components_pattern = [[\(]] .. table.concat(components_keywords, "\\|") .. [[\)\w*]]

  return functions_pattern .. [[\|]] .. components_pattern
end

--- Get root and language
--- @return table|nil, string|nil
M.get_root_and_lang = function()
  local parsers = require("nvim-treesitter.parsers")
  if not parsers then
    return nil, nil
  end

  local parser = parsers.get_parser()

  if not parser then
    return nil, nil
  end

  local tree = parser:parse()[1]

  if not tree then
    return nil, nil
  end

  local root = tree:root()
  local lang = parser:lang()

  if not M.in_table(lang, { "blade", "php" }) then
    vim.notify("Info: works only on PHP.")
    return nil, nil
  end

  return root, lang
end

--- Check if a BladeNavInstallArtisanCommand command exists
--- @return boolean
M.check_blade_command = function()
  local root_dir = M.get_root_dir()
  return vim.fn.filereadable(root_dir .. "/app/Console/Commands/BladeNav.php") == 1
end

--- Get PSR-4 mappings
--- @return table
M.get_psr4_mappings = function()
  local content, err = M.read_file("composer.json")
  if not content then
    vim.notify("Error reading file: " .. err)
    return {}
  end

  local decoded = vim.fn.json_decode(content)
  if not decoded or not decoded.autoload or not decoded.autoload["psr-4"] then
    return {}
  end

  return decoded.autoload["psr-4"]
end

--- Read a file and return its content
--- @param file_path string
--- @return string|nil, string|nil
M.read_file = function(file_path)
  local file = io.open(file_path, "r")
  if not file then
    return nil, "File not found: " .. file_path
  end

  local content = file:read("*all")
  file:close()

  return content
end

--- Write a file
--- @param file_path string
--- @param content string
--- @return boolean|nil, string
M.write_file = function(file_path, content)
  local file = io.open(file_path, "w")
  if not file then
    return nil, "Could not open file: " .. file_path
  end
  file:write(content)
  file:close()
  return true, ""
end

--- Get the PSR-4 app path
--- @return string
M.psr4_app = function()
  local psr4_mappings = M.get_psr4_mappings()
  for key, value in pairs(psr4_mappings) do
    if value == "app/" then
      return key
    end
  end
  return "App\\"
end

--- Modify the namespace in BladeNav.php
--- @param content string
--- @param psr4 string
--- @return string
M.modify_namespace = function(content, psr4)
  if psr4 ~= "App\\" then
    local output, _ = content:gsub("namespace App\\Console\\Commands;", "namespace " .. psr4 .. "Console\\Commands;")
    return output
  end

  return content
end

M.get_blade_nav_filename = function()
  local script_path = debug.getinfo(1, "S").source:sub(2)
  local script_dir = script_path:match("(.*/)")
  return script_dir .. "../../BladeNav.php"
end

--- Get the root directory
--- @return string, boolean
M.get_root_dir = function()
  local found = true
  local root_dir = M.execute_command_silent("git rev-parse --show-toplevel"):gsub("[\r\n]", "")
  if root_dir == "" then
    found = false
    root_dir = vim.fn.getcwd()
  end
  return root_dir, found
end

--- Convert kebab-case to PascalCase
--- @param input string
--- @return string
M.kebab_to_pascal = function(input)
  local result = input:gsub("(%-)(%w)", function(_, letter)
    return letter:upper()
  end)
  local text = result:gsub("^%l", string.upper)
  return text
end

return M
