local M = {}

function M.ftplugin_loader()
  if vim.g.blade_nav and vim.g.blade_nav.enable == false then
    return
  end

  if not vim.g.loaded_blade_nav then
    local ok, blade_nav = pcall(require, "blade-nav")
    if ok and blade_nav then
      local setup_ok, setup_err = pcall(blade_nav.setup)
      if not setup_ok then
        vim.notify("[BladeNav] Setup failed: " .. tostring(setup_err), vim.log.levels.WARN)
      end
    else
      vim.notify("[BladeNav] Failed to load module: " .. tostring(blade_nav), vim.log.levels.ERROR)
    end
    vim.g.loaded_blade_nav = true
  end
end

return M
