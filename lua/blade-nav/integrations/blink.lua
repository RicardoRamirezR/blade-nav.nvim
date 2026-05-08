-- lua/blade-nav/integrations/blink.lua

local log = require("blade-nav.utils.log")

local source = {}
local registered = false

function source.new(opts)
  opts = opts or {}
  opts.close_tag_on_complete = opts.close_tag_on_complete ~= false

  vim.api.nvim_set_hl(0, "BlinkCmpKindBladeNav", { fg = "#f53003" })

  local self = setmetatable({}, { __index = source })
  self.opts = opts
  return self
end

function source:enabled()
  local buf_ft = vim.api.nvim_get_option_value("filetype", { buf = 0 })
  return buf_ft == "blade" or buf_ft == "php"
end

function source:get_trigger_characters()
  return { ".", "<", ":", "@", "(", "'", '"' }
end

function source:get_completions(ctx, callback)
  local laravel = require("blade-nav.utils.laravel")
  local str = require("blade-nav.utils.string")

  local line_before_cursor = ctx.line:sub(1, ctx.cursor[2])
  local input_prefix = line_before_cursor:match("[^%s]*$") or ""

  log.debug("Blink input prefix: '%s'", input_prefix)

  local _, completion_items = laravel.get_view_names(input_prefix, not self.opts.close_tag_on_complete)
  completion_items = completion_items or {}

  local items = {}
  for _, item_data in ipairs(completion_items) do
    if type(item_data) == "table" and item_data.label then
      table.insert(items, {
        label = item_data.label,
        filterText = item_data.filterText or item_data.label,
        insertText = item_data.newText or item_data.label,
        kind = "BladeNav",
        kind_hl_group = "BlinkCmpKindBladeNav",
      })
    end
  end

  log.debug("Blink returning %d items", #items)
  callback({ items = items, isIncomplete = false })
end

local M = {}

function M.setup(opts)
  if registered or not opts.integrations.blink then
    log.debug("BladeNav blink setup skipped (already registered or disabled).")
    return
  end
  registered = true

  local has_blink, blink = pcall(require, "blink.cmp")
  if not has_blink then
    log.debug("blink.cmp not found, skipping BladeNav blink source.")
    return
  end

  blink.register_source("blade-nav", source.new(opts))
  log.info("BladeNav blink.cmp source registered.")
end

return M
