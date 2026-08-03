local M = {}

local checked_roots = {}

function M.ftplugin_loader()
  if vim.g.blade_nav and vim.g.blade_nav.enable == false then
    return
  end

  if vim.g.loaded_blade_nav then
    return
  end

  local laravel_ok, laravel = pcall(require, "blade-nav.utils.laravel")
  if laravel_ok then
    local cfg = vim.g.blade_nav or {}
    if not cfg.force_enable then
      local fs_ok, fs = pcall(require, "blade-nav.utils.fs")
      local root = fs_ok and fs.get_root_dir() or nil

      if root and checked_roots[root] == false then
        return
      end

      local is_laravel = laravel.is_laravel_project(root)
      if root then
        checked_roots[root] = is_laravel
      end

      if not is_laravel then
        return
      end
    end
  end

  local req_ok, blade_nav = pcall(require, "blade-nav")
  if req_ok and blade_nav then
    local setup_ok, setup_err = pcall(blade_nav.setup)
    if not setup_ok then
      vim.notify("[BladeNav] Setup failed: " .. tostring(setup_err), vim.log.levels.WARN)
      -- Do not latch vim.g.loaded_blade_nav on failure: allow retry later.
      return
    end
  else
    vim.notify("[BladeNav] Failed to load module: " .. tostring(blade_nav), vim.log.levels.ERROR)
    -- Do not latch vim.g.loaded_blade_nav on failure: allow retry later.
    return
  end
  vim.g.loaded_blade_nav = true
end

return M
