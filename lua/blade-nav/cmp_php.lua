-- Custom nvim-cmp source for Laravel views

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

  source.get_debug_name = function()
    return "blade-nav-php"
  end

  source.get_keyword_pattern = function()
    return [[\(view\|View::make\|Route::view\)\(('\)*\w*]]
  end

  local function get_blade_files()
    local handle = io.popen('find resources/views -type f -name "*.blade.php" | sort')
    local result = handle:read("*a")
    handle:close()

    local files = {}
    for file in result:gmatch("[^\r\n]+") do
      table.insert(files, file)
    end

    return files
  end

  source.complete = function(_, request, callback)
    local input = string.sub(request.context.cursor_before_line, request.offset - 1):gsub("%s+", "")

    -- Define patterns to match and corresponding completion items
    local patterns = {
      { pattern = "Route::view%s*", item = "Route::view('uri', '%s')" },
      { pattern = "View::make%s*",  item = "View::make('%s')" },
      { pattern = "view%s*",        item = "view('%s')" },
    }

    local items = {}
    for _, p in ipairs(patterns) do
      if input:match(p.pattern) then
        local blade_files = get_blade_files()
        for _, file in ipairs(blade_files) do
          local view_name = file:match("resources/views/(.*)%.blade%.php$")
          if view_name then
            view_name = view_name:gsub("/", ".")
            table.insert(items, {
              filterText = input .. view_name,
              label = p.item:format(view_name):gsub("^%s+", ""),
              kind = require("cmp.types.lsp").CompletionItemKind.Reference,
              textEdit = {
                newText = p.item:format(view_name),
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
        end
        break
      end
    end

    callback({ items = items, isIncomplete = false })
  end

  local current_sources = cmp.get_config().sources
  local new_sources = {}

  table.insert(new_sources, { name = "blade-nav-php", priority = 1000 })
  for _, current_source in ipairs(current_sources) do
    table.insert(new_sources, current_source)
  end

  cmp.register_source("blade-nav-php", source.new())
  cmp.setup.filetype("php", {
    sources = cmp.config.sources(new_sources),
  })
end

return M
