-- lua/tests/test_targets_xcomponent_spec.lua
local stub = require("luassert.stub")
local xcomp = require("blade-nav.targets.xcomponent")
local fs = require("blade-nav.utils.fs")
local laravel = require("blade-nav.utils.laravel")

describe("xcomponent handler", function()
  it("returns nil if not a blade file", function()
    local target = xcomp.get_target({ filetype = "php", line = "<x-alert />" })
    assert.is_nil(target)
  end)

  it("detects component and returns choices", function()
    stub(laravel, "get_component_paths").returns({ "resources/views/components/alert.blade.php" })
    local ctx = { filetype = "blade", line = "<x-alert />" }
    local target = xcomp.get_target(ctx)
    assert.is_table(target)
    assert.equals("xcomponent", target.type)
    laravel.get_component_paths:revert()
  end)

  it("returns nil if no choices found", function()
    stub(laravel, "get_component_paths").returns({})
    local ctx = { filetype = "blade", line = "<x-unknown />" }
    local target = xcomp.get_target(ctx)
    assert.is_nil(target)
    laravel.get_component_paths:revert()
  end)
end)
