-- lua/blade-nav/core/config.lua

-- local log = require("blade-nav.utils.log")

local M = {}
local cache = {} -- Simple cache for the merged config

local schema = {
  enable = "boolean",
  cache_timeout = "number",
  debug = "boolean",
  jsconfig_path = "string",
  laravel_components_paths = "table",
  handlers = "table",
  integrations = "table",
}

local function validate(config)
  for key, expected in pairs(schema) do
    local val = config[key]
    if val ~= nil and type(val) ~= expected then
      vim.notify(
        string.format("[BladeNav] Invalid config: '%s' expected %s but got %s", key, expected, type(val)),
        vim.log.levels.WARN
      )
    end
  end
end

-- @class BladeNavConfig
-- @field cache_timeout integer Timeout for cached data in milliseconds (default: 5000)
-- @field debug boolean Enable debug logging (default: false)
-- @field jsconfig_path string Path to jsconfig.json (default: "./jsconfig.json")
-- @field laravel_components_paths table List of additional component search paths (default: {})
-- @field handlers table<string, boolean> Enable/disable specific target handlers
-- @field integrations table<string, boolean> Enable/disable specific integrations

--- Default configuration options for the plugin.
--- @type BladeNavConfig
local default_config = {
  enable = true,
  cache_timeout = 50000, -- 5 seconds
  debug = false,
  jsconfig_path = "./jsconfig.json",
  close_tag_on_complete = true,
  include_routes_in_cmp = true,
  laravel_components_paths = {},
  handlers = {
    directive = true,
    view = true,
    livewire = true,
    route = true,
    config = true,
    component = true,
    inertia = true,
    vue = true,
  },
  integrations = {
    blink = true,
    cmp = true,
    coq = true,
    gf = true,
    health = true,
  },
}

--- Merges user-provided options with defaults and handles legacy global config.
--- This function incorporates logic to read vim.g.blade_nav.laravel_components
--- and vim.g.blade_nav.enable if the modern equivalents are not set in user options.
--- @param user_opts? table User-provided configuration options.
--- @return BladeNavConfig
local function merge_config_with_legacy(user_opts)
  user_opts = user_opts or {}

  -- Start with the default configuration
  local merged_config = vim.deepcopy(default_config)

  -- 1. Merge user-provided options on top of defaults
  -- This handles the standard setup({ ... }) call
  merged_config = vim.tbl_deep_extend("force", merged_config, user_opts)

  -- 2. Handle Legacy Global Config Fallback (vim.g.blade_nav)
  -- Check if vim.g.blade_nav exists and is a table
  local legacy_global_config = vim.g.blade_nav
  if type(legacy_global_config) == "table" then
    -- >>>>>>>>>> ADDED: Check for global 'enable' flag <<<<<<<<<<
    -- If the user did NOT provide 'enable' in setup({...})
    -- AND the legacy 'enable' is a boolean, use it.
    local legacy_enable = legacy_global_config.enable
    if type(legacy_enable) == "boolean" and user_opts.enable == nil then
      merged_config.enable = legacy_enable
      -- Log this application if debug is enabled in *default* config
      -- (since user config might not be fully merged yet for their debug setting)
      if default_config.debug then
        -- log.debug("[BladeNav Debug] Applied legacy global enable flag: %s", tostring(legacy_enable))
      end
    end
    -- >>>>>>>>>> END ADDED <<<<<<<<<<

    -- Check specifically for the legacy 'laravel_components' key
    local legacy_laravel_components = legacy_global_config.laravel_components

    -- If the user did NOT provide 'laravel_components_paths' in setup({...})
    -- AND the legacy 'laravel_components' is a table, use it as the default.
    -- This prioritizes the new config option if explicitly set.
    if
        type(legacy_laravel_components) == "table"
        and (not user_opts.laravel_components_paths or vim.tbl_isempty(user_opts.laravel_components_paths))
    then
      merged_config.laravel_components_paths = vim.deepcopy(legacy_laravel_components)
      if merged_config.debug then
        print("[BladeNav Debug] Applied legacy global laravel_components_paths.")
      end
    end

    -- Add similar logic for other legacy global options if needed
    -- Example for a hypothetical 'include_routes':
    -- local legacy_include_routes = legacy_global_config.include_routes
    -- if type(legacy_include_routes) == "boolean" and user_opts.include_routes == nil then
    --     merged_config.include_routes = legacy_include_routes
    -- end
  end

  -- 3. Ensure laravel_components_paths is always a table
  if type(merged_config.laravel_components_paths) ~= "table" then
    merged_config.laravel_components_paths = {}
  end

  -- 4. Normalize paths in laravel_components_paths (ensure trailing slash)
  local normalized_paths = {}
  for _, path in ipairs(merged_config.laravel_components_paths) do
    if type(path) == "string" and path ~= "" then
      -- Remove trailing slashes and add one back for consistency
      local normalized_path = path:gsub("/+$", "") .. "/"
      table.insert(normalized_paths, normalized_path)
    end
  end
  merged_config.laravel_components_paths = normalized_paths

  return merged_config
end

--- Setup and merge user configuration.
--- @param user_config? BladeNavConfig User provided configuration options.
function M.setup(user_config)
  if cache.merged then
    return cache.merged
  end
  -- Use the new merging function that includes legacy support
  cache.merged = merge_config_with_legacy(user_config)
  validate(cache.merged)
end

--- Get the current configuration.
--- @return BladeNavConfig|string
function M.get(key, value)
  if key and value then
    cache.merged[key] = value
  end
  if key then
    return cache.merged[key]
  end
  -- Return the cached merged configuration
  return cache.merged or {}
end

function M.set(key, value)
  print("Set " .. key .. " to " .. value, cache.merged[key])
  cache.merged[key] = value
  print("Set " .. key .. " to " .. value, cache.merged[key])
end

function M.enableDebug()
  cache.merged.debug = true
end

return M
