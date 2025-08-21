local laravel = require("blade-nav.utils.laravel")

describe("is_laravel_project", function()
  local fs = require("blade-nav.utils.fs")

  before_each(function()
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
end)
