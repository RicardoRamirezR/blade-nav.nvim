-- lua/tests/test_targets_lazy_spec.lua
local stub = require("luassert.stub")

describe("BladeNav targets lazy loading", function()
  local targets

  before_each(function()
    package.loaded["blade-nav.targets"] = nil
    targets = require("blade-nav.targets")

    -- reset state
    targets._handlers = {}
    targets._handler_order = {}
    targets._handler_modules = {}
  end)

  it("does not require handler until resolution", function()
    local required = false

    package.preload["blade-nav.targets.fake"] = function()
      required = true
      return {
        get_target = function()
          return { type = "fake", resolved = true }
        end,
        resolve = function()
          return true
        end,
      }
    end

    -- manually register fake into handler_modules
    targets._handler_modules["fake"] = "blade-nav.targets.fake"
    table.insert(targets._handler_order, "fake")

    assert.is_false(required)

    local ok = targets.resolve_target({})
    assert.is_true(ok)
    assert.is_true(required) -- required should flip to true
    assert.is_not_nil(targets._handlers.fake)
  end)

  it("skips disabled handlers", function()
    local required = false
    package.preload["blade-nav.targets.fake2"] = function()
      required = true
      return {
        get_target = function()
          return { type = "fake2", resolved = true }
        end,
        resolve = function()
          return true
        end,
      }
    end

    -- Simulate load_handlers skipping disabled
    local config = { handlers = { fake2 = false } }
    targets.load_handlers("blade-nav.targets", ".", config)

    assert.is_nil(targets._handler_modules.fake2)
    assert.is_false(required)
  end)

  it("logs error if handler fails to load", function()
    package.preload["blade-nav.targets.broken"] = function()
      error("broken module")
    end

    -- inject broken handler
    targets._handler_modules["broken"] = "blade-nav.targets.broken"
    table.insert(targets._handler_order, "broken")

    local log = require("blade-nav.utils.log")
    local log_error = stub(log, "error")

    local ok = targets.resolve_target({})

    log.error:revert()

    assert.is_false(ok)
    assert.stub(log_error).was_called()
    local msg = log_error.calls[1].refs[1]
    assert.matches("Failed to load target handler", msg)
  end)
end)
