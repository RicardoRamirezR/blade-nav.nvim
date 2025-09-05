-- lua/blade-nav/integrations/gf.lua

local targets = require("blade-nav.targets")
local context_creator = require("blade-nav.core.context")
local log = require("blade-nav.utils.log")

local M = {}
local registered = false
local gf_mapping

--- Gets the current keymap for 'gf' in normal mode.
--- @param mode string The mode (e.g., "n" for normal).
--- @param lhs string The left-hand side of the mapping (e.g., "gf").
--- @return table|nil The keymap table or nil if not found.
local function get_keymap(mode, lhs)
  local keymaps = vim.api.nvim_get_keymap(mode)
  for _, keymap in ipairs(keymaps) do
    if keymap.lhs == lhs then
      return keymap
    end
  end
end

--- Executes the native Neovim `gf` command.
--- Attempts to use the user's existing mapping if it exists, otherwise falls back.
local function gf_native()
  if gf_mapping then
    local rhs = vim.api.nvim_replace_termcodes(gf_mapping.rhs, true, true, true)
    vim.api.nvim_feedkeys(rhs, "n", false)
  else
    vim.fn.execute("normal! gf", "silent")
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

--- Setup function for the `gf` integration.
--- Registers the `gf` keymap for relevant filetypes.
function M.setup()
  if registered then
    log.debug("BladeNav gf integration setup already called, skipping.")
    return
  end
  registered = true

  gf_mapping = get_keymap("n", "gf")

  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = vim.api.nvim_create_augroup("blade_nav_gf_integration", { clear = true }),
    callback = function(args)
      local buf_ft = vim.api.nvim_buf_get_option(args.buf, "filetype")
      if buf_ft == "blade" or buf_ft == "php" or buf_ft == "vue" then
        pcall(vim.keymap.del, "n", "gf", { buffer = args.buf })

        vim.keymap.set("n", "gf", M.gf, {
          buffer = args.buf,
          noremap = true,
          silent = true,
          desc = "BladeNav: Enhanced go-to file under cursor",
        })
        log.debug("BladeNav gf mapping set for buffer %d (filetype: %s)", args.buf, buf_ft)
      end
    end,
  })

  log.info("BladeNav gf integration setup complete.")
end

return M
