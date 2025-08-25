-- lua/blade-nav/integrations/gf.lua
-- Integration for the `gf` keymap, delegating resolution to the targets system.

local targets = require("blade-nav.targets")              -- Import the targets module for resolution
local context_creator = require("blade-nav.core.context") -- Import context creator
local log = require("blade-nav.utils.log")                -- Import logger

local M = {}
local registered = false -- Flag to ensure setup only runs once
local gf_mapping         -- Store the original gf mapping

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
    -- If a custom mapping exists, execute its right-hand side
    local rhs = vim.api.nvim_replace_termcodes(gf_mapping.rhs, true, true, true)
    vim.api.nvim_feedkeys(rhs, "n", false)
  else
    -- Fallback to the built-in gf behavior
    vim.fn.execute("normal! gf", "silent")
  end
end

--- Main `gf` handler function.
--- Creates context and delegates resolution to the targets system.
function M.gf()
  log.debug("BladeNav gf handler invoked.")

  local context = context_creator.create_context()

  local resolved = targets.resolve_target(context)

  -- 3. Determine fallback behavior.
  -- If targets.resolve_target returned false/nil, it means:
  --   - No handler matched the context.
  --   - A handler matched but failed to resolve (e.g., file not found).
  --   - An error occurred during resolution.
  -- In these cases, we fall back to the native Neovim `gf` behavior.
  if not resolved then
    log.debug("No BladeNav target resolved or action taken, falling back to native gf.")
    gf_native()
  else
    log.debug("BladeNav target resolution process completed (action may have been taken).")
    -- If resolved is true, the targets system handled it (opened file, showed picker, etc.)
    -- No further action is needed here.
  end
end

--- Setup function for the `gf` integration.
--- Registers the `gf` keymap for relevant filetypes.
function M.setup()
  -- Ensure setup only runs once
  if registered then
    log.debug("BladeNav gf integration setup already called, skipping.")
    return
  end
  registered = true

  -- Get the current user mapping for 'gf' to potentially use for fallback
  gf_mapping = get_keymap("n", "gf")

  -- Setup an autocommand to register the `gf` keymap for Blade and PHP files
  -- Use BufWinEnter as in new-version.txt for robustness
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = vim.api.nvim_create_augroup("blade_nav_gf_integration", { clear = true }),
    callback = function(args)
      local buf_ft = vim.api.nvim_buf_get_option(args.buf, "filetype")
      -- Check if the buffer's filetype is one we want to enhance
      if buf_ft == "blade" or buf_ft == "php" or buf_ft == "vue" then -- Add "vue" if needed
        -- Remove any existing 'gf' mapping in this buffer to avoid conflicts
        -- pcall is used to prevent errors if 'gf' isn't mapped
        pcall(vim.keymap.del, "n", "gf", { buffer = args.buf })

        -- Set the new 'gf' mapping to call our M.gf function
        -- Use buffer = args.buf for buffer-local mapping
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
