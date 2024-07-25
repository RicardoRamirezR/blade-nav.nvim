local M = {}

M.get_blade_files = function()
  local handle = io.popen('find resources/views -type f -name "*.blade.php" | sort')
  local result = handle:read("*a")
  handle:close()

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

M.determine_prefix_and_suffix = function(input)
  input = input:match("^%s*(.-)%s*$")
  local prefix_map = {
    ["<x-"] = { prefix = "<x-", suffix = " />" },
    ["<live"] = { prefix = "<livewire:", suffix = " />" },
    ["@live"] = { prefix = "@livewire('", suffix = "')" },
    ["@exte"] = { prefix = "@extends('", suffix = "')" },
    ["@incl"] = { prefix = "@include('", suffix = "')" },
  }

  local prefix = nil
  local suffix = nil

  for key, value in pairs(prefix_map) do
    if vim.startswith(input, key) then
      prefix = value.prefix
      suffix = value.suffix
      break
    end
  end

  return prefix, suffix
end

M.get_components = function(prefix)
  local component_dirs = {
    ["@livewire('"] = "resources/views/livewire/",
    ["<livewire:"] = "resources/views/livewire/",
    ["@include('"] = "resources/views/",
    ["@extends('"] = "resources/views/",
    ["<x-"] = "resources/views/components/",
  }

  local components_dir = component_dirs[prefix]
  local components = {}
  local handle = io.popen("find " .. components_dir .. " -type f")

  for filename in handle:lines() do
    local component_name = filename:match(components_dir .. "(.+)")
    if component_name then
      component_name = component_name:gsub("^/", ""):gsub("%.blade%.php$", "")
      component_name = prefix .. component_name:gsub("/", ".")
      table.insert(components, { label = component_name })
    end
  end

  handle:close()

  return components
end

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

M.get_route_names = function()
  local obj = vim.system({
    "php",
    "artisan",
    "route:list",
    "--json",
  }, { text = true }):wait()

  if obj.code ~= 0 then
    vim.notify("Error running artisan route:list")
    return {}
  end

  local routes = vim.fn.json_decode(obj.stdout)
  local route_map = {}

  for _, route in ipairs(routes) do
    if route.name ~= vim.NIL then
      table.insert(route_map, route.name)
    end
  end

  return route_map
end

local function find_files(cmd_string, exclude_option, path, exclude_dirs)
  local exclude_cmd = ""
  exclude_option = " " .. exclude_option
  for _, dir in ipairs(exclude_dirs or {}) do
    exclude_cmd = exclude_cmd .. string.format(exclude_option, dir)
  end

  local cmd = string.format(cmd_string, path, exclude_cmd) .. " 2>/dev/null"
  local handle = io.popen(cmd)
  local result = handle and handle:read("*a")

  if handle then
    handle:close()
  end

  return result
end

local function find_files_fd(path, exclude_dirs)
  return find_files("fd -p ./%s --type file --extension blade.php %s", "-E %s", path, exclude_dirs)
end

local function find_files_find(path, exclude_dirs)
  return find_files("find ./%s -type f -name '*.blade.php'%s", "-not -path './%s/*'", path, exclude_dirs)
end

local function find_views_names(path, exclude_dirs)
  local result = find_files_fd(path, exclude_dirs)

  if not result or result == "" then
    result = find_files_find(path, exclude_dirs)
  end

  if not result then
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

local function find_components()
  return find_views_names("resources/views/components")
end

local function find_livewire()
  return find_views_names("resources/views/livewire")
end

local function find_views()
  return find_views_names("resources/views", { "resources/views/livewire", "resources/views/components" })
end

local function find_routes()
  return M.get_route_names()
end

M.get_view_names = function(input)
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
          table.insert(items, {
            filterText = input .. name,
            label = p.tpl:format(name):gsub("^%s+", ""),
            newText = p.tpl:format(name),
          })
        end
      end
      index = i
      break
    end
  end
  return index, items
end

M.get_keyword_pattern = function()
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
  local functions_pattern = [[\(]] .. table.concat(functions_keywords, "\\|") .. [[\)\(('\)*\w*]]
  local components_pattern = [[\(]] .. table.concat(components_keywords, "\\|") .. [[\)\w*]]

  return functions_pattern .. [[\|]] .. components_pattern
end

M.get_root_and_lang = function()
  local parsers = require("nvim-treesitter.parsers")
  local parser = parsers.get_parser()

  if not parser then
    vim.notify("Failed to parse the tree.", vim.log.levels.ERROR)
    return nil, nil
  end

  local tree = parser:parse()[1]

  if not tree then
    vim.notify("Failed to parse the tree.", vim.log.levels.ERROR)
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

return M
