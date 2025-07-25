local utils = require("blade-nav.utils")

-- `COQsources` is a global registry of sources
COQsources = COQsources or {}

COQsources["blade-nav"] = {
  name = "blade-nav",
  fn = function(_, callback)
    if not utils.in_table(vim.bo.filetype, { "blade", "php" }) then
      callback()
    end

    local pattern = utils.get_keyword_pattern()
    local input = vim.api.nvim_get_current_line()
    if vim.fn.match(input, pattern) == -1 then
      return callback()
    end

    local index, names = utils.get_view_names(input)
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
