local stub = require("luassert.stub")
local route = require("blade-nav.targets.route")
local laravel = require("blade-nav.utils.laravel")

describe("route handler", function()
  before_each(function()
    -- reset stubs/globals between tests
    package.loaded["blade-nav.utils.laravel"] = nil
    laravel = require("blade-nav.utils.laravel")
  end)

  it("returns nil if not a route reference", function()
    local ctx = { line = "echo 'foo';", cursor_col_1 = 5 }
    assert.is_nil(route.get_target(ctx))
  end)

  it("detects route name and resolves", function()
    stub(laravel, "normalize_route_name").returns("home")
    stub(laravel, "get_route_path").returns("routes/web.php")

    local ctx = { line = "route('home')", cursor_col_1 = 8 }
    local target = route.get_target(ctx)

    assert.is_table(target)
    assert.equals("route", target.type)

    laravel.normalize_route_name:revert()
    laravel.get_route_path:revert()
  end)
end)
