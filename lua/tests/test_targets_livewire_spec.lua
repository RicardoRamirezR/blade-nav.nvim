-- lua/tests/test_targets_livewire_spec.lua
local stub = require("luassert.stub")
local livewire = require("blade-nav.targets.livewire")
local fs = require("blade-nav.utils.fs")
local strutil = require("blade-nav.utils.string")

describe("livewire handler", function()
  it("returns nil if no livewire reference", function()
    local ctx = { line = "<div>nope</div>", ts_node = {} }
    assert.is_nil(livewire.get_target(ctx))
  end)

  it("extracts @livewire directive", function()
    local ctx = { line = "@livewire('user.profile')", ts_node = {} }
    stub(strutil, "kebab_to_pascal").returns("UserProfile")

    local target = livewire.get_target(ctx)
    assert.is_table(target)
    assert.equals("livewire", target.type)
    strutil.kebab_to_pascal:revert()
  end)

  it("normalize component name", function()
    local ctx = { line = "<livewire:user-profile />", ts_node = {} }
    stub(strutil, "kebab_to_pascal").returns("UserProfile")
    local target = livewire.get_target(ctx)
    assert.equals("livewire", target.type)
    strutil.kebab_to_pascal:revert()
  end)
end)
