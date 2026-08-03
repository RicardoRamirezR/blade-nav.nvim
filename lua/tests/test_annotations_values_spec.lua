-- lua/tests/test_annotations_values_spec.lua
-- Behavioral coverage for blade-nav.features.annotations.values:
-- PHP + JS treesitter query captures, multibyte-safe truncate, invalidate_maps.

local stub = require("luassert.stub")

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

  describe("get_env_map", function()
    local get_map_stub
    local calls

    before_each(function()
      calls = 0
      get_map_stub = stub(env_extractor, "get_map").invokes(function()
        calls = calls + 1
        return { FOO = "bar" }
      end)
    end)

    after_each(function()
      get_map_stub:revert()
    end)

    it("memoizes get_env_map and refetches only after invalidate_maps", function()
      local m1 = values.get_env_map()
      local m2 = values.get_env_map()
      assert.equals(1, calls)
      assert.equals(m1, m2)

      values.invalidate_maps()
      values.get_env_map()
      assert.equals(2, calls)
    end)
  end)

  describe("get_cfg_map", function()
    local get_map_stub
    local calls

    before_each(function()
      calls = 0
      get_map_stub = stub(config_extractor, "get_map").invokes(function()
        calls = calls + 1
        return { ["app.name"] = { kind = "scalar", text = "Demo" } }
      end)
    end)

    after_each(function()
      get_map_stub:revert()
    end)

    it("memoizes get_cfg_map and refetches only after invalidate_maps", function()
      values.get_cfg_map()
      values.get_cfg_map()
      assert.equals(1, calls)

      values.invalidate_maps()
      values.get_cfg_map()
      assert.equals(2, calls)
    end)
  end)

  describe("get_lang_map", function()
    local get_map_stub
    local calls

    before_each(function()
      calls = 0
      get_map_stub = stub(lang_extractor, "get_map").invokes(function()
        calls = calls + 1
        return { welcome = "Welcome!" }
      end)
    end)

    after_each(function()
      get_map_stub:revert()
    end)

    it("memoizes get_lang_map and refetches only after invalidate_maps", function()
      values.get_lang_map()
      values.get_lang_map()
      assert.equals(1, calls)

      values.invalidate_maps()
      values.get_lang_map()
      assert.equals(2, calls)
    end)
  end)
end)

describe("annotations.values query compile retry", function()
  -- A failed query compile (parser missing) must not be a one-shot flag:
  -- after :TSInstall the annotations should come alive without a restart,
  -- throttled so a missing parser does not cost a compile attempt per call.
  local orig_parse
  local orig_time
  local orig_loaded

  local function fresh_values()
    package.loaded["blade-nav.features.annotations.values"] = nil
    return require("blade-nav.features.annotations.values")
  end

  before_each(function()
    orig_parse = vim.treesitter.query.parse
    orig_time = os.time
    orig_loaded = package.loaded["blade-nav.features.annotations.values"]
  end)

  after_each(function()
    vim.treesitter.query.parse = orig_parse
    rawset(os, "time", orig_time)
    package.loaded["blade-nav.features.annotations.values"] = orig_loaded
  end)

  it("throttles retries of a failed compile within the retry interval", function()
    local attempts = 0
    vim.treesitter.query.parse = function()
      attempts = attempts + 1
      error("parser not installed")
    end

    local v = fresh_values()
    assert.is_nil(v.get_php_query())
    assert.equals(1, attempts)

    -- Immediate retry is throttled: no second compile attempt.
    assert.is_nil(v.get_php_query())
    assert.equals(1, attempts)

    assert.is_nil(v.get_js_query())
    assert.equals(2, attempts)
    assert.is_nil(v.get_js_query())
    assert.equals(2, attempts)
  end)

  it("retries after the interval and caches the success forever", function()
    local attempts = 0
    local fail = true
    vim.treesitter.query.parse = function(lang, src)
      attempts = attempts + 1
      if fail then
        error("parser not installed")
      end
      return orig_parse(lang, src)
    end

    local now = os.time()
    rawset(os, "time", function()
      return now
    end)

    local v = fresh_values()
    assert.is_nil(v.get_php_query())
    assert.equals(1, attempts)

    -- 31s later (e.g. after :TSInstall php) the compile is retried.
    fail = false
    rawset(os, "time", function()
      return now + 31
    end)

    local q = v.get_php_query()
    assert.is_not_nil(q, "retry after the throttle interval should compile the query")
    assert.equals(2, attempts)

    -- The success is cached: no further compile attempts.
    assert.equals(q, v.get_php_query())
    assert.equals(2, attempts)
  end)
end)
