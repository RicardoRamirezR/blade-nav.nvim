local stub = require("luassert.stub")
local config = require("blade-nav.targets.config")
local laravel = require("blade-nav.utils.laravel")

describe("config handler", function()
  before_each(function()
    _G.all_calculated_paths = {}
  end)

  it("detects config reference and returns target_info", function()
    stub(laravel, "get_config_path").returns("config/app.php")

    local ctx = { line = "config('app.name')", cursor_col_1 = 10 }
    local target = config.get_target(ctx)

    assert.is_table(target)
    assert.equals("config", target.type)

    laravel.get_config_path:revert()
  end)

  it("returns nil if no config or env reference", function()
    local ctx = { line = "echo 'foo';", cursor_col_1 = 5 }
    assert.is_nil(config.get_target(ctx))
  end)

  it("resolves config key to a file", function()
    stub(laravel, "get_config_path").returns("config/app.php")

    local ctx = { line = "config('app.debug')", cursor_col_1 = 10 }
    local target = config.get_target(ctx)

    assert.is_table(target)
    assert.equals("config", target.type)

    laravel.get_config_path:revert()
  end)

  it("fails gracefully if config file missing", function()
    stub(laravel, "get_config_path").returns(nil)

    local ctx = { line = "config('foo.bar')", cursor_col_1 = 10 }
    local target = config.get_target(ctx)

    assert.is_table(target)
    assert.equals("config", target.type)
    assert.equals("foo.bar", target.name)
    -- path should be nil since file doesn't exist
    assert.is_nil(target.path)

    laravel.get_config_path:revert()
  end)
end)
