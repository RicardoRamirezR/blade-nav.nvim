-- lua/blade-nav/integrations/cmp.lua

local log = require("blade-nav.utils.log")
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

  opts = opts or {}
  local close_tag_on_complete = opts.close_tag_on_complete ~= false

  local has_cmp, cmp = pcall(require, "cmp")
  if not has_cmp or not cmp then
    log.warn("nvim-cmp not found, skipping BladeNav cmp source setup.")
    return
  end

  registered = true

  local source = {}

  source.new = function()
    return setmetatable({}, { __index = source })
  end

  source.get_debug_name = function()
    return "blade-nav"
  end

  source.is_available = function()
    local buf_ft = vim.api.nvim_get_option_value("filetype", { buf = 0 })
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

    local completion_items = laravel.items_for_prefix(
      input_prefix,
      { not_include_closing_tag = not close_tag_on_complete }
    ) or {}

    log.debug("Gathered %d completion items.", #completion_items)

    local items = {}
    for _, item_data in ipairs(completion_items) do
      local cmp_item = {
        label = item_data.label,
        filterText = item_data.filter_text or item_data.label,
        cmp = {
          kind_text = "BladeNav",
          kind_hl_group = "CmpItemKindBladeNav",
        },
        textEdit = {
          newText = item_data.new_text or item_data.label,
          range = {
            start = {
              line = request.context.cursor.line,
              character = request.context.cursor.character - #input_prefix,
            },
            ["end"] = {
              line = request.context.cursor.line,
              character = request.context.cursor.character,
            },
          },
        },
      }
      table.insert(items, cmp_item)
    end

    local result = {
      items = items,
      isIncomplete = false,
    }

    log.debug("Returning %d items to cmp.", #items)
    callback(result)
  end

  local warned_config_fallback = false

  --- Resolves the sources already configured for a filetype (falling back to
  --- the global sources) without clobbering the other filetype's config.
  --- @param ft string
  --- @return table
  local function existing_sources_for(ft)
    local ok_internal, cmp_config = pcall(require, "cmp.config")
    local ft_config = ok_internal and cmp_config.filetypes and cmp_config.filetypes[ft]
    if ft_config and ft_config.sources then
      return ft_config.sources
    end
    if ok_internal and cmp_config.global and cmp_config.global.sources then
      return cmp_config.global.sources
    end
    if not warned_config_fallback then
      warned_config_fallback = true
      log.warn(
        "nvim-cmp internal config API unavailable; per-filetype sources may be merged from the active buffer's config"
      )
    end
    return cmp.get_config().sources or {}
  end

  local function with_blade_nav_source(sources)
    local merged = { { name = "blade-nav", priority = 1000 } }
    for _, existing_source in ipairs(sources or {}) do
      if existing_source.name ~= "blade-nav" then
        table.insert(merged, existing_source)
      end
    end
    return merged
  end

  cmp.register_source("blade-nav", source.new())
  for _, ft in ipairs({ "blade", "php" }) do
    cmp.setup.filetype(ft, {
      sources = cmp.config.sources(with_blade_nav_source(existing_sources_for(ft))),
    })
  end

  vim.api.nvim_set_hl(0, "CmpItemKindBladeNav", { fg = "#fb503b", default = true })

  log.info("BladeNav nvim-cmp source registered.")
end

return M
