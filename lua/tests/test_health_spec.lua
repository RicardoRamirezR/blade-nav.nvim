-- lua/tests/test_health_spec.lua
-- Behavioral coverage for blade-nav.health (blade-nav.integrations.health):
-- the Neovim >= 0.11 gate runs first in check() and short-circuits the rest
-- of the report on old Neovim; and malformed `php artisan --format=json`
-- output takes the vim.health.warn path (not an uncaught error), because
-- health.lua binds `start`/`ok`/`warn`/`error` from vim.health at
-- require-time, so vim.health must be stubbed *before* a fresh require.

describe("health.check", function()
  local orig_vim_health
  local orig_has
  local health_calls

  local function install_fake_vim_health()
    health_calls = { start = {}, ok = {}, warn = {}, error = {} }
    vim.health = {
      start = function(name)
        table.insert(health_calls.start, name)
      end,
      ok = function(msg)
        table.insert(health_calls.ok, msg)
      end,
      warn = function(msg)
        table.insert(health_calls.warn, msg)
      end,
      error = function(msg)
        table.insert(health_calls.error, msg)
      end,
    }
  end

  local function fresh_health_module()
    package.loaded["blade-nav.health"] = nil
    package.loaded["blade-nav.integrations.health"] = nil
    return require("blade-nav.health")
  end

  local function any_match(list, pattern)
    for _, msg in ipairs(list) do
      if msg:match(pattern) then
        return true
      end
    end
    return false
  end

  before_each(function()
    orig_vim_health = vim.health
    orig_has = vim.fn.has
    install_fake_vim_health()
  end)

  after_each(function()
    vim.health = orig_vim_health
    vim.fn.has = orig_has
    package.loaded["blade-nav.health"] = nil
    package.loaded["blade-nav.integrations.health"] = nil
  end)

  it("checks Neovim >= 0.11 first and short-circuits the rest of the report on old Neovim", function()
    vim.fn.has = function(feature)
      if feature == "nvim-0.11" then
        return 0
      end
      return orig_has(feature)
    end

    local cmd = require("blade-nav.utils.cmd")
    local orig_execute_silent = cmd.execute_silent
    local execute_silent_calls = 0
    cmd.execute_silent = function(...)
      execute_silent_calls = execute_silent_calls + 1
      return orig_execute_silent(...)
    end

    local health = fresh_health_module()
    local ok, err = pcall(health.check)
    cmd.execute_silent = orig_execute_silent

    assert.is_true(ok, "health.check() should not throw: " .. tostring(err))
    assert.is_true(
      any_match(health_calls.error, "Neovim >= 0%.11"),
      "expected a version-gate error, got: " .. vim.inspect(health_calls.error)
    )
    assert.equals(
      0,
      execute_silent_calls,
      "no further checks (which shell out via cmd.execute_silent) should run after the version gate fails"
    )
    assert.is_false(
      any_match(health_calls.ok, "BladeNav plugin loaded"),
      "the post-gate 'plugin loaded' ok() should not have been reached"
    )
  end)

  it("takes the vim.health.warn path (not an error) when `php artisan --format=json` returns garbage", function()
    -- config_module.get().integrations must be a real table for
    -- check_integrations() to run; force a clean default merge regardless
    -- of what earlier specs left cached in this shared, process-wide module.
    require("blade-nav.core.config").setup({})

    local cmd = require("blade-nav.utils.cmd")
    local orig_execute_silent = cmd.execute_silent
    cmd.execute_silent = function(argv, opts)
      if argv[1] == "php" and argv[2] == "artisan" and argv[3] == "--format=json" then
        return "not valid json {{{", true
      end
      return orig_execute_silent(argv, opts)
    end

    local health = fresh_health_module()
    local ok, err = pcall(health.check)
    cmd.execute_silent = orig_execute_silent

    assert.is_true(ok, "health.check() should not throw on malformed json: " .. tostring(err))
    assert.is_true(
      any_match(health_calls.warn, "Could not parse"),
      "expected a warn() about unparsable artisan --format=json output, got: " .. vim.inspect(health_calls.warn)
    )
  end)
end)
