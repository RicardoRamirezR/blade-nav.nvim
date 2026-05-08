local stub = require("luassert.stub")
local view = require("blade-nav.targets.view")
local laravel = require("blade-nav.utils.laravel")

describe("view handler", function()
  before_each(function()
    _G.all_calculated_paths = {}
  end)

  it("returns nil if not on a view reference", function()
    local ctx = { line = "echo 'foo';", cursor_col_1 = 5 }
    assert.is_nil(view.get_target(ctx))
  end)

  it("detects view reference", function()
    stub(laravel, "normalize_view_name").returns("user/profile.blade.php")
    stub(laravel, "get_view_path").returns("resources/views/user/profile.blade.php")

    local ctx = { line = "view('user.profile')", cursor_col_1 = 8 }
    local target = view.get_target(ctx)

    assert.is_table(target)
    assert.equals("view", target.type)

    laravel.normalize_view_name:revert()
    laravel.get_view_path:revert()
  end)
end)
