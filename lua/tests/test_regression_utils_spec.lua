-- lua/tests/test_regression_utils_spec.lua
-- Regression coverage for Wave-1 audit fixes in blade-nav.utils.* and
-- blade-nav.features.annotations.values (see .superpowers/sdd/task-7-brief.md).

local stub = require("luassert.stub")

describe("regression: fs.find_files is injection-safe (argv-based, no shell)", function()
  it("does not execute shell metacharacters embedded in a malicious path segment", function()
    local fs = require("blade-nav.utils.fs")
    local uv = vim.uv

    local tmpdir = uv.fs_mkdtemp("/tmp/blade-nav-injection-XXXXXX")
    assert.is_truthy(tmpdir)

    -- The path itself need not exist: a shell-based implementation would
    -- evaluate `$(touch ...)` while parsing the command string, regardless
    -- of whether the resulting "directory" is real. An argv-based
    -- implementation never invokes a shell, so it just fails to find this
    -- (nonexistent) path and returns gracefully.
    local marker = tmpdir .. "/pwned_marker"
    local malicious_path = tmpdir .. "/evil dir $(touch " .. marker .. ")"

    local ok, files = pcall(fs.find_files, malicious_path, "php")

    assert.is_true(ok, "fs.find_files raised an error instead of returning gracefully: " .. tostring(files))
    assert.is_nil(uv.fs_stat(marker), "shell metacharacters in the path were executed: marker file was created")

    uv.fs_rmdir(tmpdir)
  end)
end)

describe("regression: choice.select_file executes {label, cmd} entries via vim.system, not :edit", function()
  it("passes the argv table and cwd to vim.system, and never calls vim.cmd with the literal command", function()
    local choice = require("blade-nav.utils.choice")
    local fs = require("blade-nav.utils.fs")

    local root_dir_stub = stub(fs, "get_root_dir").returns("/fake/laravel/root")
    local system_stub = stub(vim, "system")
    local cmd_stub = stub(vim, "cmd")

    local entry = {
      label = "php artisan make:component Foo",
      cmd = { "php", "artisan", "make:component", "Foo" },
    }

    choice.select_file("Select component", { entry }, function() end)

    assert.stub(system_stub).was_called()
    assert.equals(1, #system_stub.calls)

    local call_args = system_stub.calls[1].refs
    assert.same({ "php", "artisan", "make:component", "Foo" }, call_args[1])
    assert.equals("/fake/laravel/root", call_args[2].cwd)

    assert.stub(cmd_stub).was_not_called()

    system_stub:revert()
    cmd_stub:revert()
    root_dir_stub:revert()
  end)
end)

describe("regression: inertia-path-extractor embedded test-case coverage (public API)", function()
  local extractor

  before_each(function()
    package.loaded["blade-nav.utils.inertia-path-extractor"] = nil
    extractor = require("blade-nav.utils.inertia-path-extractor")
  end)

  it("extracts from dynamic import() style", function()
    local content = [[resolve: name => import(`./Pages/${name}.vue`)]]
    assert.equals("Pages", extractor.extract_pages_path(content))
  end)

  it("extracts from definePages style", function()
    local content = [[resolve: name => definePages(`./Pages/${name}.vue`)]]
    assert.equals("Pages", extractor.extract_pages_path(content))
  end)

  it("returns INVALID_PATH for unsafe characters in the resolved path", function()
    local content = [[resolve: name => definePages(`./Pages<invalid>/${name}.vue`)]]
    local result, err = extractor.extract_pages_path(content)
    assert.is_nil(result)
    assert.equals(extractor.ErrorTypes.INVALID_PATH, err.type)
  end)
end)

describe("regression: vue-imports cache invalidates on changedtick change", function()
  it("re-parses and returns the updated import path after the buffer is modified", function()
    package.loaded["blade-nav.utils.vue-imports"] = nil
    local vue_imports = require("blade-nav.utils.vue-imports")

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.bo[bufnr].filetype = "vue"
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "<template>",
      "  <FooBar />",
      "</template>",
      "<script setup>",
      "import FooBar from './FooBarV1.vue'",
      "</script>",
    })
    vim.api.nvim_set_current_buf(bufnr)

    local ok1, parser1 = pcall(vim.treesitter.get_parser, bufnr, "vue")
    if ok1 and parser1 then
      pcall(function()
        parser1:parse()
      end)
    end

    local path1 = vue_imports.resolve_path_for("<FooBar />")
    assert.equals("./FooBarV1.vue", path1)

    -- Modify the buffer: changedtick bumps, so the cache key (bufnr..":"..changedtick)
    -- changes and the stale import map cannot leak through.
    vim.api.nvim_buf_set_lines(bufnr, 4, 5, false, {
      "import FooBar from './FooBarV2.vue'",
    })

    local ok2, parser2 = pcall(vim.treesitter.get_parser, bufnr, "vue")
    if ok2 and parser2 then
      pcall(function()
        parser2:parse()
      end)
    end

    local path2 = vue_imports.resolve_path_for("<FooBar />")
    assert.equals("./FooBarV2.vue", path2)
    assert.are_not.equal(path1, path2)

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)

describe("regression: annotations.values lazy query init", function()
  it("get_php_query() degrades to nil (not an error) when the parser/query is unavailable", function()
    package.loaded["blade-nav.features.annotations.values"] = nil

    local parse_stub = stub(vim.treesitter.query, "parse").invokes(function(lang)
      error("simulated: no parser available for lang: " .. tostring(lang))
    end)

    local ok_require, values = pcall(require, "blade-nav.features.annotations.values")
    assert.is_true(ok_require, "require() must not eagerly parse queries: " .. tostring(values))

    local ok_call, result = pcall(values.get_php_query)
    assert.is_true(ok_call, "get_php_query() must catch the parse failure internally")
    assert.is_nil(result)

    parse_stub:revert()
    -- Drop the module instance that memoized the simulated failure so later
    -- specs get a fresh (real) query on their next require.
    package.loaded["blade-nav.features.annotations.values"] = nil
  end)
end)
