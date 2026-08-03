local stub = require("luassert.stub")
local route = require("blade-nav.targets.route")
local laravel = require("blade-nav.utils.laravel")

describe("route handler", function()
  before_each(function()
    -- reset stubs/globals between tests
    package.loaded["blade-nav.utils.laravel"] = nil
    laravel = require("blade-nav.utils.laravel")
  end)

  it("returns nil if not a route reference", function()
    local ctx = { line = "echo 'foo';", cursor_col_1 = 5 }
    assert.is_nil(route.get_target(ctx))
  end)

  it("detects route name and resolves", function()
    stub(laravel, "normalize_route_name").returns("home")
    stub(laravel, "get_route_path").returns("routes/web.php")

    local ctx = { line = "route('home')", cursor_col_1 = 8 }
    local target = route.get_target(ctx)

    assert.is_table(target)
    assert.equals("route", target.type)

    laravel.normalize_route_name:revert()
    laravel.get_route_path:revert()
  end)
end)

describe("route handler resolve", function()
  local fs = require("blade-nav.utils.fs")
  local ts_utils = require("blade-nav.utils.treesitter")
  local log = require("blade-nav.utils.log")

  local tmpdir
  local controller_path

  local CONTROLLER_LINES = {
    "<?php",
    "",
    "class HomeController",
    "{",
    "    public function index()",
    "    {",
    "    }",
    "",
    "    function implicit()",
    "    {",
    "    }",
    "",
    "    protected function hidden()",
    "    {",
    "    }",
    "}",
  }

  local function write_controller()
    vim.fn.mkdir(tmpdir .. "/app/Http/Controllers", "p")
    vim.fn.writefile(CONTROLLER_LINES, controller_path)
  end

  before_each(function()
    -- reload both modules in sync so the spec's `laravel` table is the same
    -- instance route.lua captured at load time.
    package.loaded["blade-nav.targets.route"] = nil
    package.loaded["blade-nav.utils.laravel"] = nil
    route = require("blade-nav.targets.route")
    laravel = require("blade-nav.utils.laravel")

    tmpdir = vim.uv.fs_mkdtemp("/tmp/blade-nav-route-test-XXXXXX")
    assert.is_truthy(tmpdir)
    -- nvim resolves symlinks in buffer names (/tmp -> /private/tmp on macOS)
    tmpdir = vim.uv.fs_realpath(tmpdir) or tmpdir
    controller_path = tmpdir .. "/app/Http/Controllers/HomeController.php"
    write_controller()

    stub(fs, "get_root_dir").returns(tmpdir)
    stub(laravel, "get_route_list").returns({
      home = { controller = "App\\Http\\Controllers\\HomeController", method = "index" },
      implicit = { controller = "App\\Http\\Controllers\\HomeController", method = "implicit" },
      hidden = { controller = "App\\Http\\Controllers\\HomeController", method = "hidden" },
      closure = { controller = "Closure" },
    })
    -- trailing slash exercises the double-slash normalization
    stub(laravel, "get_psr4_mappings").returns({ ["App\\"] = "app/" })
  end)

  after_each(function()
    vim.cmd("silent! bwipeout!")
    fs.get_root_dir:revert()
    laravel.get_route_list:revert()
    laravel.get_psr4_mappings:revert()
    vim.fn.delete(tmpdir, "rf")
  end)

  it("opens the controller via an absolute root-based path (cwd-independent)", function()
    local ok = route.resolve({ type = "route", name = "home" })

    assert.is_true(ok)
    assert.equals(controller_path, vim.api.nvim_buf_get_name(0))
    -- public function index() is at line 5
    assert.equals(5, vim.api.nvim_win_get_cursor(0)[1])
  end)

  it("jumps to a method without an explicit visibility modifier (implicitly public)", function()
    local ok = route.resolve({ type = "route", name = "implicit" })

    assert.is_true(ok)
    assert.equals(controller_path, vim.api.nvim_buf_get_name(0))
    -- function implicit() is at line 9
    assert.equals(9, vim.api.nvim_win_get_cursor(0)[1])
  end)

  it("does not jump to a non-public method with the same name", function()
    local ok = route.resolve({ type = "route", name = "hidden" })

    assert.is_true(ok)
    assert.equals(controller_path, vim.api.nvim_buf_get_name(0))
    -- protected function hidden() must not be targeted; cursor stays put
    assert.are_not.equals(13, vim.api.nvim_win_get_cursor(0)[1])
  end)

  it("still reports success when method navigation fails (e.g. php parser missing)", function()
    stub(ts_utils, "gets_root_and_lang", function()
      error("no php parser")
    end)

    local ok, result = pcall(route.resolve, { type = "route", name = "home" })

    ts_utils.gets_root_and_lang:revert()

    assert.is_true(ok, "resolve() raised: " .. tostring(result))
    assert.is_true(result)
    assert.equals(controller_path, vim.api.nvim_buf_get_name(0))
  end)

  it("skips Closure routes silently (no controller warn, no edit)", function()
    local warn_stub = stub(log, "warn")
    local buf_before = vim.api.nvim_buf_get_name(0)

    local ok = route.resolve({ type = "route", name = "closure" })

    log.warn:revert()

    assert.is_false(ok)
    assert.stub(warn_stub).was_not_called()
    assert.equals(buf_before, vim.api.nvim_buf_get_name(0))
  end)
end)
