-- lua/tests/test_annotations_values_spec.lua
-- Behavioral coverage for blade-nav.features.annotations.values:
-- PHP + JS treesitter query captures, multibyte-safe truncate, invalidate_maps.

local values = require("blade-nav.features.annotations.values")
local env_extractor = require("blade-nav.extractors.env")
local config_extractor = require("blade-nav.extractors.config")
local lang_extractor = require("blade-nav.extractors.lang")

local function make_buffer(ft, lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].filetype = ft
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, ft)
  if ok and parser then
    pcall(function()
      parser:parse()
    end)
  end
  return bufnr
end

-- Collect { key, kind, default_value } entries for every match of the PHP
-- (or JS) calls query on the given buffer, keyed by extracted key so
-- assertions can look up a specific call regardless of match order.
local function collect_by_key(bufnr, for_each_tree, find_call_fn, query)
  local by_key = {}
  for_each_tree(bufnr, function(root, b)
    for _, match, _ in query:iter_matches(root, b) do
      local info = values.extract_call_info(query, match, b, find_call_fn)
      if info then
        by_key[info.key] = info
      end
    end
  end)
  return by_key
end

describe("annotations.values PHP query captures", function()
  it("extracts env/config/__/trans/Config::get/Config::set calls with correct kind", function()
    local bufnr = make_buffer("php", {
      "<?php",
      "function demo() {",
      "    env('API_TOKEN', 'default_token');",
      "    config('app.name');",
      "    __('messages.welcome');",
      "    trans('messages.bye');",
      "    Config::get('services.stripe.key', 'fallback');",
      "    Config::set('app.timezone', 'UTC');",
      "}",
    })

    local query = values.get_php_query()
    assert.is_not_nil(query, "PHP treesitter query should parse (php parser must be installed)")

    local by_key = collect_by_key(bufnr, values.for_each_php_tree, values.find_enclosing_call, query)

    assert.is_not_nil(by_key["API_TOKEN"])
    assert.equals("env", by_key["API_TOKEN"].kind)
    assert.equals("default_token", by_key["API_TOKEN"].default_value)

    assert.is_not_nil(by_key["app.name"])
    assert.equals("config", by_key["app.name"].kind)

    assert.is_not_nil(by_key["messages.welcome"])
    assert.equals("lang", by_key["messages.welcome"].kind)

    assert.is_not_nil(by_key["messages.bye"])
    assert.equals("lang", by_key["messages.bye"].kind)

    assert.is_not_nil(by_key["services.stripe.key"])
    assert.equals("config", by_key["services.stripe.key"].kind)
    assert.equals("fallback", by_key["services.stripe.key"].default_value)

    assert.is_not_nil(by_key["app.timezone"])
    assert.equals("config", by_key["app.timezone"].kind)

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)

describe("annotations.values JS query captures", function()
  it("extracts config/env/__/trans calls from a javascript buffer", function()
    local bufnr = make_buffer("javascript", {
      "config('app.name');",
      "env('API_KEY', 'default_val');",
      "__('messages.hello');",
      "trans('messages.hi');",
    })

    local query = values.get_js_query()
    assert.is_not_nil(query, "JS treesitter query should parse (javascript parser must be installed)")

    local by_key = collect_by_key(bufnr, values.for_each_js_tree, values.find_enclosing_js_call, query)

    assert.is_not_nil(by_key["app.name"])
    assert.equals("config", by_key["app.name"].kind)

    assert.is_not_nil(by_key["API_KEY"])
    assert.equals("env", by_key["API_KEY"].kind)
    assert.equals("default_val", by_key["API_KEY"].default_value)

    assert.is_not_nil(by_key["messages.hello"])
    assert.equals("lang", by_key["messages.hello"].kind)

    assert.is_not_nil(by_key["messages.hi"])
    assert.equals("lang", by_key["messages.hi"].kind)

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)

describe("annotations.values.truncate multibyte safety", function()
  it("truncates a multibyte string by character count, not byte count", function()
    -- "Última actividad": Ú is a 2-byte UTF-8 character. A naive byte-based
    -- truncate at n=5 would slice through the middle of "Ú" and corrupt it.
    local result = values.truncate("Última actividad", 5)
    assert.equals("Últi…", result)
    -- Sanity: 4 characters + ellipsis, but 5 bytes + ellipsis bytes (since Ú is 2 bytes).
    assert.equals(4, vim.fn.strchars("Últi"))
  end)

  it("returns the original string unchanged when shorter than the limit", function()
    assert.equals("short", values.truncate("short", 20))
  end)

  it("returns an empty string for nil input", function()
    assert.equals("", values.truncate(nil, 10))
  end)
end)

describe("annotations.values.invalidate_maps", function()
  before_each(function()
    values.invalidate_maps()
  end)

  after_each(function()
    values.invalidate_maps()
  end)

  it("memoizes get_env_map and refetches only after invalidate_maps", function()
    local calls = 0
    local original = env_extractor.get_map
    env_extractor.get_map = function()
      calls = calls + 1
      return { FOO = "bar" }
    end

    local m1 = values.get_env_map()
    local m2 = values.get_env_map()
    assert.equals(1, calls)
    assert.equals(m1, m2)

    values.invalidate_maps()
    values.get_env_map()
    assert.equals(2, calls)

    env_extractor.get_map = original
  end)

  it("memoizes get_cfg_map and refetches only after invalidate_maps", function()
    local calls = 0
    local original = config_extractor.get_map
    config_extractor.get_map = function()
      calls = calls + 1
      return { ["app.name"] = { kind = "scalar", text = "Demo" } }
    end

    values.get_cfg_map()
    values.get_cfg_map()
    assert.equals(1, calls)

    values.invalidate_maps()
    values.get_cfg_map()
    assert.equals(2, calls)

    config_extractor.get_map = original
  end)

  it("memoizes get_lang_map and refetches only after invalidate_maps", function()
    local calls = 0
    local original = lang_extractor.get_map
    lang_extractor.get_map = function()
      calls = calls + 1
      return { welcome = "Welcome!" }
    end

    values.get_lang_map()
    values.get_lang_map()
    assert.equals(1, calls)

    values.invalidate_maps()
    values.get_lang_map()
    assert.equals(2, calls)

    lang_extractor.get_map = original
  end)
end)
