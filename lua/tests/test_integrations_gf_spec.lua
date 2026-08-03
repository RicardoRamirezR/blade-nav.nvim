-- lua/tests/test_integrations_gf_spec.lua
-- Behavioral coverage for blade-nav.integrations.gf's fallback path: when no
-- blade-nav target resolves, gf.gf() must fall back to the user's global
-- `gf` mapping and, if it is a Lua callback, invoke it directly (rather than
-- crashing or silently doing nothing) -- and must NOT invoke it when a
-- blade-nav target did resolve.

local helpers = require("tests.helpers")
local targets = require("blade-nav.targets")
local gf = require("blade-nav.integrations.gf")

describe("integrations.gf fallback dispatch", function()
  local orig_resolve_target

  before_each(function()
    orig_resolve_target = targets.resolve_target
    pcall(vim.keymap.del, "n", "gf")
  end)

  after_each(function()
    targets.resolve_target = orig_resolve_target
    pcall(vim.keymap.del, "n", "gf")
  end)

  it("invokes the global gf Lua-callback mapping when no blade-nav target resolves", function()
    targets.resolve_target = function()
      return false
    end

    local called = false
    vim.keymap.set("n", "gf", function()
      called = true
    end)

    helpers.with_buffer({ "plain line, nothing to resolve here" }, { filetype = "php" }, function()
      local ok, err = pcall(gf.gf)
      assert.is_true(ok, "gf.gf() should not throw: " .. tostring(err))
    end)

    assert.is_true(called, "expected the global gf Lua-callback to be invoked as a fallback")
  end)

  it("does not invoke the global gf callback when a blade-nav target resolves", function()
    targets.resolve_target = function()
      return true
    end

    local called = false
    vim.keymap.set("n", "gf", function()
      called = true
    end)

    helpers.with_buffer({ "@include('x')" }, { filetype = "blade" }, function()
      local ok = pcall(gf.gf)
      assert.is_true(ok)
    end)

    assert.is_false(called, "fallback should not run when blade-nav already resolved a target")
  end)

  it("feeds the global gf string rhs with remap so mappings it references still expand", function()
    targets.resolve_target = function()
      return false
    end

    local called = false
    vim.keymap.set("n", "<Plug>(BladeNavTestGf)", function()
      called = true
    end)
    -- A noremap mapping whose rhs references another mapping: only a remap
    -- feed ("m") expands the <Plug> reference.
    vim.keymap.set("n", "gf", "<Plug>(BladeNavTestGf)")

    helpers.with_buffer({ "plain line, nothing to resolve here" }, { filetype = "php" }, function()
      local ok, err = pcall(gf.gf)
      assert.is_true(ok, "gf.gf() should not throw: " .. tostring(err))
      -- Feedkeys with "m" only queues the rhs; flush the pending typeahead
      -- synchronously so the <Plug> mapping actually triggers.
      vim.api.nvim_feedkeys("", "x", false)
      assert.is_true(called, "expected the <Plug> mapping referenced by the gf rhs to be invoked via remap feedkeys")
    end)

    pcall(vim.keymap.del, "n", "<Plug>(BladeNavTestGf)")
  end)
end)

describe("integrations.gf filetype lifecycle", function()
  local function buf_gf_mapping(bufnr)
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
      if m.lhs == "gf" then
        return m
      end
    end
  end

  after_each(function()
    pcall(vim.api.nvim_del_augroup_by_name, "blade_nav_gf_integration")
  end)

  it("removes the buffer-local gf and clears the guard flag when the filetype leaves the supported set", function()
    helpers.with_buffer({ "plain" }, { filetype = "blade" }, function(bufnr)
      gf.setup()

      assert.is_not_nil(buf_gf_mapping(bufnr), "gf mapping should be installed for blade buffers")
      assert.is_true(vim.b[bufnr].blade_nav_gf)

      vim.bo[bufnr].filetype = "markdown"

      assert.is_nil(buf_gf_mapping(bufnr), "gf mapping must not survive a filetype change away from blade/php/vue")
      assert.is_nil(vim.b[bufnr].blade_nav_gf, "the guard flag should be cleared so re-entry re-evaluates")

      vim.bo[bufnr].filetype = "blade"
      assert.is_not_nil(buf_gf_mapping(bufnr), "gf mapping should be re-installed when switching back")
      assert.is_true(vim.b[bufnr].blade_nav_gf)
    end)
  end)
end)
