-- lua/blade-nav/integrations/health.lua
-- Comprehensive Health Check integration for Neovim's :checkhealth

local fs = require("blade-nav.utils.fs")
local cmd = require("blade-nav.utils.cmd")
local log = require("blade-nav.utils.log")
local config_module = require("blade-nav.core.config")
local laravel = require("blade-nav.utils.laravel")
local cache = require("blade-nav.utils.cache")

-- Use Neovim's health reporting functions (backward compatible)
local start = vim.health.start or vim.health.report_start
local ok = vim.health.ok or vim.health.report_ok
local warn = vim.health.warn or vim.health.report_warn
local error = vim.health.error or vim.health.report_error

local M = {}

--------------------------------------------------------------------------------
-- Environment
--------------------------------------------------------------------------------
local function check_environment()
  local version = vim.version()
  ok(string.format("Neovim version: %d.%d.%d", version.major, version.minor, version.patch))
  ok("Operating System: " .. vim.loop.os_uname().sysname)

  if fs.command_exists("php") then
    local php_version = vim.fn.system("php --version"):match("^[^\n]+")
    ok("PHP: " .. (php_version or "unknown version"))
  else
    error("PHP not found in PATH")
  end

  if fs.command_exists("php") then
    local artisan_version = vim.fn.system("php artisan --version"):match("^[^\n]+")
    if artisan_version and artisan_version ~= "" then
      ok("Artisan: " .. artisan_version)
    else
      warn("Cannot run `php artisan --version`")
    end
  end
end

--------------------------------------------------------------------------------
-- Tree-sitter
--------------------------------------------------------------------------------
local function check_treesitter()
  local ts_status, ts_parsers = pcall(require, "nvim-treesitter.parsers")
  if not ts_status then
    error("nvim-treesitter not available")
    return
  end

  local required_langs = { "php", "blade" }
  local missing = {}
  for _, lang in ipairs(required_langs) do
    if ts_parsers.has_parser(lang) then
      ok("Tree-sitter parser for '" .. lang .. "' is installed")
    else
      table.insert(missing, lang)
    end
  end

  if #missing > 0 then
    warn(
      "Missing parsers: " .. table.concat(missing, ", ") .. ". Install with :TSInstall " .. table.concat(missing, " ")
    )
  end
end

--------------------------------------------------------------------------------
-- External Commands
--------------------------------------------------------------------------------
local function check_external_commands()
  local cmds = { "php", "fd", "find" }
  local missing = {}

  for _, c in ipairs(cmds) do
    if fs.command_exists(c) then
      ok("External command '" .. c .. "' available")
    else
      table.insert(missing, c)
    end
  end

  if #missing > 0 then
    warn("Missing external commands: " .. table.concat(missing, ", "))
  end
end

--------------------------------------------------------------------------------
-- Project structure
--------------------------------------------------------------------------------
local function check_project_files()
  if vim.loop.fs_stat("composer.json") then
    ok("composer.json found")
  else
    error("Missing composer.json")
  end

  if vim.loop.fs_stat("resources/views") then
    ok("resources/views directory exists")
  else
    error("Missing resources/views directory")
  end

  if vim.loop.fs_stat("vendor/composer/autoload_psr4.php") then
    ok("vendor/composer/autoload_psr4.php found")
  else
    error("Missing vendor/composer/autoload_psr4.php")
  end

  local root_dir, is_ok = laravel.get_root_dir()
  print("Root dir: " .. root_dir, is_ok)
  if is_ok and root_dir and root_dir ~= "" then
    ok("Git repository found at " .. root_dir)
  else
    warn("Git repository not detected")
  end
end

--------------------------------------------------------------------------------
-- BladeNav artisan command
--------------------------------------------------------------------------------
local function check_blade_command()
  local result = cmd.execute_silent({ "php", "artisan", "--format=json" })
  if result == "" then
    warn("Cannot run `php artisan`. BladeNav artisan command cannot be checked.")
    return
  end

  local decoded = vim.fn.json_decode(result)
  local found = false
  for _, command in ipairs(decoded.commands or {}) do
    if command.name == "blade-nav:components-aliases" then
      ok("BladeNav artisan command 'blade-nav:components-aliases' available")
      found = true
      break
    end
  end

  if not found then
    warn("BladeNav artisan command not found. Run :BladeNavInstallArtisanCommand to install it.")
    return
  end

  -- Compare installed BladeNav.php with local source
  local source = laravel.get_blade_nav_filename()
  local local_blade, err = laravel.read_file(source)
  if not local_blade then
    warn("Could not read BladeNav.php source: " .. err)
    return
  end
  local_blade = laravel.modify_namespace(local_blade, laravel.psr4_app())

  local file, file_err = fs.read_file("app/Console/Commands/BladeNav.php")
  if not file then
    warn("BladeNav.php not found in app/Console/Commands/: " .. file_err)
    return
  end

  if vim.fn.sha256(local_blade) ~= vim.fn.sha256(file) then
    warn("BladeNav.php in app/Console/Commands/ is outdated. Run :BladeNavInstallArtisanCommand to refresh it.")
  else
    ok("BladeNav.php is up to date")
  end
end

--------------------------------------------------------------------------------
-- Configuration validation
--------------------------------------------------------------------------------
local function check_config()
  local config = config_module.get()
  ok("BladeNav configuration loaded")

  if vim.g.blade_nav and vim.g.blade_nav.laravel_components then
    local paths = vim.g.blade_nav.laravel_components
    local suffix = #paths > 1 and "s" or ""
    ok("Additional search path" .. suffix .. " for Laravel components: " .. table.concat(paths, ", "))
  end

  if vim.g.blade_nav and vim.g.blade_nav.include_routes ~= nil then
    if type(vim.g.blade_nav.include_routes) ~= "boolean" then
      warn("include_routes should be boolean")
    else
      ok("include_routes = " .. tostring(vim.g.blade_nav.include_routes))
    end
  end
end

--------------------------------------------------------------------------------
-- Integrations
--------------------------------------------------------------------------------
local function check_integrations()
  local cfg = config_module.get()

  local function check(name, require_path)
    if cfg.integrations[name] then
      local ok_mod, _ = pcall(require, require_path)
      if ok_mod then
        ok(name .. " integration enabled and available")
      else
        warn(name .. " integration enabled but not installed")
      end
    else
      ok(name .. " integration disabled")
    end
  end

  check("cmp", "cmp")
  check("blink", "blink.cmp")
  check("coq", "coq")
  if cfg.integrations.health then
    ok("Health integration enabled")
  end
end

--------------------------------------------------------------------------------
-- Routes
--------------------------------------------------------------------------------
local function check_routes()
  -- Clear cache before cold load
  cache.clear("route_list:route_name")

  local start_time = vim.loop.hrtime()
  local ok1, routes1 = pcall(laravel.get_route_names)
  local elapsed1 = (vim.loop.hrtime() - start_time) / 1e6 -- ms

  if ok1 and routes1 and #routes1 > 0 then
    ok(string.format("Cold route load: %d routes in %.2f ms", #routes1, elapsed1))
  else
    warn("Cold route load failed")
  end

  -- Warm load
  local start_time2 = vim.loop.hrtime()
  local ok2, routes2 = pcall(laravel.get_route_names)
  local elapsed2 = (vim.loop.hrtime() - start_time2) / 1e6 -- ms

  if ok2 and routes2 and #routes2 > 0 then
    ok(string.format("Warm route load: %d routes in %.2f ms", #routes2, elapsed2))
  else
    warn("Warm route load failed")
  end
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------
function M.check()
  start("BladeNav Health Check")

  ok("BladeNav plugin loaded")

  check_environment()
  check_treesitter()
  check_external_commands()
  check_project_files()
  check_blade_command()
  check_config()
  check_integrations()
  check_routes()
end

return M
