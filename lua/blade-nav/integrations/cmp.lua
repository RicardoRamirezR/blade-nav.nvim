-- lua/blade-nav/integrations/cmp.lua
-- Integration for nvim-cmp, providing completions for Blade/Laravel constructs.
-- Based on structure from new-version.txt and working-version.txt cmp.lua

local log = require("blade-nav.utils.log")
local utils = require("blade-nav.utils")     -- Main utils module
local tbl = require("blade-nav.utils.table") -- Require the table utilities module
local laravel = require("blade-nav.utils.laravel")
local string_utils = require("blade-nav.utils.string")
-- local config_module = require("blade-nav.core.config") -- If you move config/get_keyword_pattern there

local M = {}
local registered = false -- Flag to ensure setup only runs once

--- Setup the nvim-cmp integration.
--- Registers the BladeNav source with cmp.
--- @param opts? table Options (e.g., { close_tag_on_complete = true })
function M.setup(opts)
  -- Ensure setup only runs once
  if registered then
    log.debug("nvim-cmp integration setup already called, skipping.")
    return
  end
  registered = true

  -- Handle options, defaulting close_tag_on_complete to true
  opts = opts or {}
  local close_tag_on_complete = opts.close_tag_on_complete ~= false -- Default true

  -- Attempt to load nvim-cmp
  local has_cmp, cmp = pcall(require, "cmp")
  if not has_cmp or not cmp then
    log.warn("nvim-cmp not found, skipping BladeNav cmp source setup.")
    return
  end

  -- Define the BladeNav cmp source
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

  --- Defines the keyword pattern for this source.
  --- This pattern tells cmp what constitutes a "word" for this source to complete.
  --- It needs to be broad enough to trigger correctly.
  source.get_keyword_pattern = function()
    -- Use your existing, well-defined keyword pattern function
    -- This pattern should already be suitable for triggering completion
    -- in the right contexts (after @include(, <x-, etc.).
    return string_utils.get_keyword_pattern() -- This returns the combined pattern string
  end

  --- Main completion function for nvim-cmp.
  --- Gathers completion items.
  --- @param _ table The source instance (self).
  --- @param request table Request object from cmp (contains context, offset).
  --- @param callback function Callback to return completion items to cmp.
  source.complete = function(_, request, callback)
    -- --- Determine the Input Prefix ---
    -- Get the text before the cursor on the current line
    local line_before_cursor = request.context.cursor_before_line or ""
    -- Get the byte offset where the completion word starts
    -- request.offset is 1-based byte index
    local offset_1b = request.offset or 1
    -- Extract the prefix being completed
    -- string.sub uses 1-based byte indices
    local input_prefix = string.sub(line_before_cursor, offset_1b)

    -- Sanitize input: remove leading/trailing whitespace
    -- The pattern matching in get_view_names/utils might handle this,
    -- but cleaning it here is good practice.
    input_prefix = input_prefix:gsub("^%s+", ""):gsub("%s+$", "")

    log.debug("Input prefix extracted: '%s' (from line: '%s', offset: %d)", input_prefix, line_before_cursor, offset_1b)

    -- --- Gather Completion Items ---
    -- Call the existing utility function to get names based on the input prefix.
    -- utils.get_view_names is expected to analyze the prefix (e.g., <x-, @include()
    -- and return appropriate completions (view names, component names) formatted for cmp.
    -- It also handles the close_tag_on_complete logic internally.
    local _, completion_items = laravel.get_view_names(input_prefix, not close_tag_on_complete) -- Note: notted boolean

    -- Ensure items is a table
    completion_items = completion_items or {}

    log.debug("Gathered %d completion items.", #completion_items)

    -- --- Prepare Items for cmp ---
    local items = {}
    -- Iterate through the items returned by utils.get_view_names
    -- These are expected to be pre-formatted for cmp consumption,
    -- including filterText, label, newText.
    for _, item_data in ipairs(completion_items) do
      -- item_data from utils.get_view_names is expected like:
      -- { filterText = "...", label = "...", newText = "..." }
      -- We need to convert this into the structure cmp expects for textEdit
      -- and potentially add cmp-specific metadata.

      if type(item_data) == "table" and item_data.label then
        local cmp_item = {
          label = item_data.label,
          filterText = item_data.filterText or item_data.label,
          -- cmp-specific metadata
          cmp = {
            kind_text = "BladeNav", -- Or derive from item_data.type if available
            kind_hl_group = "CmpItemKindBladeNav",
          },
          -- Use textEdit for precise insertion/replacement.
          -- The range needs to be calculated based on the *original input prefix*
          -- and the *current cursor position*.
          textEdit = {
            newText = item_data.newText or item_data.label,
            -- Define the range to replace: from offset_1b to current cursor position
            range = {
              start = {
                line = request.context.cursor.row - 1, -- 0-based line
                character = offset_1b - 1,             -- 0-based character (offset is 1-based)
              },
              ["end"] = {
                line = request.context.cursor.row - 1,      -- 0-based line
                character = request.context.cursor.col - 1, -- 0-based character
              },
            },
          },
        }
        table.insert(items, cmp_item)
      else
        log.debug("Skipping invalid or unlabeled item: %s", vim.inspect(item_data))
      end
    end

    -- --- Return Items to cmp ---
    -- Prepare the result table for cmp's callback.
    -- isIncomplete = false assumes the list is complete for the given prefix.
    -- Set to true if dealing with huge lists or pagination.
    local result = {
      items = items,
      isIncomplete = false,
    }

    log.debug("Returning %d items to cmp.", #items)
    -- Call the callback with the result
    callback(result)
  end

  -- --- Register the Source with nvim-cmp ---
  -- Register the source with cmp using the name "blade-nav"
  -- Use the registration logic from new-version.txt/working-version.txt
  local current_sources = cmp.get_config().sources or {} -- Handle potential nil
  local new_sources = {}

  table.insert(new_sources, { name = "blade-nav", priority = 1000 })
  for _, current_source in ipairs(current_sources) do
    -- Avoid potential duplicates, though cmp.setup.filetype should overwrite
    if current_source.name ~= "blade-nav" then
      table.insert(new_sources, current_source)
    end
  end

  cmp.register_source("blade-nav", source.new())
  cmp.setup.filetype({ "blade", "php" }, {
    sources = cmp.config.sources(new_sources),
  })
  -- --- Set Highlight Group ---
  -- Define a highlight group for BladeNav completion items
  vim.api.nvim_set_hl(0, "CmpItemKindBladeNav", { fg = "#fb503b", default = true }) -- Example orange/red color

  log.info("BladeNav nvim-cmp source registered.")
end

return M
