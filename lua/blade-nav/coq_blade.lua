local utils = require("blade-nav.utils")

-- `COQsources` is a global registry of sources
COQsources = COQsources or {}

COQsources["blade-nav-blade"] = {
  name = "blade-nav",
  fn = function(_, callback)
    if vim.bo.filetype ~= "blade" then
      callback()
    end

    local pattern = [[\C\(<x-\|<livewire:\|<livewire\|@livewire(\?\|@extends(\?\|@include(\?\)]]
    local input = vim.api.nvim_get_current_line()
    if vim.fn.match(input, pattern) == -1 then
      return callback()
    end

    local prefix, suffix = utils.determine_prefix_and_suffix(input)
    if not prefix then
      callback({ isIncomplete = true })
      return
    end

    local items = {}
    local components = utils.get_components(prefix)

    for _, component in ipairs(components) do
      table.insert(items, {
        filterText = component.label,
        label = component.label,
        kind = vim.lsp.protocol.CompletionItemKind.Reference,
        insertText = component.label .. suffix,
      })
    end

    callback({
      items = items,
      isIncomplete = true,
    })
  end,
}
