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

    local dst_content = laravel.modify_namespace(src_content, laravel.psr4_app())

    -- Never clobber an existing, divergent BladeNav.php without confirmation
    -- (health already detects divergence via sha256).
    local existing = fs.read_file(dest_path)
    if existing and existing ~= dst_content then
      vim.notify(
        "BladeNav.php already exists with different content; skipping. Remove it manually to reinstall.",
        vim.log.levels.WARN
      )
      return
    end

    -- vim.fn.mkdir returns 0 on failure (it does not throw).
    local mkdir_result = vim.fn.mkdir(vim.fn.fnamemodify(dest_path, ":h"), "p")
    if mkdir_result ~= 1 then
      vim.notify("Error creating directory: " .. vim.fn.fnamemodify(dest_path, ":h"), vim.log.levels.ERROR)
      return
    end

    local ok, dst_err = fs.write_file(dest_path, dst_content)
    if not ok then
      vim.notify("Error writing file: " .. dst_err, vim.log.levels.ERROR)
      return
    end

    vim.notify("BladeNav.php has been copied to app/Console/Commands/", vim.log.levels.INFO)
  end, { desc = "Copy BladeNav.php to app/Console/Commands/BladeNav.php" })
end

return M
