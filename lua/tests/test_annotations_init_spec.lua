-- lua/tests/test_annotations_init_spec.lua
-- Orchestration coverage for blade-nav.features.annotations setup():
-- keymaps installed per config (create_keymaps), a taken global lhs is kept
-- and notified once, toggle on/off renders and clears the namespace, edits
-- while show=false schedule no render work, and the buffer-local K is
-- removed (restoring any captured previous mapping) when the buffer leaves
-- the web filetypes.
--
-- The annotations module is shared process-wide, so every test cleans up the
-- autocmds, user commands and global keymaps that setup() installs.

local helpers = require("tests.helpers")

local annotations = require("blade-nav.features.annotations")
local renderer = require("blade-nav.features.annotations.renderer")
local values = require("blade-nav.features.annotations.values")
local config_module = require("blade-nav.core.config")

local K_DESC = "BladeNav: show config/env value"

local function buf_keymap(bufnr, lhs)
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
    if m.lhs == lhs then
      return m
    end
  end
end

local function extmark_count(bufnr)
  return #vim.api.nvim_buf_get_extmarks(bufnr, values.ns, 0, -1, {})
end

describe("annotations.setup orchestration", function()
  local orig_get_clients
  local orig_notify
  local orig_render_buffer

  before_each(function()
    orig_get_clients = vim.lsp.get_clients
    orig_notify = vim.notify
    orig_render_buffer = renderer.render_buffer
    config_module.setup({})
  end)

  after_each(function()
    vim.lsp.get_clients = orig_get_clients
    vim.notify = orig_notify
    renderer.render_buffer = orig_render_buffer
    pcall(vim.keymap.del, "n", "<leader>bv")
    pcall(vim.keymap.del, "n", "<leader>bcc")
    pcall(vim.api.nvim_del_user_command, "BladeNavToggleShowValues")
    pcall(vim.api.nvim_del_user_command, "BladeNavClearCache")
    pcall(vim.api.nvim_del_augroup_by_name, "BladeNavValues")
    renderer.clear_queue()
    renderer.cleanup_timer()
    config_module.setup({})
  end)

  it("installs global and buffer-local keymaps when create_keymaps is true", function()
    helpers.with_buffer({ "plain" }, { filetype = "blade" }, function(bufnr)
      annotations.setup()

      assert.is_true(vim.fn.maparg("<leader>bv", "n") ~= "", "<leader>bv should be installed")
      assert.is_true(vim.fn.maparg("<leader>bcc", "n") ~= "", "<leader>bcc should be installed")

      local k = buf_keymap(bufnr, "K")
      assert.is_not_nil(k, "buffer-local K should be installed for web filetypes")
      assert.equals(K_DESC, k.desc)
    end)
  end)

  it("installs no keymaps when create_keymaps is false", function()
    config_module.setup({ annotations = { create_keymaps = false } })

    helpers.with_buffer({ "plain" }, { filetype = "blade" }, function(bufnr)
      annotations.setup()

      assert.is_true(vim.fn.maparg("<leader>bv", "n") == "", "<leader>bv should not be installed")
      assert.is_true(vim.fn.maparg("<leader>bcc", "n") == "", "<leader>bcc should not be installed")
      assert.is_nil(buf_keymap(bufnr, "K"), "buffer-local K should not be installed")
    end)
  end)

  it("keeps a taken global lhs and notifies once (WARN)", function()
    vim.keymap.set("n", "<leader>bv", function() end, { desc = "user bv" })

    local notifies = {}
    vim.notify = function(msg, level)
      table.insert(notifies, { msg = msg, level = level })
    end

    annotations.setup()
    -- log.warn notifies via vim.schedule; pump the loop before restoring.
    assert.is_true(vim.wait(1000, function()
      return #notifies >= 1
    end, 10))

    annotations.setup()
    vim.wait(200)

    vim.notify = orig_notify

    assert.equals(1, #notifies, "a taken lhs should notify exactly once")
    assert.equals(vim.log.levels.WARN, notifies[1].level)
    assert.is_true(notifies[1].msg:find("<leader>bv", 1, true) ~= nil)

    local user_map
    for _, m in ipairs(vim.api.nvim_get_keymap("n")) do
      if m.desc == "user bv" then
        user_map = m
      end
    end
    assert.is_not_nil(user_map, "the user's mapping must be kept, not overwritten")

    pcall(vim.keymap.del, "n", "<leader>bv")
  end)

  it("toggle on renders extmarks and toggle off clears the namespace", function()
    helpers.with_buffer({ "<?php", "config('app.name');" }, { filetype = "php" }, function(bufnr)
      annotations.setup()

      annotations.toggle_show()
      assert.is_true(
        vim.wait(2000, function()
          return extmark_count(bufnr) > 0
        end, 10),
        "toggle on should render extmarks"
      )

      annotations.toggle_show()
      assert.equals(0, extmark_count(bufnr), "toggle off should clear the namespace")
    end)
  end)

  it("schedules no render work on edits while show is false", function()
    config_module.setup({ annotations = { show_on_load = false, debounce_ms = 30 } })

    -- Drain any render callback a previous test may have scheduled but not
    -- yet run, so the spy below only counts work triggered by this test.
    vim.wait(100)

    local render_calls = 0
    renderer.render_buffer = function(...)
      render_calls = render_calls + 1
      return orig_render_buffer(...)
    end

    helpers.with_buffer({ "<?php", "config('app.name');" }, { filetype = "php" }, function(bufnr)
      annotations.setup()

      vim.api.nvim_exec_autocmds("TextChanged", { buffer = bufnr })
      vim.api.nvim_exec_autocmds("BufEnter", { buffer = bufnr })
      -- Well past debounce_ms: anything armed would have fired by now.
      vim.wait(200)
    end)

    assert.equals(0, render_calls, "no render work should be scheduled while annotations are off")
  end)

  it("replays a pre-existing buffer-local K through the hover fallback", function()
    helpers.with_buffer({ "<?php", "$x = 1;" }, { filetype = "php" }, function(bufnr)
      local prev_called = false
      vim.keymap.set("n", "K", function()
        prev_called = true
      end, { buffer = bufnr, desc = "user K" })

      annotations.setup()
      assert.equals(K_DESC, buf_keymap(bufnr, "K").desc, "our K should be installed over the user's")

      vim.lsp.get_clients = function()
        return {}
      end

      annotations.on_K()

      assert.is_true(prev_called, "K should fall back to the captured pre-existing mapping")
    end)
  end)

  it("restores the captured previous K when the buffer leaves the web filetypes", function()
    helpers.with_buffer({ "plain" }, { filetype = "blade" }, function(bufnr)
      local prev_called = false
      vim.keymap.set("n", "K", function()
        prev_called = true
      end, { buffer = bufnr, desc = "user K" })

      annotations.setup()
      assert.equals(K_DESC, buf_keymap(bufnr, "K").desc)

      vim.bo[bufnr].filetype = "markdown"

      local restored = buf_keymap(bufnr, "K")
      assert.is_not_nil(restored, "the previous buffer-local K should be restored on filetype change")
      assert.equals("user K", restored.desc)
      restored.callback()
      assert.is_true(prev_called)
    end)
  end)

  it("removes the buffer-local K when the buffer leaves the web filetypes and there was no previous K", function()
    helpers.with_buffer({ "plain" }, { filetype = "blade" }, function(bufnr)
      annotations.setup()
      assert.is_not_nil(buf_keymap(bufnr, "K"))

      vim.bo[bufnr].filetype = "markdown"
      assert.is_nil(buf_keymap(bufnr, "K"), "our K must not survive a filetype change away from the web set")

      vim.bo[bufnr].filetype = "blade"
      local k = buf_keymap(bufnr, "K")
      assert.is_not_nil(k, "K should be re-applied when switching back to a web filetype")
      assert.equals(K_DESC, k.desc)
    end)
  end)
end)
