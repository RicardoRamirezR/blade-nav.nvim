-- lua/tests/test_laravel_spec.lua
local laravel = require("blade-nav.utils.laravel")
local cache = require("blade-nav.utils.cache")
local real_cmd = require("blade-nav.utils.cmd")
-- Required at file level: some tests below replace package.loaded["blade-nav.utils.fs"]
-- with a stub, so a later require would not return the real module.
local fs = require("blade-nav.utils.fs")

describe("laravel.get_route_list", function()
  before_each(function()
    cache.clear_prefix("route_list:")
  end)

  it("returns {} placeholder when php is missing", function()
    package.loaded["blade-nav.utils.fs"] = {
      command_exists = function()
        return false
      end,
    }
    local result = laravel.get_route_list("foo")
    assert.is_table(result)
    assert.is_nil(next(result))
  end)

  it("returns correct map when php artisan succeeds", function()
    package.loaded["blade-nav.utils.fs"] = {
      command_exists = function()
        return true
      end,
    }
    real_cmd.execute_silent = function()
      return vim.json.encode({
        { name = "foo", action = "App\\Http\\Controllers\\Foo@bar" },
      }), true
    end

    local result = laravel.get_route_list("foo")
    assert.is_table(result)
    assert.equals("App\\Http\\Controllers\\Foo", result["foo"].controller)
    assert.equals("bar", result["foo"].method)
  end)

  it("uses primed cache if available", function()
    cache.set("route_list:primed:" .. fs.get_root_dir(), {
      foo = { controller = "X", method = "y" },
    })
    local result = laravel.get_route_list("foo")
    assert.equals("X", result["foo"].controller)
    assert.equals("y", result["foo"].method)
  end)
end)
