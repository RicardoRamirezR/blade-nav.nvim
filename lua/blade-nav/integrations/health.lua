-- lua/blade-nav/integrations/health.lua
-- Integration for Neovim's :checkhealth feature.

local utils = require("blade-nav.utils")               -- Assuming general utils exist
local log = require("blade-nav.utils.log")             -- Assuming logging exists
local config_module = require("blade-nav.core.config") -- Assuming core config

-- Use Neovim's health reporting functions (fallbacks for older versions)
local start = vim.health.start or vim.health.report_start
local ok = vim.health.ok or vim.health.report_ok
local warn = vim.health.warn or vim.health.report_warn
local error = vim.health.error or vim.health.report_error

local M = {}

-- Check if the required Tree-sitter parsers are available
local function check_treesitter_parsers()
  local ts_status, ts_parsers = pcall(require, "nvim-treesitter.parsers")
  if not ts_status then
    error("nvim-treesitter is not available or failed to load.")
    return
  end

  local required_langs = { "php", "blade" } -- Add "vue" if Vue support is relevant
  local missing_parsers = {}

  for _, lang in ipairs(required_langs) do
    if ts_parsers.has_parser(lang) then
      ok(string.format("Tree-sitter parser for '%s' is installed.", lang))
    else
      table.insert(missing_parsers, lang)
    end
  end

  if #missing_parsers > 0 then
    warn(
      string.format(
        "Missing Tree-sitter parsers: %s. Install using :TSInstall %s",
        table.concat(missing_parsers, ", "),
        table.concat(missing_parsers, " ")
      )
    )
  end
end

-- Check if external commands are available
local function check_external_commands()
  local required_commands = { "php" } -- Add "fd", "find" if used for file discovery
  local missing_commands = {}

  for _, cmd in ipairs(required_commands) do
    if utils.fs.command_exists(cmd) then -- Assuming fs.command_exists exists
      ok(string.format("External command '%s' is available.", cmd))
    else
      table.insert(missing_commands, cmd)
    end
  end

  if #missing_commands > 0 then
    warn(string.format("Missing external commands: %s. Please install them.", table.concat(missing_commands, ", ")))
  end
end

-- Check configuration options
local function check_configuration()
  local config = config_module.get() -- Get current config
  ok("BladeNav configuration loaded successfully.")

  -- Example: Check a specific config option
  -- if config.some_option ~= nil then
  --     ok(string.format("Configuration option 'some_option' is set to: %s", tostring(config.some_option)))
  -- else
  --     warn("Configuration option 'some_option' is not set, using default.")
  -- end

  -- Add more checks for specific config values if needed
end

-- Check integration availability
local function check_integrations()
  local config = config_module.get()

  -- Check cmp
  if config.integrations.cmp then
    local has_cmp, _ = pcall(require, "cmp")
    if has_cmp then
      ok("nvim-cmp integration is enabled and nvim-cmp is available.")
    else
      warn("nvim-cmp integration is enabled but nvim-cmp plugin not found.")
    end
  else
    ok("nvim-cmp integration is disabled.")
  end

  -- Check blink
  if config.integrations.blink then
    local has_blink, _ = pcall(require, "blink.cmp")
    if has_blink then
      ok("blink.cmp integration is enabled and blink.cmp is available.")
    else
      warn("blink.cmp integration is enabled but blink.cmp plugin not found.")
    end
  else
    ok("blink.cmp integration is disabled.")
  end

  -- Check coq
  if config.integrations.coq then
    local has_coq, _ = pcall(require, "coq")
    if has_coq then
      ok("coq.nvim integration is enabled and coq.nvim is available.")
    else
      warn("coq.nvim integration is enabled but coq.nvim plugin not found.")
    end
  else
    ok("coq.nvim integration is disabled.")
  end

  -- Check health itself (this file)
  if config.integrations.health then
    ok("Health check integration is enabled.")
  else
    -- This is contradictory, but just for completeness based on config structure
    warn("Health check integration is disabled (but running now).")
  end
end

-- Main check function called by :checkhealth
function M.check()
  start("BladeNav Health Check")

  ok("BladeNav plugin loaded successfully.")

  check_configuration()
  check_treesitter_parsers()
  check_external_commands()
  check_integrations()

  -- Add more checks as needed (e.g., cache directory writable, artisan command accessible)
end

-- Setup function (might be used to register the health check source or perform initial checks)
function M.setup()
  -- In Neovim, health checks are typically found automatically if placed in plugin/health.lua
  -- or if a function named `check` is exported from a module in the plugin structure.
  -- Registering might not be strictly necessary, but we can log that setup ran.
  log.debug("BladeNav health integration setup called.")
  -- If specific setup is needed (e.g., creating autocommands related to health), do it here.
end

return M
