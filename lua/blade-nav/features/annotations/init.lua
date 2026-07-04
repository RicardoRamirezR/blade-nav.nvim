-- lua/blade-nav/features/annotations/init.lua
-- Orchestrator: delegates to values, renderer, and hover sub-modules.

local M = {}

local values = require("blade-nav.features.annotations.values")
local renderer = require("blade-nav.features.annotations.renderer")
local hover = require("blade-nav.features.annotations.hover")
local debounce = require("blade-nav.utils.debounce")
local log = require("blade-nav.utils.log")

local ns = values.ns
local WEB_FILETYPES = { "php", "blade", "html", "javascript", "vue" }

local DEFAULT_CFG = {
  show = false,
  hl = "Comment",
  prefix = " ⟶ ",
  max_len = 160,
  debounce_ms = 120,
  show_on_load = true,
  create_keymaps = true,
}

local config = {}
local render_debounced
local cancel_render_debounced
local rendered_bufs = {}

local function for_each_web_buffer(cb)
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.tbl_contains(WEB_FILETYPES, vim.bo[b].filetype) then
      cb(b)
    end
  end
end

function M.toggle_show()
  config.show = not config.show
  if config.show then
    for_each_web_buffer(function(b)
      rendered_bufs[b] = true
      renderer.render_buffer(b, true)
    end)
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

-- Apply the buffer-local K keymap and the show_on_load initial render to a
-- single buffer. Used both for buffers loading after setup() (via the
-- FileType autocmd) and for buffers that already matched a web filetype
-- before setup() ran (e.g. when the plugin is lazy-loaded on FileType).
local function apply_to_buffer(bufnr)
  if config.create_keymaps then
    vim.keymap.set("n", "K", M.on_K, { buffer = bufnr, desc = "BladeNav: show config/env value" })
  end
  if config.show_on_load then
    render_debounced(bufnr)
  end
end

function M.setup()
  local core = require("blade-nav.core.config")
  config = vim.tbl_deep_extend("force", vim.deepcopy(DEFAULT_CFG), core.get("annotations") or {})

  renderer.set_config(config)
  hover.set_config(config)
  hover.set_renderer(renderer)

  if cancel_render_debounced then
    cancel_render_debounced()
  end

  render_debounced, cancel_render_debounced = debounce.debounce_per_key(function(buf)
    renderer.render_buffer(buf, true)
  end, config.debounce_ms)

  local grp = vim.api.nvim_create_augroup("BladeNavValues", { clear = true })

  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
    group = grp,
    callback = function(args)
      if
          vim.tbl_contains(WEB_FILETYPES, vim.bo[args.buf].filetype)
          and (config.show_on_load or rendered_bufs[args.buf])
      then
        render_debounced(args.buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "TextChanged", "InsertLeave", "BufWritePost" }, {
    group = grp,
    callback = function(args)
      if vim.tbl_contains(WEB_FILETYPES, vim.bo[args.buf].filetype) then
        rendered_bufs[args.buf] = true
        render_debounced(args.buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd("FileType", {
    group = grp,
    pattern = WEB_FILETYPES,
    callback = function(args)
      apply_to_buffer(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd("BufDelete", {
    group = grp,
    callback = function(args)
      rendered_bufs[args.buf] = nil
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
    callback = function()
      renderer.cleanup_timer()
      if cancel_render_debounced then
        cancel_render_debounced()
      end
    end,
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
    vim.keymap.set("n", "<leader>bv", M.toggle_show, { desc = "BladeNav: toggle show annotations" })
    vim.keymap.set("n", "<leader>bcc", M.clear_cache, { desc = "BladeNav: clear cache" })
  end

  -- Buffers that already matched a web filetype before setup() ran (common
  -- when the plugin itself is lazy-loaded on FileType) never fire the
  -- autocmd above, so apply K + initial render to them retroactively.
  for_each_web_buffer(apply_to_buffer)

  log.debug("BladeNav: annotations setup with: %s", vim.inspect(config))
end

return M
