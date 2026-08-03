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
local toggled_on = false

local K_DESC = "BladeNav: show config/env value"
-- Buffer-local K mappings that predated ours, keyed by bufnr, so the hover
-- fallback can replay them (and filetype cleanup can restore them).
local prev_K_maps = {}
-- Global lhs for which we already notified about a collision (notify once).
local warned_keymap_collisions = {}

-- Mirror of integrations/gf.lua's get_keymap: buffer-local lookup by lhs.
local function get_buf_keymap(mode, lhs, buf)
  for _, keymap in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
    if keymap.lhs == lhs then
      return keymap
    end
  end
end

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
    toggled_on = true
    for_each_web_buffer(function(b)
      rendered_bufs[b] = true
      renderer.render_buffer(b, true)
    end)
    log.debug("Values enabled")
    return
  end

  toggled_on = false
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
    -- Capture any pre-existing buffer-local K before clobbering it, so
    -- hover.on_K can replay it when it has nothing to show (mirrors the
    -- pre-existing-mapping check in integrations/gf.lua). Skip our own
    -- mapping when re-applying so the original capture is kept.
    local existing = get_buf_keymap("n", "K", bufnr)
    if not (existing and existing.desc == K_DESC) then
      prev_K_maps[bufnr] = existing
    end
    vim.keymap.set("n", "K", M.on_K, { buffer = bufnr, desc = K_DESC })
  end
  if config.show_on_load or toggled_on then
    render_debounced(bufnr)
  end
end

-- Undo apply_to_buffer's K mapping when a buffer leaves the web filetypes:
-- delete our mapping and restore the one we captured, if any.
local function remove_K_mapping(bufnr)
  local existing = get_buf_keymap("n", "K", bufnr)
  if existing and existing.desc == K_DESC then
    pcall(vim.keymap.del, "n", "K", { buffer = bufnr })
  end

  local prev = prev_K_maps[bufnr]
  prev_K_maps[bufnr] = nil
  if prev then
    local opts = {
      buffer = bufnr,
      noremap = prev.noremap == 1,
      silent = prev.silent == 1,
      expr = prev.expr == 1,
      desc = prev.desc,
    }
    pcall(vim.keymap.set, "n", "K", prev.callback or prev.rhs, opts)
  end
end

-- Install a global keymap unless the user already mapped something to the
-- same lhs; in that case keep the user's mapping and notify once per lhs.
-- An existing mapping with our own desc is one we installed on an earlier
-- setup() call: silently keep it (re-setup is idempotent, not a collision).
local function set_global_keymap(lhs, rhs, desc)
  local existing = vim.fn.maparg(lhs, "n", false, true)
  if existing and existing.lhs and existing.lhs ~= "" then
    if existing.desc == desc then
      return
    end
    if not warned_keymap_collisions[lhs] then
      warned_keymap_collisions[lhs] = true
      log.warn("BladeNav: '%s' is already mapped; skipping default mapping (%s)", lhs, desc)
    end
    return
  end
  vim.keymap.set("n", lhs, rhs, { desc = desc })
end

function M.setup()
  local core = require("blade-nav.core.config")
  config = vim.tbl_deep_extend("force", vim.deepcopy(DEFAULT_CFG), core.get("annotations") or {})

  renderer.set_config(config)
  hover.set_config(config)
  hover.set_renderer(renderer)
  hover.set_prev_K_lookup(function(bufnr)
    return prev_K_maps[bufnr]
  end)

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
        and (config.show_on_load or toggled_on or rendered_bufs[args.buf])
      then
        render_debounced(args.buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "TextChanged", "InsertLeave", "BufWritePost" }, {
    group = grp,
    callback = function(args)
      -- Annotations hidden: skip entirely. Marking rendered_bufs and arming
      -- the debounce here would only produce a namespace-clearing no-op
      -- timer per edit burst and stale renders on the next BufEnter.
      if not config.show then
        return
      end
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

  -- Buffers whose filetype changes away from the web set must not keep the
  -- buffer-local K we installed.
  vim.api.nvim_create_autocmd("FileType", {
    group = grp,
    callback = function(args)
      if not vim.tbl_contains(WEB_FILETYPES, args.match) then
        remove_K_mapping(args.buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufDelete", {
    group = grp,
    callback = function(args)
      rendered_bufs[args.buf] = nil
      prev_K_maps[args.buf] = nil
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
    set_global_keymap("<leader>bv", M.toggle_show, "BladeNav: toggle show annotations")
    set_global_keymap("<leader>bcc", M.clear_cache, "BladeNav: clear cache")
  end

  -- Buffers that already matched a web filetype before setup() ran (common
  -- when the plugin itself is lazy-loaded on FileType) never fire the
  -- autocmd above, so apply K + initial render to them retroactively.
  for_each_web_buffer(apply_to_buffer)

  log.debug("BladeNav: annotations setup with: %s", vim.inspect(config))
end

return M
