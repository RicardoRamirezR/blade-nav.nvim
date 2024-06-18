-- Custom nvim-cmp source for Laravel components

local M = {}

local registered = false

local function determine_prefix_and_suffix(input)
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

local function get_components(prefix)
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

M.setup = function()
  if registered then
    return
  end

  registered = true

  local has_cmp, cmp = pcall(require, "cmp")

  if not has_cmp then
    return
  end

  local source = {}

  source.new = function()
    return setmetatable({ cache = {} }, { __index = source })
  end

  source.get_trigger_characters = function()
    return {
      "<x-",
      "@extends",
      "@include",
      "@livewire",
      "<livewire",
    }
  end

  source.complete = function(self, request, callback)
    local bufnr = vim.api.nvim_get_current_buf()
    local input = string.sub(request.context.cursor_before_line, request.offset - 1)
    local prefix, suffix = determine_prefix_and_suffix(input)

    if not prefix then
      callback({ isIncomplete = true })
      return
    end

    self.cache[bufnr] = self.cache[bufnr] or {}
    if self.cache[bufnr][prefix] then
      callback({
        items = self.cache[bufnr][prefix],
        isIncomplete = false,
      })
      return
    end

    local items = {}
    local components = get_components(prefix)

    for _, component in ipairs(components) do
      table.insert(items, {
        filterText = component.label,
        label = component.label,
        kind = require("cmp.types.lsp").CompletionItemKind.Reference,
        textEdit = {
          newText = component.label .. suffix,
          range = {
            start = {
              line = request.context.cursor.row - 1,
              character = request.context.cursor.col - 1 - #input,
            },
            ["end"] = {
              line = request.context.cursor.row - 1,
              character = request.context.cursor.col - 1,
            },
          },
        },
      })
    end

    callback({
      items = items,
      isIncomplete = false,
    })
  end

  local current_sources = cmp.get_config().sources
  local new_sources = {}

  table.insert(new_sources, { name = "blade-nav", priority = 1000 })
  for _, current_source in ipairs(current_sources) do
    table.insert(new_sources, current_source)
  end

  cmp.register_source("blade-nav", source.new())
  cmp.setup.filetype("blade", {
    sources = cmp.config.sources(new_sources),
  })
end

return M
