local utils = require("blade-nav.utils")

-- `COQsources` is a global registry of sources
COQsources = COQsources or {}

COQsources["blade-nav-routes"] = nil

COQsources["blade-nav-routes"] = {
  name = "blade-nav",
  fn = function(_, callback)
    if not utils.in_array(vim.bo.filetype, { "blade", "php" }) then
      callback()
    end

    local pattern = [[\C\s\?route(']]
    local input = vim.api.nvim_get_current_line()

    if vim.fn.match(input, pattern) == -1 then
      return callback()
    end

    local patterns = {
      { pattern = "%s*route%s*", item = "route('%s')" },
    }

    local items = {}
    for _, p in ipairs(patterns) do
      if input:match(p.pattern) then
        local route_names = utils.get_route_names()
        for _, route_name in ipairs(route_names) do
          table.insert(items, {
            label = p.item:format(route_name):gsub("^%s+", ""),
            kind = vim.lsp.protocol.CompletionItemKind.Reference,
            insertText = p.item:format(route_name),
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
