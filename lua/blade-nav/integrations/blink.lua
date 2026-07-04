-- lua/blade-nav/integrations/blink.lua
-- blink.cmp v1 provider module
-- Usage: sources.providers = { ["blade-nav"] = { name = "blade-nav", module = "blade-nav.integrations.blink" } }

local log = require("blade-nav.utils.log")
local config = require("blade-nav.core.config")

local Source = {}

function Source.new()
  return setmetatable({}, { __index = Source })
end

function Source:enabled()
  local ft = vim.api.nvim_get_option_value("filetype", { buf = 0 })
  return ft == "blade" or ft == "php"
end

function Source:get_trigger_characters()
  return { ".", "<", ":", "@", "(", "'", '"' }
end

---@param ctx blink.cmp.Context
---@param callback fun(result?: blink.cmp.CompletionResponse)
function Source:get_completions(ctx, callback)
  local laravel = require("blade-nav.utils.laravel")

  local line_before_cursor = ctx.line:sub(1, ctx.cursor[2])
  -- TODO(shared-prefix): adopt items_for_prefix
  local input_prefix = line_before_cursor:match("[^%s]*$") or ""

  log.debug("Blink input prefix: '%s'", input_prefix)

  local close_tag_on_complete = config.get("close_tag_on_complete")
  if close_tag_on_complete == nil then
    close_tag_on_complete = true
  end

  local _, completion_items = laravel.get_view_names(input_prefix, not close_tag_on_complete)
  completion_items = completion_items or {}

  local items = {}
  for _, item_data in ipairs(completion_items) do
    if type(item_data) == "table" and item_data.label then
      table.insert(items, {
        label = item_data.label,
        filterText = item_data.filterText or item_data.label,
        insertText = item_data.newText or item_data.label,
        kind = require("blink.cmp.types").CompletionItemKind.Reference,
      })
    end
  end

  log.debug("Blink returning %d items", #items)
  callback({ is_incomplete_forward = false, is_incomplete_backward = false, items = items })
end

return Source
