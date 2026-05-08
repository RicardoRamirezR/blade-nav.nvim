local cache = require("blade-nav.utils.cache")

describe("cache module", function()
  it("stores and retrieves values", function()
    cache.set("foo", "bar")
    assert.equals("bar", cache.get("foo"))
  end)

  it("expires values after ttl", function()
    cache.set("baz", "qux")
    vim.wait(20)                        -- 20ms wait
    assert.is_nil(cache.get("baz", 10)) -- ttl=10ms
  end)

  it("clear_prefix removes matching keys", function()
    cache.set("route_list:abc", "foo")
    cache.set("route_list:def", "bar")
    cache.clear_prefix("route_list:")
    assert.is_nil(cache.get("route_list:abc"))
    assert.is_nil(cache.get("route_list:def"))
  end)
end)
