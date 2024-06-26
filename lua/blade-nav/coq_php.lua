local utils = require("blade-nav.utils")

-- `COQsources` is a global registry of sources
COQsources = COQsources or {}

COQsources["blade-nav-php"] = nil

COQsources["blade-nav-php"] = {
  name = "blade-nav",
  fn = function(_, callback)
    if vim.bo.filetype ~= "php" then
      callback()
    end

    local pattern = [[\C\(\sview\|\sView::make\|\s\?Route::view\)\(('\)\?]]
    local input = vim.api.nvim_get_current_line()

    if vim.fn.match(input, pattern) == -1 then
      return callback()
    end

    local patterns = {
      { pattern = "%s*Route::view%s*", item = "Route::view('uri', '%s')" },
      { pattern = "%sView::make%s*",   item = "View::make('%s')" },
      { pattern = "%sview%s*",         item = "view('%s')" },
    }

    local items = {}
    for _, p in ipairs(patterns) do
      if input:match(p.pattern) then
        local blade_files = utils.get_blade_files()
        for _, view_name in ipairs(blade_files) do
          table.insert(items, {
            label = p.item:format(view_name):gsub("^%s+", ""),
            kind = vim.lsp.protocol.CompletionItemKind.Reference,
            insertText = p.item:format(view_name),
          })
        end
      end
    end
    callback({
      isIncomplete = true,
      items = items,
    })
  end,
}
