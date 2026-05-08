-- lua/blade-nav/integrations/coq_source.lua (formerly coq_all.lua)

local log = require("blade-nav.utils.log")
local tbl = require("blade-nav.utils.table")
local str = require("blade-nav.utils.string")
local laravel = require("blade-nav.utils.laravel")

_G.COQsources = _G.COQsources or {}

_G.COQsources["blade-nav"] = {
  name = "blade-nav",
  fn = function(_, callback)
    if not tbl.contains({ "blade", "php" }, vim.bo.filetype) then
      callback()
      return
    end

    local pattern = str.get_keyword_pattern()
    local input = vim.api.nvim_get_current_line()

    if vim.fn.match(input, pattern) == -1 then
      callback()
      return
    end

    local index, names = laravel.get_view_names(input)
    if not index then
      callback({ isIncomplete = true })
      return
    end

    local items = {}
    for _, name in ipairs(names) do
      table.insert(items, {
        filterText = name.filterText,
        label = name.label,
      })
    end

    callback({
      items = items,
      isIncomplete = true,
    })
  end,
}

log.debug("BladeNav coq source defined in _G.COQsources['blade-nav']")

return nil
