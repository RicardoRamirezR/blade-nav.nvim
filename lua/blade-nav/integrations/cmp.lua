-- lua/blade-nav/integrations/cmp.lua

local log = require("blade-nav.utils.log")
local utils = require("blade-nav.utils")
local tbl = require("blade-nav.utils.table")
local laravel = require("blade-nav.utils.laravel")
local str = require("blade-nav.utils.string")

local M = {}
local registered = false

--- Setup the nvim-cmp integration.
--- Registers the BladeNav source with cmp.
--- @param opts? table Options (e.g., { close_tag_on_complete = true })
function M.setup(opts)
  if registered then
    log.debug("nvim-cmp integration setup already called, skipping.")
    return
  end
  registered = true

  opts = opts or {}
  local close_tag_on_complete = opts.close_tag_on_complete ~= false

  local has_cmp, cmp = pcall(require, "cmp")
  if not has_cmp or not cmp then
    log.warn("nvim-cmp not found, skipping BladeNav cmp source setup.")
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
    local buf_ft = vim.api.nvim_buf_get_option(0, "filetype")
    return tbl.contains({ "blade", "php" }, buf_ft)
  end

  source.get_keyword_pattern = function()
    return str.get_keyword_pattern()
  end

  --- Main completion function for nvim-cmp.
  --- Gathers completion items.
  --- @param _ table The source instance (self).
  --- @param request table Request object from cmp (contains context, offset).
  --- @param callback function Callback to return completion items to cmp.
  source.complete = function(_, request, callback)
    local line_before_cursor = request.context.cursor_before_line or ""
    local offset_1b = request.offset or 1
    local input_prefix = string.sub(line_before_cursor, offset_1b)

    input_prefix = input_prefix:gsub("^%s+", ""):gsub("%s+$", "")

    log.debug("Input prefix extracted: '%s' (from line: '%s', offset: %d)", input_prefix, line_before_cursor, offset_1b)

    local _, completion_items = laravel.get_view_names(input_prefix, not close_tag_on_complete)

    completion_items = completion_items or {}

    log.debug("Gathered %d completion items.", #completion_items)

    local items = {}
    for _, item_data in ipairs(completion_items) do
      if type(item_data) == "table" and item_data.label then
        local cmp_item = {
          label = item_data.label,
          filterText = item_data.filterText or item_data.label,
          cmp = {
            kind_text = "BladeNav",
            kind_hl_group = "CmpItemKindBladeNav",
          },
          textEdit = {
            newText = item_data.newText or item_data.label,
            range = {
              start = {
                line = request.context.cursor.row - 1,
                character = offset_1b - 1,
              },
              ["end"] = {
                line = request.context.cursor.row - 1,
                character = request.context.cursor.col - 1,
              },
            },
          },
        }
        table.insert(items, cmp_item)
      else
        log.debug("Skipping invalid or unlabeled item: %s", vim.inspect(item_data))
      end
    end

    local result = {
      items = items,
      isIncomplete = false,
    }

    log.debug("Returning %d items to cmp.", #items)
    callback(result)
  end

  local current_sources = cmp.get_config().sources or {}
  local new_sources = {}

  table.insert(new_sources, { name = "blade-nav", priority = 1000 })
  for _, current_source in ipairs(current_sources) do
    if current_source.name ~= "blade-nav" then
      table.insert(new_sources, current_source)
    end
  end

  cmp.register_source("blade-nav", source.new())
  cmp.setup.filetype({ "blade", "php" }, {
    sources = cmp.config.sources(new_sources),
  })

  vim.api.nvim_set_hl(0, "CmpItemKindBladeNav", { fg = "#fb503b", default = true })

  log.info("BladeNav nvim-cmp source registered.")
end

return M
