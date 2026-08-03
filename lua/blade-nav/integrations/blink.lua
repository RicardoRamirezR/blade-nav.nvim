-- lua/blade-nav/integrations/blink.lua
-- blink.cmp v1 provider module
-- Usage: sources.providers = { ["blade-nav"] = { name = "blade-nav", module = "blade-nav.integrations.blink" } }

local log = require("blade-nav.utils.log")
local config = require("blade-nav.core.config")

-- Guarded: blink.cmp may not be installed when this module is merely loaded.
local has_blink_types, blink_types = pcall(require, "blink.cmp.types")
local reference_kind = has_blink_types and blink_types.CompletionItemKind.Reference or nil

local Source = {}

function Source.new()
  return setmetatable({}, { __index = Source })
end

function Source.enabled(_)
  local ft = vim.api.nvim_get_option_value("filetype", { buf = 0 })
  return ft == "blade" or ft == "php"
end

function Source.get_trigger_characters(_)
  return { ".", "<", ":", "@", "(", "'", '"' }
end

---@param _ table The source instance (self).
---@param ctx blink.cmp.Context
---@param callback fun(result?: blink.cmp.CompletionResponse)
function Source.get_completions(_, ctx, callback)
  local laravel = require("blade-nav.utils.laravel")

  local line_before_cursor = ctx.line:sub(1, ctx.cursor[2])
  local input_prefix = line_before_cursor:match("[^%s]*$") or ""

  log.debug("Blink input prefix: '%s'", input_prefix)

  local close_tag_on_complete = config.get("close_tag_on_complete")
  if close_tag_on_complete == nil then
    close_tag_on_complete = true
  end

  -- items_for_prefix must never escape an error: the completion contract
  -- requires the callback to be invoked exactly once.
  local ok, completion_items =
    pcall(laravel.items_for_prefix, input_prefix, { not_include_closing_tag = not close_tag_on_complete })
  if not ok then
    log.error("BladeNav blink source: items_for_prefix failed: %s", completion_items)
    callback({ is_incomplete_forward = false, is_incomplete_backward = false, items = {} })
    return
  end
  completion_items = completion_items or {}

  local items = {}
  for _, item_data in ipairs(completion_items) do
    table.insert(items, {
      label = item_data.label,
      filterText = item_data.filter_text or item_data.label,
      insertText = item_data.new_text or item_data.label,
      kind = reference_kind,
    })
  end

  log.debug("Blink returning %d items", #items)
  callback({ is_incomplete_forward = false, is_incomplete_backward = false, items = items })
end

return Source
