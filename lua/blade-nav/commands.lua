local fs = require("blade-nav.utils.fs")
local laravel = require("blade-nav.utils.laravel")

local M = {}

function M.install_artisan_command()
  vim.api.nvim_create_user_command("BladeNavInstallArtisanCommand", function()
    local source = laravel.get_blade_nav_filename()
    local root_dir = fs.get_root_dir()
    local dest_path = root_dir .. "/app/Console/Commands/BladeNav.php"

    local src_content, err = fs.read_file(source)
    if not src_content then
      vim.notify("Error reading file: " .. err, vim.log.levels.ERROR)
      return
    end

    local mkdir_ok, mkdir_err = pcall(vim.fn.mkdir, vim.fn.fnamemodify(dest_path, ":h"), "p")
    if not mkdir_ok then
      vim.notify("Error creating directory: " .. tostring(mkdir_err), vim.log.levels.ERROR)
      return
    end

    local dst_content = laravel.modify_namespace(src_content, laravel.psr4_app())
    local ok, dst_err = fs.write_file(dest_path, dst_content)
    if not ok then
      vim.notify("Error writing file: " .. dst_err, vim.log.levels.ERROR)
      return
    end

    vim.notify("BladeNav.php has been copied to app/Console/Commands/", vim.log.levels.INFO)
  end, { desc = "Copy BladeNav.php to app/Console/Commands/BladeNav.php" })
end

return M
