-- lua/tests/test_route_map_spec.lua
local laravel = require("blade-nav.utils.laravel")

describe("build_route_map", function()
  it("parses routes with controller@method", function()
    local routes = {
      { name = "foo", action = "App\\Http\\Controllers\\FooController@bar" },
    }
    local map = laravel.__test_build_route_map(routes)
    assert.equals("App\\Http\\Controllers\\FooController", map.foo.controller)
    assert.equals("bar", map.foo.method)
  end)

  it("parses routes with controller only", function()
    local routes = {
      { name = "foo", action = "App\\Http\\Controllers\\InvokableController" },
    }
    local map = laravel.__test_build_route_map(routes)
    assert.equals("App\\Http\\Controllers\\InvokableController", map.foo.controller)
    assert.is_nil(map.foo.method)
  end)
end)
