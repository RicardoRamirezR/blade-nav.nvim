-- lua/tests/test_loader_spec.lua
local stub = require("luassert.stub")

describe("BladeNav loader", function()
  local loader
  local orig_notify

  before_each(function()
    -- Reset globals between tests
    vim.g.blade_nav = nil
    vim.g.loaded_blade_nav = nil

    -- Clear cached modules
    package.loaded["blade-nav"] = nil
    package.loaded["blade-nav.loader"] = nil
    package.loaded["blade-nav.utils.laravel"] = {
      is_laravel_project = function()
        return true
      end,
    }

    -- Keep original notify
    orig_notify = vim.notify

    loader = require("blade-nav.loader")
  end)

  after_each(function()
    -- Restore notify
    vim.notify = orig_notify
  end)

  it("bails out if vim.g.blade_nav.enable == false", function()
    package.loaded["blade-nav.utils.laravel"] = {
      is_laravel_project = function()
        return false
      end,
    }
    vim.g.blade_nav = { enable = false }
    loader.ftplugin_loader()
    assert.is_nil(vim.g.loaded_blade_nav)
  end)

  it("loads and calls setup() when available", function()
    local setup_called = false
    package.loaded["blade-nav"] = {
      setup = function()
        setup_called = true
      end,
    }

    loader.ftplugin_loader()

    assert.is_true(setup_called)
    assert.is_true(vim.g.loaded_blade_nav)
  end)

  it("notifies on setup error", function()
    package.loaded["blade-nav"] = {
      setup = function()
        error("boom!")
      end,
    }

    local notify = stub(vim, "notify")
    loader.ftplugin_loader()

    assert.stub(notify).was_called()

    local args = notify.calls[1].refs
    assert.matches("%[BladeNav%]", args[1]) -- has prefix
    assert.matches("Setup failed", args[1]) -- contains failure context
    assert.matches("boom!", args[1]) -- includes error reason
    -- loaded_blade_nav must NOT be latched on failure, otherwise a transient
    -- setup error would prevent retrying for the rest of the session.
    assert.is_nil(vim.g.loaded_blade_nav)
  end)

  it("notifies on require failure", function()
    local orig_require = require
    _G.require = function(modname)
      if modname == "blade-nav" then
        error("module not found")
      end
      return orig_require(modname)
    end

    local notify = stub(vim, "notify")
    loader.ftplugin_loader()
    _G.require = orig_require

    assert.stub(notify).was_called()

    local args = notify.calls[1].refs
    assert.matches("%[BladeNav%]", args[1]) -- has prefix
    assert.matches("Failed to load", args[1]) -- contains failure context
    assert.matches("module not found", args[1]) -- includes error reason
    assert.is_nil(vim.g.loaded_blade_nav)
  end)

  it("does not reload if already marked loaded", function()
    vim.g.loaded_blade_nav = true

    local blade_nav = { setup = stub.new() }
    package.loaded["blade-nav"] = blade_nav

    loader.ftplugin_loader()

    assert.stub(blade_nav.setup).was_not_called()
  end)

  it("bails out if not a Laravel project (unless force_enable)", function()
    package.loaded["blade-nav.utils.laravel"] = {
      is_laravel_project = function()
        return false
      end,
    }
    local setup_called = false
    package.loaded["blade-nav"] = {
      setup = function()
        setup_called = true
      end,
    }
    loader.ftplugin_loader()
    -- loaded_blade_nav must NOT be latched globally on a non-Laravel bail-out,
    -- otherwise a later Laravel project opened in the same session would never load.
    assert.is_nil(vim.g.loaded_blade_nav)
    assert.is_false(setup_called)
  end)

  it("runs when force_enable=true even if not Laravel", function()
    package.loaded["blade-nav.utils.laravel"] = {
      is_laravel_project = function()
        return false
      end,
    }
    vim.g.blade_nav = { force_enable = true }
    local setup_called = false
    package.loaded["blade-nav"] = {
      setup = function()
        setup_called = true
      end,
    }
    loader.ftplugin_loader()
    assert.is_true(setup_called)
  end)
end)
