-- lua/tests/test_targets_component_spec.lua
local stub = require("luassert.stub")
local comp = require("blade-nav.targets.component")
local laravel = require("blade-nav.utils.laravel")

describe("component handler", function()
  it("returns nil if not a blade file", function()
    local target = comp.get_target({ filetype = "php", line = "<x-alert />" })
    assert.is_nil(target)
  end)

  it("detects component and returns choices", function()
    stub(laravel, "get_component_paths").returns({ "resources/views/components/alert.blade.php" })
    local ctx = { filetype = "blade", line = "<x-alert />" }
    local target = comp.get_target(ctx)
    assert.is_table(target)
    assert.equals("component", target.type)
    laravel.get_component_paths:revert()
  end)

  it("returns nil if no choices found", function()
    stub(laravel, "get_component_paths").returns({})
    local ctx = { filetype = "blade", line = "<x-unknown />" }
    local target = comp.get_target(ctx)
    assert.is_nil(target)
    laravel.get_component_paths:revert()
  end)
end)
