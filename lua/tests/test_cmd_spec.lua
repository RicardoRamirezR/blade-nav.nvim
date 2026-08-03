-- lua/tests/test_cmd_spec.lua
-- Coverage for blade-nav.utils.cmd.artisan_argv(): artisan invocations must
--- redirect PHP error output to stderr so stdout stays machine-parseable
-- (e.g. `php artisan route:list --json` under PHP >= 8.4, where deprecation
-- notices would otherwise pollute stdout and break JSON decoding).

local cmd = require("blade-nav.utils.cmd")

describe("cmd.artisan_argv", function()
  it("prepends php with display_errors=stderr before artisan args", function()
    local argv = cmd.artisan_argv({ "route:list", "--json" })
    assert.same({ "php", "-d", "display_errors=stderr", "artisan", "route:list", "--json" }, argv)
  end)

  it("does not mutate the given args list", function()
    local args = { "--version" }
    cmd.artisan_argv(args)
    assert.same({ "--version" }, args)
  end)
end)
