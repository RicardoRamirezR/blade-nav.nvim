-- Custom nvim-cmp source for Laravel components

local utils = require("blade-nav.utils")

local M = {}

local registered = false

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
    local prefix, suffix = utils.determine_prefix_and_suffix(input)

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
    local components = utils.get_components(prefix)

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
