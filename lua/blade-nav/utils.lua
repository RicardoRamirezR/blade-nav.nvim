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
return M
