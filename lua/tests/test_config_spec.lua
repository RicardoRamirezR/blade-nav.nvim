local function clear_blade_nav_modules()
  for k in pairs(package.loaded) do
    if k:match("^blade%-nav") then
      package.loaded[k] = nil
    end
  end
end

clear_blade_nav_modules()

local fixtures_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/fixtures"

local fs = require("blade-nav.utils.fs")
fs.get_root_dir = function()
  return fixtures_dir
end

local cache = require("blade-nav.utils.cache")
local config_extractor = require("blade-nav.extractors.config")
local env_extractor = require("blade-nav.extractors.env")

describe("Config extractor", function()
  before_each(function()
    cache.clear()
  end)

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
  before_each(function()
    cache.clear()
  end)

  it("reads .env keys", function()
    local keys = env_extractor.get_keys()
    assert(vim.tbl_contains(keys, "WHATSAPP_TOKEN"))
  end)

  it("reads .env key-value map", function()
    local map = env_extractor.get_map()
    assert.equals("alfa:beta:gama", map["WHATSAPP_TOKEN"])
    assert.equals("https://wa.local", map["WHATSAPP_SERVER"])
  end)
end)
