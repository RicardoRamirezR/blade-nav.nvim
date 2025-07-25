-- lua/blade-nav/integrations/coq_source.lua (formerly coq_all.lua)
-- This file defines the actual coq source.
local utils = require("blade-nav.utils")
local log = require("blade-nav.utils.log")

-- `COQsources` is a global registry of sources for coq.nvim
_G.COQsources = _G.COQsources or {}

-- Define the BladeNav source for coq
_G.COQsources["blade-nav"] = {
  name = "blade-nav",
  fn = function(_, callback)
    -- Check filetype
    if not utils.table.contains(vim.bo.filetype, { "blade", "php" }) then
      callback()
      return
    end

    -- Get keyword pattern and current input line
    local pattern = utils.get_keyword_pattern() -- Assuming this function exists in utils
    local input = vim.api.nvim_get_current_line()

    -- Check if the line matches the keyword pattern
    if vim.fn.match(input, pattern) == -1 then
      callback() -- No match, don't provide completions
      return
    end

    -- Get view names (this logic needs implementation)
    -- Placeholder logic - replace with actual fetching
    local index, names = utils.get_view_names(input) -- Assuming this function exists
    if not index then
      callback({ isIncomplete = true })
      return
    end

    -- Prepare items for coq
    local items = {}
    for _, name in ipairs(names) do
      table.insert(items, {
        filterText = name.filterText,
        label = name.label,
        -- Add other fields coq expects if needed
      })
    end

    -- Callback with items
    callback({
      items = items,
      isIncomplete = true, -- Or false if list is exhaustive for current context
    })
  end,
}

-- Optionally log that the source was defined
log.debug("BladeNav coq source defined in _G.COQsources['blade-nav']")
-- Note: coq.nvim should automatically pick up sources defined in _G.COQsources

return nil -- No return value needed for coq source definition
