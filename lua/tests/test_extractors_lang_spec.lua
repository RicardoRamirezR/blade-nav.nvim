-- lua/tests/test_extractors_lang_spec.lua
-- Behavioral coverage for blade-nav.extractors.lang: merged PHP + JSON
-- translation maps, and per-locale maps across locale variants (e.g. pt_BR).
--
-- Fixtures live under lua/fixtures/lang/:
--   lang/en.json          -> { welcome = "Welcome!", greeting = "Hello" }
--   lang/en/messages.php  -> { bye = "Goodbye" }
--   lang/pt_BR.json       -> { welcome = "Bem-vindo!" }

local fs = require("blade-nav.utils.fs")
local cache = require("blade-nav.utils.cache")
local lang = require("blade-nav.extractors.lang")

describe("extractors.lang", function()
  local fixtures_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/fixtures"
  local orig_get_root_dir

  before_each(function()
    orig_get_root_dir = fs.get_root_dir
    fs.get_root_dir = function()
      return fixtures_dir
    end
    cache.clear()
  end)

  after_each(function()
    fs.get_root_dir = orig_get_root_dir
    lang.stop_watcher()
    cache.clear()
  end)

  it("get_map() merges JSON and PHP translations for the default locale", function()
    local map = lang.get_map()
    assert.equals("Welcome!", map["welcome"])
    assert.equals("Hello", map["greeting"])
    assert.equals("Goodbye", map["messages.bye"])
  end)

  it("get_keys() returns sorted keys from the merged default-locale map", function()
    local keys = lang.get_keys()
    assert.is_true(vim.tbl_contains(keys, "welcome"))
    assert.is_true(vim.tbl_contains(keys, "messages.bye"))
  end)

  it("get_translation() looks up a single key from the default-locale map", function()
    assert.equals("Welcome!", lang.get_translation("welcome"))
    assert.is_nil(lang.get_translation("does.not.exist"))
  end)

  it("get_map_all_locales() keeps each locale variant (including pt_BR) separate", function()
    local maps = lang.get_map_all_locales()

    assert.is_not_nil(maps["en"])
    assert.equals("Welcome!", maps["en"]["welcome"])
    assert.equals("Goodbye", maps["en"]["messages.bye"])

    assert.is_not_nil(maps["pt_BR"], "expected pt_BR locale variant to be discovered")
    assert.equals("Bem-vindo!", maps["pt_BR"]["welcome"])

    -- Locale variants are independent: pt_BR has no PHP-sourced key.
    assert.is_nil(maps["pt_BR"]["messages.bye"])
  end)
end)
