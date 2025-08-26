local fs = require("blade-nav.utils.fs")
local laravel = require("blade-nav.utils.laravel")

local M = {}

--- Install the BladeNav artisan command into app/Console/Commands
function M.install_artisan_command()
  vim.api.nvim_create_user_command("BladeNavInstallArtisanCommand", function()
    local source = laravel.get_blade_nav_filename()
    local root_dir = fs.get_root_dir()
    local dest_dir = root_dir .. "/app/Console/Commands/BladeNav.php"

    local src_content, err = fs.read_file(source)
    if not src_content then
      vim.notify("Error reading file: " .. err, vim.log.levels.ERROR)
      return
    end

    vim.fn.mkdir(vim.fn.fnamemodify(dest_dir, ":h"), "p")

    local dst_content = laravel.modify_namespace(src_content, laravel.psr4_app())
    local ok, dst_err = fs.write_file(dest_dir, dst_content)
    if not ok then
      vim.notify("Error writing file: " .. dst_err, vim.log.levels.ERROR)
      return
    end

    vim.notify("BladeNav.php has been copied to app/Console/Commands/", vim.log.levels.INFO)
  end, { desc = "Copy BladeNav.php to app/Console/Commands/BladeNav.php" })
end

--- Clear BladeNav cache
function M.clear_cache()
  vim.api.nvim_create_user_command("BladeNavClearCache", function()
    require("blade-nav.utils.cache").clear()
    vim.notify("BladeNav cache cleared", vim.log.levels.INFO)
  end, { desc = "Clear all BladeNav plugin cache" })
end

return M
