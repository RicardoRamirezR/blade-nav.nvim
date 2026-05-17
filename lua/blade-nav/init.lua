-- lua/blade-nav/init.lua

local M = {}

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
--- @param opts? BladeNavConfig User-provided configuration options.
function M.setup(opts)
  vim.g.blade_nav = vim.tbl_extend("force", vim.g.blade_nav or {}, opts or {})

  local laravel = require("blade-nav.utils.laravel")
  if not vim.g.blade_nav.force_enable and not laravel.is_laravel_project() then
    vim.g.blade_nav.enable = false
    return
  end

  local config = require("blade-nav.core.config")
  config.setup(opts)
  local user_config = config.get()

  local targets = require("blade-nav.targets")
  targets.load_handlers("blade-nav.targets", nil, user_config)

  if user_config.integrations.gf ~= false then
    require("blade-nav.integrations.gf").setup()
  end

  if user_config.integrations.cmp ~= false then
    require("blade-nav.integrations.cmp").setup(user_config)
  end

  if user_config.integrations.coq ~= false then
    require("blade-nav.integrations.coq").setup()
  end

  local commands = require("blade-nav.commands")
  commands.install_artisan_command()
  commands.clear_cache()

  require("blade-nav.features.annotations").setup()
end

return M
