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
end)
