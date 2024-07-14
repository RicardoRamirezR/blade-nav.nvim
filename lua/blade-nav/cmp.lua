-- Custom nvim-cmp source for Laravel routes
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
    return setmetatable({}, { __index = source })
  end

  source.get_debug_name = function()
    return "blade-nav"
  end

  source.is_available = function()
    return utils.in_table(vim.bo.filetype, { "blade", "php" })
  end

  source.get_keyword_pattern = function()
    local components_keywords = {
      "<x-",
      "<livewire:",
    }
    local functions_keywords = {
      "@extends",
      "@include",
      "@livewire",
      "route",
      "view",
      "View::make",
      "Route::view",
    }
    local functions_pattern = [[\(]] .. table.concat(functions_keywords, "\\|") .. [[\)\(('\)*\w*]]
    local components_pattern = [[\(]] .. table.concat(components_keywords, "\\|") .. [[\)\w*]]

    return functions_pattern .. [[\|]] .. components_pattern
  end

  source.complete = function(_, request, callback)
    local input = string.sub(request.context.cursor_before_line, request.offset - 1):gsub("%s+", "")
    local index, names = utils.get_view_names(input)
    local items = {}

    for _, name in ipairs(names) do
      table.insert(items, {
        filterText = name.filterText,
        label = name.label,
        cmp = {
          kind_hl_group = "CmpItemKindBladeNav",
          kind_text = "  " .. " blade-nav",
        },
        textEdit = {
          newText = name.newText,
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

    callback({ items = items, isIncomplete = #items == 0 })
  end

  local current_sources = cmp.get_config().sources
  local new_sources = {}

  table.insert(new_sources, { name = "blade-nav", priority = 1000 })
  for _, current_source in ipairs(current_sources) do
    table.insert(new_sources, current_source)
  end

  cmp.register_source("blade-nav", source.new())
  cmp.setup.filetype({ "blade", "php" }, {
    sources = cmp.config.sources(new_sources),
  })
  vim.api.nvim_set_hl(0, "CmpItemKindBladeNav", { fg = "#BDBDBD" })
end

return M
