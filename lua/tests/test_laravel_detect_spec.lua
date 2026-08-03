local laravel = require("blade-nav.utils.laravel")

describe("is_laravel_project", function()
  local fs = require("blade-nav.utils.fs")

  before_each(function()
    -- The result is memoized per root; clear between tests that re-mock fs.
    laravel.__test_clear_is_laravel_cache()
    fs.path_exists = function(_)
      return false
    end
    fs.read_file = function(_)
      return nil
    end
  end)

  it("true when artisan exists", function()
    fs.path_exists = function(p)
      return p:match("artisan$") ~= nil
    end
    assert.is_true(laravel.is_laravel_project("/x"))
  end)

  it("true when composer.json requires laravel/framework", function()
    fs.path_exists = function(p)
      return p:match("composer.json$") ~= nil
    end
    fs.read_file = function(_)
      return vim.json.encode({ require = { ["laravel/framework"] = "^11.0" } })
    end
    assert.is_true(laravel.is_laravel_project("/x"))
  end)

  it("false otherwise", function()
    assert.is_false(laravel.is_laravel_project("/x"))
  end)

  it("memoizes the result per root (no repeated filesystem hits)", function()
    local calls = 0
    fs.path_exists = function(_)
      calls = calls + 1
      return true
    end
    assert.is_true(laravel.is_laravel_project("/memoized-root"))
    local calls_after_first = calls
    assert.is_true(laravel.is_laravel_project("/memoized-root"))
    assert.equals(calls_after_first, calls)
  end)
end)
