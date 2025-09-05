-- lua/blade-nav/utils/string.lua
local log = require("blade-nav.utils.log")
local tbl = require("blade-nav.utils.table")
local M = {}

--- Explode string to table by delimiter.
--- @param delimiter string
--- @param text string
--- @return table
function M.explode(delimiter, text)
  local result = {}
  if not text or text == "" then
    return result
  end
  local pattern = string.format("([^%s]+)", delimiter:gsub("([^%w])", "%%%1"))
  for match in string.gmatch(text, pattern) do
    table.insert(result, match)
  end
  return result
end

--- Convert kebab-case to PascalCase.
--- @param input string
--- @return string
function M.kebab_to_pascal(input)
  if not input then
    return ""
  end
  local result = input:gsub("^%l", string.upper):gsub("%-(%w)", string.upper)
  return result
end

--- Determine prefix and suffix for a component/directive.
--- @param input string
--- @return string|nil, string|nil
function M.determine_prefix_and_suffix(input)
  input = input:match("^%s*(.-)%s*$")
  local prefix_map = {
    ["<x-"] = { prefix = "<x-", suffix = " />" },
    ["<livewire:"] = { prefix = "<livewire:", suffix = " />" },
    ["@livewire('"] = { prefix = "@livewire('", suffix = "')" },
    ["@extends('"] = { prefix = "@extends('", suffix = "')" },
    ["@include('"] = { prefix = "@include('", suffix = "')" },
    ["@component('"] = { prefix = "@component('", suffix = "')" },
  }
  for key, value in pairs(prefix_map) do
    if vim.startswith(input, key) then
      return value.prefix, value.suffix
    end
  end
  return nil, nil
end

--- Get keyword pattern for triggering completions.
--- @return string
function M.get_keyword_pattern()
  local components_keywords = {
    "<x-",
    "<livewire:",
  }
  local functions_keywords = {
    "@component",
    "@extends",
    "@include",
    "@livewire",
    "config",
    "env",
    "route",
    "to_route",
    "view",
    "View::make",
    "Route::view",
    "inertia",
    "Inertia::render",
  }

  if vim.g.blade_nav and vim.g.blade_nav.include_routes == false then
    functions_keywords = vim.tbl_filter(function(keyword)
      return not tbl.contains({ "route", "to_route" }, keyword)
    end, functions_keywords)
  end

  local functions_pattern = [[\(]] .. table.concat(functions_keywords, "\\|") .. [[\)\(('\)*\w*]]
  local components_pattern = [[\(]] .. table.concat(components_keywords, "\\|") .. [[\)\w*]]
  return functions_pattern .. [[\|]] .. components_pattern
end

--- Checks if the cursor is inside an inner function (simplified).
--- @param input string
--- @return string
function M.extract_inner_function(input)
  if not input or type(input) ~= "string" then
    return ""
  end
  return input:match("^%s*(.-)%s*$") or input
end

return M
