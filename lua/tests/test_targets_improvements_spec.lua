-- lua/tests/test_targets_improvements_spec.lua
local stub = require("luassert.stub")

describe("BladeNav targets improvements", function()
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
