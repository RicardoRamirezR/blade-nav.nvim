-- lua/blade-nav/features/annotations/init.lua
-- Orchestrator: delegates to values, renderer, and hover sub-modules.

local M = {}

local values = require("blade-nav.features.annotations.values")
local renderer = require("blade-nav.features.annotations.renderer")
local hover = require("blade-nav.features.annotations.hover")
local debounce = require("blade-nav.utils.debounce")
local log = require("blade-nav.utils.log")

local ns = values.ns
local config = {}
local render_debounced

function M.toggle_show()
  config.show = not config.show
  if config.show then
    renderer.render_buffer(vim.api.nvim_get_current_buf(), true)
    log.debug("Values enabled")
    return
  end

  renderer.clear_queue()

  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) then
      pcall(vim.api.nvim_buf_clear_namespace, b, ns, 0, -1)
    end
  end

  log.debug("Values disabled")
end

function M.refresh(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  renderer.render_buffer(bufnr, true)
end

function M.clear_cache()
  require("blade-nav.utils.cache").clear()
  values.invalidate_maps()
  log.debug("BladeNav: caches cleared")
end

function M.on_K()
  hover.on_K()
end

function M.setup()
  local core = require("blade-nav.core.config")
  local core_cfg = core.get() or {}
  config = core_cfg.annotations

  renderer.set_config(config)
  hover.set_config(config)
  hover.set_renderer(renderer)

  render_debounced = debounce(function(buf)
    renderer.render_buffer(buf, true)
  end, config.debounce_ms or 120)

  local WEB_FILETYPES = { "php", "blade", "html", "javascript", "vue" }
  local grp = vim.api.nvim_create_augroup("BladeNavValues", { clear = true })

  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
    group = grp,
    callback = function(args)
      local ft = vim.bo[args.buf].filetype
      if vim.tbl_contains(WEB_FILETYPES, ft) then
        render_debounced(args.buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "TextChanged", "InsertLeave", "BufWritePost" }, {
    group = grp,
    callback = function(args)
      local ft = vim.bo[args.buf].filetype
      if vim.tbl_contains(WEB_FILETYPES, ft) then
        render_debounced(args.buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufDelete", {
    group = grp,
    callback = function(args)
      local queue = renderer.get_processing_queue()
      for i = #queue, 1, -1 do
        if queue[i].bufnr == args.buf then
          table.remove(queue, i)
        end
      end
    end,
  })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = grp,
    callback = renderer.cleanup_timer,
  })

  vim.api.nvim_create_user_command("BladeNavToggleShowValues", function()
    M.toggle_show()
  end, {
    desc = "Toggle BladeNav config/env annotations in current project",
  })

  vim.api.nvim_create_user_command("BladeNavClearCache", function()
    M.clear_cache()
  end, {
    desc = "Clear BladeNav config/env caches",
  })

  if config.create_keymaps then
    vim.keymap.set("n", "K", M.on_K, { desc = "BladeNav: show config/env value" })
    vim.keymap.set("n", "<leader>bv", M.toggle_show, { desc = "BladeNav: toggle show annotations" })
    vim.keymap.set("n", "<leader>bcc", M.clear_cache, { desc = "BladeNav: clear cache" })
  end

  log.debug("BladeNav: annotations setup with: %s", vim.inspect(config))
end

return M
