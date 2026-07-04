-- lua/tests/test_targets_directive_spec.lua
-- Behavioral coverage for blade-nav.targets.directive: dot-notation view
-- names on @include/@extends resolve to root-relative candidate paths
-- (fs.get_root_dir(), not cwd- or buffer-relative).

local directive = require("blade-nav.targets.directive")
local fs = require("blade-nav.utils.fs")
local config_module = require("blade-nav.core.config")

describe("targets.directive.get_target", function()
  local FAKE_ROOT = "/tmp/blade-nav-directive-fake-root"
  local orig_get_root_dir

  before_each(function()
    orig_get_root_dir = fs.get_root_dir
    fs.get_root_dir = function()
      return FAKE_ROOT
    end
    config_module.setup({ laravel_components_paths = {} })
  end)

  after_each(function()
    fs.get_root_dir = orig_get_root_dir
  end)

  it("computes a root-relative candidate for @include dot notation", function()
    local context = {
      filetype = "blade",
      target = "@include",
      first_arg = "layouts.default",
      line = "@include('layouts.default')",
    }

    local result = directive.get_target(context)

    assert.is_not_nil(result)
    assert.equals("directive", result.type)
    assert.equals("layouts.default", result.name)
    assert.is_true(
      vim.tbl_contains(result.choices, FAKE_ROOT .. "/resources/views/layouts/default.blade.php"),
      "expected candidate rooted at fake project root, got: " .. vim.inspect(result.choices)
    )
  end)

  it("computes a root-relative candidate for @extends dot notation", function()
    local context = {
      filetype = "blade",
      target = "@extends",
      first_arg = "layouts.app",
      line = "@extends('layouts.app')",
    }

    local result = directive.get_target(context)

    assert.is_not_nil(result)
    assert.equals("directive", result.type)
    assert.is_true(
      vim.tbl_contains(result.choices, FAKE_ROOT .. "/resources/views/layouts/app.blade.php"),
      "expected candidate rooted at fake project root, got: " .. vim.inspect(result.choices)
    )
  end)

  it("honors user-configured laravel_components_paths as additional root-relative search dirs", function()
    config_module.setup({ laravel_components_paths = { "packages/acme/resources/views" } })

    local context = {
      filetype = "blade",
      target = "@include",
      first_arg = "widgets.card",
      line = "@include('widgets.card')",
    }

    local result = directive.get_target(context)

    assert.is_not_nil(result)
    assert.is_true(
      vim.tbl_contains(
        result.choices,
        FAKE_ROOT .. "/packages/acme/resources/views/widgets/card.blade.php"
      ),
      "expected extra search path candidate, got: " .. vim.inspect(result.choices)
    )

    config_module.setup({ laravel_components_paths = {} })
  end)

  it("returns nil for a non-blade filetype", function()
    local result = directive.get_target({ filetype = "php", target = "@include", first_arg = "x" })
    assert.is_nil(result)
  end)

  it("returns nil when the target is not a recognized directive", function()
    local result = directive.get_target({ filetype = "blade", target = "route", first_arg = "x" })
    assert.is_nil(result)
  end)
end)
