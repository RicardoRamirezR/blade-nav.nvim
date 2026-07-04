-- lua/tests/test_extras_spec.lua
local stub = require("luassert.stub")
local cache = require("blade-nav.utils.cache")
local laravel = require("blade-nav.utils.laravel")
local fs = require("blade-nav.utils.fs")

describe("Extra Laravel utils", function()
  before_each(function()
    cache.clear_prefix("route_list:")
  end)

  --
  -- (1) Primed cache consistency
  --
  it("returns consistent maps with and without route_name", function()
    cache.set("route_list:primed", {
      foo = { controller = "App\\Http\\Controllers\\Foo", method = "bar" },
    })

    local single = laravel.get_route_list("foo")
    local all = laravel.get_route_list()

    assert.is_table(single.foo)
    assert.equals("bar", single.foo.method)

    assert.is_table(all.foo)
    assert.equals("bar", all.foo.method)
  end)

  --
  -- (2) Watcher invalidation hooks
  --
  it("invalidates cache directly", function()
    cache.set("route_list:foo", { foo = "dummy" })

    -- directly call the internal helper
    laravel.invalidate_routes_cache()
    assert.is_nil(cache.get("route_list:foo"))
  end)
  --
  -- (3) PSR-4 mapping parsing
  --
  it("parses psr-4 mappings from composer.json", function()
    local read_file = stub(fs, "read_file").returns(vim.json.encode({
      autoload = { ["psr-4"] = { ["Noah\\"] = "src/" } },
    }))

    local mappings = laravel.get_psr4_mappings()
    assert.is_table(mappings)
    assert.equals("src/", mappings["Noah\\"])

    read_file:revert()
  end)

  --
  -- (4) normalize_view_name edge cases
  --
  it("normalizes view names with and without .blade.php", function()
    assert.equals("user/profile.blade.php", laravel.normalize_view_name("user.profile"))
    assert.equals("user/profile.blade.php", laravel.normalize_view_name("user.profile.blade.php"))
    assert.is_nil(laravel.normalize_view_name(nil))
  end)

  it("leaves an already-slash-form .blade.php view name intact", function()
    assert.equals("admin/dashboard.blade.php", laravel.normalize_view_name("admin/dashboard.blade.php"))
  end)

  --
  -- (5) component path resolution
  --
  it("returns make:component command when component is missing", function()
    local path_exists = stub(fs, "path_exists").returns(false)
    local is_dir = stub(fs, "is_dir").returns(false)

    local choices = laravel.get_component_paths("button")
    local found = false
    for _, c in ipairs(choices) do
      if type(c) == "table" and c.label:match("make:component Button") then
        assert.same({ "php", "artisan", "make:component", "Button" }, c.cmd)
        found = true
      end
    end
    assert.is_true(found)

    path_exists:revert()
    is_dir:revert()
  end)
end)
