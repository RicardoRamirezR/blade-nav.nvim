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
    local input = args.line:sub(1, args.pos[2])

    if vim.fn.match(input, pattern) == -1 then
      callback()
      return
    end

    local close_tag_on_complete = config.get("close_tag_on_complete")
    if close_tag_on_complete == nil then
      close_tag_on_complete = true
    end

    -- items_for_prefix must never escape an error: the completion contract
    -- requires the callback to be invoked exactly once.
    local ok, names = pcall(laravel.items_for_prefix, input, { not_include_closing_tag = not close_tag_on_complete })
    if not ok then
      log.error("BladeNav coq source: items_for_prefix failed: %s", names)
      callback()
      return
    end
    if not names then
      callback()
      return
    end

    local items = {}
    for _, name in ipairs(names) do
      table.insert(items, {
        filterText = name.filter_text,
        label = name.label,
        insertText = name.new_text or name.label,
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
