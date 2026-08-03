-- lua/blade-nav/integrations/gf.lua

local targets = require("blade-nav.targets")
local context_creator = require("blade-nav.core.context")
local log = require("blade-nav.utils.log")

local M = {}
local registered = false

local GF_DESC = "BladeNav: Enhanced go-to file under cursor"
local GF_FILETYPES = { "blade", "php", "vue" }

--- Gets a keymap for the given lhs in a mode.
--- @param mode string The mode (e.g., "n" for normal).
--- @param lhs string The left-hand side of the mapping (e.g., "gf").
--- @param buf? integer Buffer handle; when given, look up a buffer-local mapping.
--- @return table|nil The keymap table or nil if not found.
local function get_keymap(mode, lhs, buf)
  local keymaps = buf and vim.api.nvim_buf_get_keymap(buf, mode) or vim.api.nvim_get_keymap(mode)
  for _, keymap in ipairs(keymaps) do
    if keymap.lhs == lhs then
      return keymap
    end
  end
end

--- Executes the native Neovim `gf` command.
--- Looks up the user's global `gf` mapping at invocation time and uses it if it
--- exists (calling a Lua `callback` directly, or feeding a string `rhs` with
--- remap so mappings referenced by the rhs, e.g. `<Plug>(...)`, still expand),
--- otherwise falls back to the built-in `gf`.
local function gf_native()
  local gf_mapping = get_keymap("n", "gf")

  if gf_mapping and gf_mapping.callback then
    gf_mapping.callback()
  elseif gf_mapping and type(gf_mapping.rhs) == "string" then
    local rhs = vim.api.nvim_replace_termcodes(gf_mapping.rhs, true, true, true)
    vim.api.nvim_feedkeys(rhs, "m", false)
  else
    pcall(vim.cmd, "silent! normal! gf")
  end
end

--- Main `gf` handler function.
--- Creates context and delegates resolution to the targets system.
function M.gf()
  log.debug("BladeNav gf handler invoked.")

  local context = context_creator.create()
  local resolved = targets.resolve_target(context)

  if not resolved then
    log.debug("No BladeNav target resolved or action taken, falling back to native gf.")
    gf_native()
  else
    log.debug("BladeNav target resolution process completed (action may have been taken).")
  end
end

--- Sets the buffer-local `gf` mapping for a single buffer, unless a
--- pre-existing buffer-local `gf` mapping belongs to someone else (respected
--- and left untouched).
--- @param buf integer Buffer handle.
local function apply_gf_mapping(buf)
  if vim.b[buf].blade_nav_gf then
    return
  end
  vim.b[buf].blade_nav_gf = true

  local existing = get_keymap("n", "gf", buf)
  if existing and existing.desc ~= GF_DESC then
    log.debug("Buffer %d already has a custom gf mapping, leaving it intact.", buf)
    return
  end

  if existing then
    pcall(vim.keymap.del, "n", "gf", { buffer = buf })
  end

  vim.keymap.set("n", "gf", M.gf, {
    buffer = buf,
    noremap = true,
    silent = true,
    desc = GF_DESC,
  })
  log.debug("BladeNav gf mapping set for buffer %d.", buf)
end

--- Removes our buffer-local `gf` mapping and clears the guard flag when a
--- buffer leaves the supported filetypes, so the mapping does not outlive its
--- context and a later switch back re-evaluates from scratch.
--- @param buf integer Buffer handle.
local function remove_gf_mapping(buf)
  if not vim.b[buf].blade_nav_gf then
    return
  end
  vim.b[buf].blade_nav_gf = nil

  local existing = get_keymap("n", "gf", buf)
  if existing and existing.desc == GF_DESC then
    pcall(vim.keymap.del, "n", "gf", { buffer = buf })
    log.debug("BladeNav gf mapping removed from buffer %d.", buf)
  end
end

--- Setup function for the `gf` integration.
--- Registers the `gf` keymap for relevant filetypes.
function M.setup()
  if registered then
    log.debug("BladeNav gf integration setup already called, skipping.")
    return
  end
  registered = true

  local grp = vim.api.nvim_create_augroup("blade_nav_gf_integration", { clear = true })

  vim.api.nvim_create_autocmd("FileType", {
    group = grp,
    pattern = GF_FILETYPES,
    callback = function(args)
      apply_gf_mapping(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd("FileType", {
    group = grp,
    callback = function(args)
      if not vim.tbl_contains(GF_FILETYPES, args.match) then
        remove_gf_mapping(args.buf)
      end
    end,
  })

  -- Setup runs synchronously while handling the FileType event of the buffer
  -- that triggered it (via ftplugin loading), so the autocmd above won't fire
  -- for that same buffer/event cycle. Cover it explicitly here.
  local current_buf = vim.api.nvim_get_current_buf()
  if vim.tbl_contains(GF_FILETYPES, vim.api.nvim_get_option_value("filetype", { buf = current_buf })) then
    apply_gf_mapping(current_buf)
  end

  log.info("BladeNav gf integration setup complete.")
end

return M
