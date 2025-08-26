-- lua/blade-nav/integrations/blink.lua
-- @diagnostic disable: duplicate-doc-field
-- @module 'blink.cmp'
-- @class blink.cmp.Source
-- @field opts table

local targets = require("blade-nav.targets")
local context_creator = require("blade-nav.core.context") -- Assuming core context
local resolver = require("blade-nav.core.resolver")       -- Assuming core resolver
local log = require("blade-nav.utils.log")
local config_module = require("blade-nav.core.config")    -- Assuming core config

local source = {}
local registered = false

-- @class BladeNavBlinkSourceOpts
-- @field close_tag_on_complete boolean

-- @param opts table Configuration options passed from setup
function source.new(opts)
  -- Validate options if needed (vim.validate example, adjust as needed)
  -- vim.validate {
  --     close_tag_on_complete = { opts.close_tag_on_complete, 'boolean', true }
  -- }
  -- Provide defaults
  opts = opts or {}
  opts.close_tag_on_complete = opts.close_tag_on_complete ~= false -- Default true

  -- Set highlight group
  vim.api.nvim_set_hl(0, "BlinkCmpKindBladeNav", { fg = "#f53003" }) -- Example color

  local self = setmetatable({}, { __index = source })
  self.opts = opts
  return self
end

function source:enabled()
  local buf_ft = vim.api.nvim_buf_get_option(0, "filetype")
  return buf_ft == "blade" or buf_ft == "php"
end

-- (Optional) Non-alphanumeric characters that trigger the source
function source:get_trigger_characters()
  -- These are common triggers for Blade/Laravel constructs
  -- Adjust based on what provides the best UX
  return { ".", "<", ":", "@", "(", "'", '"' }
end

function source:get_completions(ctx, callback)
  -- ctx (context) contains the current keyword, cursor position, bufnr, etc.
  -- You should never filter items based on the keyword, since blink.cmp will
  -- do this for you based on the `label` or `filterText`.

  local context = context_creator.create()
  -- Simplified: Get a list of *all* potential completions for the current filetype/context
  -- A more advanced version might tailor the list based on the specific context (e.g., inside @include() )

  -- Example: Get view names (this logic needs to be implemented in utils or targets)
  -- Placeholder logic - replace with actual fetching
  local items = {}
  -- Simulate fetching view names
  local view_names = { "layouts.app", "components.button", "user.profile", "admin.dashboard" }
  for _, name in ipairs(view_names) do
    table.insert(items, {
      label = name,
      filterText = name,
      kind = "BladeNav", -- Or use an enum/constant if blink defines kinds
      kind_hl_group = "BlinkCmpKindBladeNav",
      -- textEdit or insertText can be set here if needed for specific insertion
    })
  end

  -- Add route names, component names etc.
  local route_names = { "home", "user.profile", "admin.dashboard" }
  for _, name in ipairs(route_names) do
    table.insert(items, {
      label = name,
      filterText = name,
      kind = "BladeNav",
      kind_hl_group = "BlinkCmpKindBladeNav",
    })
  end

  -- Signal completion is done
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

  -- Register the source with blink.cmp
  blink.register_source("blade-nav", source.new(opts)) -- Pass config opts
  log.info("BladeNav blink.cmp source registered.")
end

return M
