-- lua/blade-nav/core/config.lua

local M = {}
local cache = {}

local schema = {
  enable = "boolean",
  cache_timeout = "number",
  debug = "boolean",
  jsconfig_path = "string",
  laravel_components_paths = "table",
  handlers = "table",
  integrations = "table",
  annotations = "table",
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
  cache_timeout = 50000,
  debug = false,
  jsconfig_path = "./jsconfig.json",
  close_tag_on_complete = true,
  include_routes_in_cmp = true,
  inertia_pages_path = nil,
  inertia_extensions = { "vue", "tsx", "jsx", "ts" },
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
  annotations = {
    show = false,
    hl = "Comment",
    prefix = " ⟶ ",
    max_len = 160,
    debounce_ms = 120,
    show_on_load = true,
    create_keymaps = true,
  },
}

--- Merges user-provided options with defaults and handles legacy global config.
--- This function incorporates logic to read vim.g.blade_nav.laravel_components
--- and vim.g.blade_nav.enable if the modern equivalents are not set in user options.
--- @param user_opts? table User-provided configuration options.
--- @return BladeNavConfig
local function merge_config_with_legacy(user_opts)
  user_opts = user_opts or {}

  local merged_config = vim.deepcopy(default_config)

  merged_config = vim.tbl_deep_extend("force", merged_config, user_opts)

  local legacy_global_config = vim.g.blade_nav
  if type(legacy_global_config) == "table" then
    local legacy_enable = legacy_global_config.enable
    if type(legacy_enable) == "boolean" and user_opts.enable == nil then
      merged_config.enable = legacy_enable
    end

    local legacy_laravel_components = legacy_global_config.laravel_components

    if
        type(legacy_laravel_components) == "table"
        and (not user_opts.laravel_components_paths or vim.tbl_isempty(user_opts.laravel_components_paths))
    then
      merged_config.laravel_components_paths = vim.deepcopy(legacy_laravel_components)
    end
  end

  if type(merged_config.laravel_components_paths) ~= "table" then
    merged_config.laravel_components_paths = {}
  end

  local normalized_paths = {}
  for _, path in ipairs(merged_config.laravel_components_paths) do
    if type(path) == "string" and path ~= "" then
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

  cache.merged = merge_config_with_legacy(user_config)
  validate(cache.merged)
end

--- Get the current configuration.
--- @param key? string Key to retrieve.
--- @return BladeNavConfig|any
function M.get(key)
  if key then
    return cache.merged[key]
  end

  return cache.merged or {}
end

function M.set(key, value)
  cache.merged[key] = value
end

function M.disableDebug()
  cache.merged.debug = false
end

function M.enableDebug()
  cache.merged.debug = true
end

return M
