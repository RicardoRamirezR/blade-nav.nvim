-- lua/tests/test_targets_livewire_spec.lua
local stub = require("luassert.stub")
local livewire = require("blade-nav.targets.livewire")
local strutil = require("blade-nav.utils.string")

describe("livewire handler", function()
  it("returns nil if no livewire reference", function()
    local ctx = { line = "<div>nope</div>", target = "livewire" }
    assert.is_nil(livewire.get_target(ctx))
  end)

  it("extracts @livewire directive", function()
    local ctx = {
      line = "@livewire('user.profile')",
      target = "livewire",
      first_arg = "user.profile",
      filetype = "blade", -- <--- add this
    }
    stub(strutil, "kebab_to_pascal").returns("UserProfile")

    local target = livewire.get_target(ctx)
    assert.is_table(target)
    assert.equals("livewire", target.type)
    strutil.kebab_to_pascal:revert()
  end)

  it("normalize component name", function()
    local ctx = {
      line = "<livewire:user-profile />",
      target = "livewire",
      filetype = "blade", -- <--- add this
    }
    stub(strutil, "kebab_to_pascal").returns("UserProfile")

    local target = livewire.get_target(ctx)
    assert.equals("livewire", target.type)
    strutil.kebab_to_pascal:revert()
  end)
end)
