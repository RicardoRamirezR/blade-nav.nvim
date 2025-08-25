-- lua/blade-nav/init.lua

-- Import required core modules
local config = require("blade-nav.core.config")                   -- Handles plugin configuration
local gf_integration = require("blade-nav.integrations.gf")       -- Handles the `gf` mapping
local cmp_integration = require("blade-nav.integrations.cmp")     -- Handles nvim-cmp integration
local blink_integration = require("blade-nav.integrations.blink") -- Handles blink.cmp integration
local coq_integration = require("blade-nav.integrations.coq")     -- Handles coq.nvim integration
local targets = require("blade-nav.targets")                      -- Handles target handler loading/registration
local commands = require("blade-nav.commands")

-- Define the main module table
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

  -- 1. Load and merge user configuration with defaults
  -- This updates the global configuration state managed by core/config.lua
  config.setup(opts)               -- Pass defaults and user opts
  local user_config = config.get() -- Get the final merged config

  -- 2. Load built-in target handlers dynamically
  -- This discovers and registers all built-in target modules (view.lua, route.lua, etc.)
  -- It respects the `config.handlers` table to potentially skip loading disabled handlers.
  -- It uses the configuration to determine which handlers to load/register.
  targets.load_handlers("blade-nav.targets", nil, user_config) -- nil lets load_handlers derive path

  -- 3. Apply configuration to enable/disable loaded handlers (if load_handlers doesn't do it fully)
  -- This step ensures that even if a handler was loaded, it's only active if config says so.
  -- targets.apply_config(user_config) -- Uncomment if separate apply step is needed/desired

  -- 4. Setup integrations
  -- Initialize each integration module, passing the final configuration so they
  -- can check if they are enabled and configure themselves accordingly.

  -- Setup `gf` integration if enabled
  if user_config.integrations.gf ~= false then
    gf_integration.setup()
  else
    -- Log or handle if gf is explicitly disabled
  end

  -- Setup `cmp` integration if enabled
  if user_config.integrations.cmp ~= false then
    cmp_integration.setup(user_config) -- Pass config for specific settings like close_tag
  else
    -- Log or handle if cmp is explicitly disabled
  end

  -- Setup `blink` integration if enabled
  if user_config.integrations.blink ~= false then
    blink_integration.setup(user_config) -- Pass config
  else
    -- Log or handle if blink is explicitly disabled
  end

  -- Setup `coq` integration if enabled
  if user_config.integrations.coq ~= false then
    coq_integration.setup() -- Coq setup might not need specific config
  else
    -- Log or handle if coq is explicitly disabled
  end

  -- Future integrations can be added similarly
  -- if user_config.integrations.some_new_integration ~= false then
  --     require("blade-nav.integrations.some_new_integration").setup(user_config)
  -- end

  -- 5. Any other global setup or state initialization can happen here
  -- (e.g., setting up autocommands that aren't specific to an integration)

  -- Indicate successful setup
  -- print("[BladeNav] Setup completed.")
  commands.install_artisan_command()
  commands.clear_cache()
end

-- Return the module table so it can be required and used
return M
