-- lua/blade-nav/integrations/coq_source.lua (formerly coq_all.lua)

local log = require("blade-nav.utils.log")
local tbl = require("blade-nav.utils.table")
local str = require("blade-nav.utils.string")
local laravel = require("blade-nav.utils.laravel")
local config = require("blade-nav.core.config")

_G.COQsources = _G.COQsources or {}

_G.COQsources["blade-nav"] = {
  name = "blade-nav",
  fn = function(args, callback)
    if not tbl.contains({ "blade", "php" }, vim.bo.filetype) then
      callback()
      return
    end

    local pattern = str.get_keyword_pattern()
    -- TODO(shared-prefix): adopt items_for_prefix
    local input = args.line:sub(1, args.pos[2])

    if vim.fn.match(input, pattern) == -1 then
      callback()
      return
    end

    local close_tag_on_complete = config.get("close_tag_on_complete")
    if close_tag_on_complete == nil then
      close_tag_on_complete = true
    end

    local index, names = laravel.get_view_names(input, not close_tag_on_complete)
    if not index then
      callback()
      return
    end

    local items = {}
    for _, name in ipairs(names) do
      table.insert(items, {
        filterText = name.filterText,
        label = name.label,
        insertText = name.newText or name.label,
      })
    end

    callback({
      items = items,
      isIncomplete = false,
    })
  end,
}

log.debug("BladeNav coq source defined in _G.COQsources['blade-nav']")

return nil
