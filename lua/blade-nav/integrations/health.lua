-- lua/blade-nav/integrations/health.lua
-- Comprehensive Health Check integration for Neovim's :checkhealth

local fs = require("blade-nav.utils.fs")
local cmd = require("blade-nav.utils.cmd")
local config_module = require("blade-nav.core.config")
local laravel = require("blade-nav.utils.laravel")
local cache = require("blade-nav.utils.cache")

local start = vim.health.start
local ok = vim.health.ok
local warn = vim.health.warn
local error = vim.health.error

local M = {}

--------------------------------------------------------------------------------
-- Environment
--------------------------------------------------------------------------------
local function check_environment()
  start("Environment")

  local version = vim.version()
  ok(string.format("Neovim version: %d.%d.%d", version.major, version.minor, version.patch))
  ok("Operating System: " .. vim.uv.os_uname().sysname)

  local root = fs.get_root_dir()

  if fs.command_exists("php") then
    local php_version = cmd.execute_silent({ "php", "--version" }, { cwd = root }):match("^[^\n]+")
    ok("PHP: " .. (php_version or "unknown version"))
  else
    error("PHP not found in PATH")
  end

  if fs.command_exists("php") then
    local artisan_version = cmd.execute_silent(cmd.artisan_argv({ "--version" }), { cwd = root }):match("^[^\n]+")
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
local function parser_installed(lang)
  local ok_parser = pcall(function()
    vim.treesitter.language.add(lang, { force = false })
  end)
  return ok_parser
end

local function check_treesitter()
  start("Tree-sitter")

  local required_langs = { "php", "blade", "vue", "html" }
  local missing = {}

  for _, lang in ipairs(required_langs) do
    if parser_installed(lang) then
      ok("Parser for '" .. lang .. "' available")
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
  start("External Commands")

  local cmds = { "php", "fd", "find" }
  for _, c in ipairs(cmds) do
    if fs.command_exists(c) then
      ok("'" .. c .. "' available")
    else
      warn("'" .. c .. "' not found in PATH")
    end
  end
end

--------------------------------------------------------------------------------
-- Project structure / Laravel detection
--------------------------------------------------------------------------------
local function check_project_files()
  start("Project Structure")

  local root_dir = fs.get_root_dir()
  if not root_dir or root_dir == "" then
    root_dir = vim.fn.getcwd()
    warn("Could not detect Git root, fallback to cwd: " .. root_dir)
  end

  if laravel.is_laravel_project(root_dir) then
    ok("Laravel project detected at " .. root_dir)
  else
    ok("Root directory: " .. root_dir)
    warn("Laravel heuristics failed: project may not be a Laravel app")
  end

  if vim.uv.fs_stat(root_dir .. "/composer.json") then
    ok("composer.json found")
  else
    error("Missing composer.json")
  end
  if vim.uv.fs_stat(root_dir .. "/resources/views") then
    ok("resources/views directory exists")
  else
    error("Missing resources/views directory")
  end

  if vim.uv.fs_stat(root_dir .. "/vendor/composer/autoload_psr4.php") then
    ok("vendor/composer/autoload_psr4.php found")
  else
    error("Missing vendor/composer/autoload_psr4.php")
  end
end

--------------------------------------------------------------------------------
-- BladeNav artisan command
--------------------------------------------------------------------------------
local function check_blade_command()
  start("BladeNav Artisan Command")

  ok("Purpose: provides component aliases from external packages via `blade-nav:components-aliases`")

  local root = fs.get_root_dir()
  local output, ok_cmd = cmd.execute_silent(cmd.artisan_argv({ "--format=json" }), { cwd = root })
  if not ok_cmd then
    warn("Cannot run `php artisan` to detect commands " .. output)
    return
  end

  local ok_decode, decoded = pcall(vim.fn.json_decode, output)
  if not ok_decode or type(decoded) ~= "table" then
    warn("Could not parse `php artisan --format=json` output: " .. tostring(decoded))
    return
  end

  local found = false
  for _, command in ipairs(decoded.commands or {}) do
    if command.name == "blade-nav:components-aliases" then
      ok("'blade-nav:components-aliases' command is installed")
      found = true
      break
    end
  end

  if not found then
    ok("'blade-nav:components-aliases' not installed (optional)")
    return
  end

  local source = laravel.get_blade_nav_filename()
  local local_blade, err = fs.read_file(source)
  if not local_blade then
    warn("Could not read BladeNav.php source: " .. err)
    return
  end
  local_blade = laravel.modify_namespace(local_blade, laravel.psr4_app())

  local file, file_err = fs.read_file(root .. "/app/Console/Commands/BladeNav.php")
  if not file then
    warn("BladeNav.php not found in app/Console/Commands/: " .. file_err)
    return
  end

  if vim.fn.sha256(local_blade) ~= vim.fn.sha256(file) then
    warn("BladeNav.php is outdated. Run :BladeNavInstallArtisanCommand to refresh it.")
  else
    ok("BladeNav.php is up to date")
  end
end

--------------------------------------------------------------------------------
-- Configuration validation
--------------------------------------------------------------------------------
local function check_config()
  start("Configuration")

  local config = config_module.get()
  ok("BladeNav configuration loaded")

  if config.laravel_components_paths and #config.laravel_components_paths > 0 then
    ok("Extra component search paths: " .. table.concat(config.laravel_components_paths, ", "))
  end

  if config.inertia_pages_path then
    ok("Inertia pages path override: " .. config.inertia_pages_path)
  end

  if config.inertia_extensions then
    ok("Inertia extensions: " .. table.concat(config.inertia_extensions, ", "))
  end

  ok("Cache timeout: " .. tostring(config.cache_timeout) .. "ms")
  ok("Debug: " .. tostring(config.debug))
end

--------------------------------------------------------------------------------
-- Integrations
--------------------------------------------------------------------------------
local function check_integrations()
  start("Integrations")

  local cfg = config_module.get()
  local engines = {
    cmp = "cmp",
    blink = "blink.cmp",
    coq = "coq",
  }

  local enabled, available = {}, {}
  for name, require_path in pairs(engines) do
    if cfg.integrations[name] then
      table.insert(enabled, name)
      local ok_mod, _ = pcall(require, require_path)
      if ok_mod then
        table.insert(available, name)
      end
    end
  end

  if #enabled == 0 then
    ok("No completion engine enabled")
    return
  end

  ok("Enabled engines: " .. table.concat(enabled, ", "))

  if #available > 0 then
    ok("Available engine(s): " .. table.concat(available, ", "))
  else
    warn("No enabled completion engine is available (not installed)")
  end
end

--------------------------------------------------------------------------------
-- Routes
--------------------------------------------------------------------------------
local function check_routes()
  start("Routes")

  cache.clear("route_list:route_name")

  local start_time = vim.uv.hrtime()
  local ok1, routes1 = pcall(laravel.get_route_names)
  local elapsed1 = (vim.uv.hrtime() - start_time) / 1e6

  if ok1 and routes1 and #routes1 > 0 then
    ok(string.format("Cold: %d routes in %.2f ms", #routes1, elapsed1))
  else
    warn("Cold route load failed")
  end

  local start_time2 = vim.uv.hrtime()
  local ok2, routes2 = pcall(laravel.get_route_names)
  local elapsed2 = (vim.uv.hrtime() - start_time2) / 1e6

  if ok2 and routes2 and #routes2 > 0 then
    ok(string.format("Warm: %d routes in %.2f ms (cache)", #routes2, elapsed2))
  else
    warn("Warm route load failed")
  end
end

--------------------------------------------------------------------------------
-- Views
--------------------------------------------------------------------------------
local function check_views()
  start("Views")

  cache.clear("view_list")

  local start_time = vim.uv.hrtime()
  local ok1, views1 = pcall(laravel.__health_check_views)
  local elapsed1 = (vim.uv.hrtime() - start_time) / 1e6

  if ok1 and views1 and #views1 > 0 then
    ok(string.format("Cold: %d views in %.2f ms", #views1, elapsed1))
  else
    warn("Cold view load failed")
  end

  local start_time2 = vim.uv.hrtime()
  local ok2, views2 = pcall(laravel.__health_check_views)
  local elapsed2 = (vim.uv.hrtime() - start_time2) / 1e6

  if ok2 and views2 and #views2 > 0 then
    ok(string.format("Warm: %d views in %.2f ms (cache)", #views2, elapsed2))
  else
    warn("Warm view load failed")
  end
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------
function M.check()
  start("BladeNav Health Check")

  if vim.fn.has("nvim-0.11") == 0 then
    error("blade-nav requires Neovim >= 0.11")
    return
  end

  ok("BladeNav plugin loaded")

  check_environment()
  check_treesitter()
  check_external_commands()
  check_project_files()
  check_blade_command()
  check_config()
  check_integrations()
  check_routes()
  check_views()
end

return M
