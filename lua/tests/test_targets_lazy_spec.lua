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
    targets._failed_handlers = {}
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
    targets.load_handlers("blade-nav.targets", "./lua/blade-nav/targets", config)

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

  --
  -- 🔥 New improvement tests
  --
  it("does not duplicate handlers on multiple load_handlers calls", function()
    local config = { handlers = {} }

    targets.load_handlers("blade-nav.targets", "./lua/blade-nav/targets", config)
    local first_count = #targets._handler_order

    targets.load_handlers("blade-nav.targets", "./lua/blade-nav/targets", config)
    local second_count = #targets._handler_order

    assert.equals(first_count, second_count)
  end)

  it("skips disabled handlers before registration", function()
    local config = { handlers = { view = false } }
    targets.load_handlers("blade-nav.targets", "./lua/blade-nav/targets", config)

    assert.is_nil(targets._handler_modules.view)
    assert.is_true(#targets._handler_order > 0) -- sanity
  end)

  it("caches failed handler require attempts", function()
    targets._handler_modules["broken"] = "blade-nav.targets.broken"
    table.insert(targets._handler_order, "broken")

    package.preload["blade-nav.targets.broken"] = function()
      error("boom")
    end

    local log = require("blade-nav.utils.log")
    local log_error = stub(log, "error")

    local ok1 = targets.resolve_target({})
    assert.is_false(ok1)
    assert.stub(log_error).was_called()

    log_error:clear()

    -- second attempt should not even try require
    local ok2 = targets.resolve_target({})
    assert.is_false(ok2)
    assert.stub(log_error).was_not_called()
    log_error:revert()
  end)

  it("successfully loads and runs a valid handler", function()
    package.preload["blade-nav.targets.good"] = function()
      return {
        get_target = function()
          return { type = "good", resolved = true }
        end,
        resolve = function()
          return true
        end,
      }
    end

    targets._handler_modules["good"] = "blade-nav.targets.good"
    table.insert(targets._handler_order, "good")

    local ok = targets.resolve_target({})
    assert.is_true(ok)
    assert.is_not_nil(targets._handlers.good)
  end)

  it("does not duplicate handlers on multiple load_handlers calls", function()
    local config = { handlers = {} }

    targets.load_handlers("blade-nav.targets", "./lua/blade-nav/targets", config)
    local first_count = #targets._handler_order

    -- call again with same config
    targets.load_handlers("blade-nav.targets", "./lua/blade-nav/targets", config)
    local second_count = #targets._handler_order

    assert.equals(first_count, second_count)
  end)

  it("skips disabled handlers before registration", function()
    local config = { handlers = { view = false } }
    targets.load_handlers("blade-nav.targets", "./lua/blade-nav/targets", config)

    -- "view" handler exists in repo, but should not be in _handler_modules
    assert.is_nil(targets._handler_modules.view)
    -- sanity: at least one other handler is registered
    assert.is_true(#targets._handler_order > 0)
  end)

  it("caches failed handler require attempts", function()
    -- inject a fake broken handler
    targets._handler_modules["broken"] = "blade-nav.targets.broken"
    table.insert(targets._handler_order, "broken")

    package.preload["blade-nav.targets.broken"] = function()
      error("boom")
    end

    local log = require("blade-nav.utils.log")
    local log_error = stub(log, "error")

    local ok1 = targets.resolve_target({})
    assert.is_false(ok1)
    assert.stub(log_error).was_called()

    log_error:clear()

    -- second attempt should not even try require, so no extra log
    local ok2 = targets.resolve_target({})
    assert.is_false(ok2)
    assert.stub(log_error).was_not_called()
    log_error:revert()
  end)
end)
