local config_extractor = require("blade-nav.extractors.config")
local env_extractor = require("blade-nav.extractors.env")

-- Force root to fixtures
package.loaded["blade-nav.utils.fs"] = nil
local fs = require("blade-nav.utils.fs")
function fs.get_root_dir()
  return vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h") .. "/fixtures"
end

describe("Config extractor", function()
  it("loads services.php keys", function()
    local keys = config_extractor.get_keys()
    assert(vim.tbl_contains(keys, "services.whatsapp.token"))
  end)

  it("resolves env references", function()
    local map = config_extractor.get_map()
    assert.equals("alfa:beta:gama", map["services.whatsapp.token"].text)
  end)

  it("resolves scalar values", function()
    local map = config_extractor.get_map()
    assert.equals("MyApp", map["app.name"].text)
    assert.equals("true", map["app.debug"].text)
  end)
end)

describe("Env extractor", function()
  it("reads .env keys", function()
    local keys = env_extractor.get_keys()
    assert(vim.tbl_contains(keys, "WHATSAPP_TOKEN"))
  end)
end)
