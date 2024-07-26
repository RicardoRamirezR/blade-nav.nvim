local utils = require("blade-nav.utils")

local M = {}

local start = vim.health.start or vim.health.report_start
local ok = vim.health.ok or vim.health.report_ok
local warn = vim.health.warn or vim.health.report_warn
local error = vim.health.error or vim.health.report_error

--- Check if BladeNav.php has been modified
local function blade_command_sync()
  local source = utils.get_blade_nav_filename()
  local local_blade, err = utils.read_file(source)

  if not local_blade then
    error("Error reading file: " .. err)
    return
  end

  local_blade = utils.modify_namespace(local_blade, utils.psr4_app())

  local file, file_err = utils.read_file("app/Console/Commands/BladeNav.php")
  if not file then
    error("Error reading file: " .. file_err)
    return
  end

  if vim.fn.sha256(local_blade) ~= vim.fn.sha256(file) then
    warn('File "app/Console/Commands/BladeNav.php" needs to be updated')
  end
end

local function check_blade_command()
  local result = utils.execute_command_silent({ "php", "artisan", "--format=json" })
  if result == "" then
    error("Cannot run artisan")
    warn("Blade command components-aliases cannot be checked")
    return
  end

  result = vim.fn.json_decode(result)
  for _, command in ipairs(result.commands) do
    if command.name == "blade-nav:components-aliases" then
      ok("Blade command blade-nav:components-aliases")
      blade_command_sync()
      return
    end
  end

  warn(
    "Blade command components-aliases not found\n" .. "to install it run the Ex command BladeNavInstallArtisanCommand"
  )
end

local function check_setup()
  local fd = utils.command_exists("fd")
  local find = utils.command_exists("find")
  local php = utils.command_exists("php")

  if jit then
    print("Operating System: " .. jit.os)
  else
    print("jit is not available")
  end

  ok("Operating System: " .. vim.loop.os_uname().sysname)

  if find then
    if not fd then
      ok("Command find found and will be used\n")
    end
  end

  if php then
    local version = utils.explode("\n", vim.fn.system("php --version"))
    ok(version[1])
  else
    error("Command PHP does not exist")
  end

  if php then
    local version = utils.explode("\n", vim.fn.system("php artisan --version"))
    ok(version[1])
  else
    error("Artisan command not found")
  end

  if php then
    check_blade_command()
  end

  local f = io.open("composer.json", "r")
  if f then
    f:close()
    ok("composer.json")
  else
    error("Missing composer.json")
  end

  local stat = vim.loop.fs_stat("resources/views")
  if stat and stat.type == "directory" then
    ok("resources/views")
  else
    error("Missing resources/views directory")
  end

  f = io.open("./vendor/composer/autoload_psr4.php")
  if f then
    f:close()
    ok("vendor/composer/autoload_psr4.php")
  else
    error("Missing vendor/composer/autoload_psr4.php")
  end

  local root_dir = utils.get_root_dir()
  if root_dir and root_dir ~= "" then
    ok("Git repository found")
  else
    warn("Git repository not found")
  end
end

M.check = function()
  start("Blade Nav health check started")

  check_setup()
end

return M
