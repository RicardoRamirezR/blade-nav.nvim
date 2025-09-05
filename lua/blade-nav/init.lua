-- lua/blade-nav/init.lua

local config = require("blade-nav.core.config")
local gf_integration = require("blade-nav.integrations.gf")
local cmp_integration = require("blade-nav.integrations.cmp")
local blink_integration = require("blade-nav.integrations.blink")
local coq_integration = require("blade-nav.integrations.coq")
local targets = require("blade-nav.targets")
local commands = require("blade-nav.commands")
local annotations = require("blade-nav.annotations.values")

local M = {}

--- Default configuration options for the plugin.
--- This defines the structure and default values.
--- Users can override these via the `setup` function.
--- @class BladeNavConfig
--- @field handlers table<string, boolean> Enable/disable specific target handlers
--- @field integrations table<string, boolean> Enable/disable specific integrations
--- @field debug boolean Enable debug logging
--- @field cache_timeout integer Cache timeout in milliseconds
--- @field close_tag_on_complete boolean For cmp/blink completion
--- @field include_routes_in_cmp boolean For cmp/blink completion
--- @field jsconfig_path string Path for Vue jsconfig
--- @field laravel_components_paths table List of additional component search paths

--- Setup function for BladeNav.
--- This is the primary function users call in their Neovim configuration.
--- It merges user options with defaults, loads handlers, and initializes integrations.
--- @param opts? BladeNavConfig User-provided configuration options.
function M.setup(opts)
  vim.g.blade_nav = vim.tbl_extend("force", vim.g.blade_nav or {}, opts or {})

  local laravel = require("blade-nav.utils.laravel")
  if not vim.g.blade_nav.force_enable and not laravel.is_laravel_project() then
    vim.g.blade_nav.enable = false
    return
  end

  config.setup(opts)
  local user_config = config.get()

  targets.load_handlers("blade-nav.targets", nil, user_config)

  if user_config.integrations.gf ~= false then
    gf_integration.setup()
  end

  if user_config.integrations.cmp ~= false then
    cmp_integration.setup(user_config)
  end

  if user_config.integrations.blink ~= false then
    blink_integration.setup(user_config)
  end

  if user_config.integrations.coq ~= false then
    coq_integration.setup()
  end

  commands.install_artisan_command()
  commands.clear_cache()
  annotations.setup()
end

return M
