-- lua/blade-nav/integrations/blink.lua

local context_creator = require("blade-nav.core.context")
local log = require("blade-nav.utils.log")

local source = {}
local registered = false

-- @class BladeNavBlinkSourceOpts
-- @field close_tag_on_complete boolean

-- @param opts table Configuration options passed from setup
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
  local context = context_creator.create()
  local items = {}
  local view_names = { "layouts.app", "components.button", "user.profile", "admin.dashboard" }
  for _, name in ipairs(view_names) do
    table.insert(items, {
      label = name,
      filterText = name,
      kind = "BladeNav",
      kind_hl_group = "BlinkCmpKindBladeNav",
    })
  end

  local route_names = { "home", "user.profile", "admin.dashboard" }
  for _, name in ipairs(route_names) do
    table.insert(items, {
      label = name,
      filterText = name,
      kind = "BladeNav",
      kind_hl_group = "BlinkCmpKindBladeNav",
    })
  end

  callback({ items = items, isIncomplete = false })
end

local M = {}

-- Setup the blink integration.
-- @param opts table Configuration options (specifically integrations.blink)
function M.setup(opts)
  if registered or not opts.integrations.blink then
    log.debug("BladeNav blink setup skipped (already registered or disabled).")
    return
  end
  registered = true

  local has_blink, blink = pcall(require, "blink.cmp")
  if not has_blink then
    log.warn("blink.cmp not found, skipping BladeNav blink source.")
    return
  end

  blink.register_source("blade-nav", source.new(opts))
  log.info("BladeNav blink.cmp source registered.")
end

return M
