-- lua/tests/test_view_spec.lua
local laravel = require("blade-nav.utils.laravel")

describe("normalize_view_name", function()
  it("converts dot notation to path", function()
    assert.equals("user/profile.blade.php", laravel.normalize_view_name("user.profile"))
  end)

  it("leaves .blade.php intact", function()
    assert.equals("admin/dashboard.blade.php", laravel.normalize_view_name("admin/dashboard.blade.php"))
  end)
end)
