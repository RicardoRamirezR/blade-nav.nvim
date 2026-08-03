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
  local root_dir_stub, system_stub, cmd_stub

  before_each(function()
    local fs = require("blade-nav.utils.fs")
    root_dir_stub = stub(fs, "get_root_dir").returns("/fake/laravel/root")
    system_stub = stub(vim, "system")
    cmd_stub = stub(vim, "cmd")
  end)

  after_each(function()
    system_stub:revert()
    cmd_stub:revert()
    root_dir_stub:revert()
  end)

  it("passes the argv table and cwd to vim.system, and never calls vim.cmd with the literal command", function()
    local choice = require("blade-nav.utils.choice")

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

    -- The buffer is unnamed, so relative imports resolve against the cwd.
    local cwd = vim.fn.getcwd()
    local path1 = vue_imports.resolve_path_for("<FooBar />")
    assert.equals(vim.fs.normalize(cwd .. "/FooBarV1.vue"), path1)

    -- Modify the buffer: changedtick bumps, so the per-buffer cache entry
    -- no longer matches and the stale import map cannot leak through.
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
    assert.equals(vim.fs.normalize(cwd .. "/FooBarV2.vue"), path2)
    assert.are_not.equal(path1, path2)

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)

describe("regression: Route::get definitions are not treated as route references", function()
  local ts_utils = require("blade-nav.utils.treesitter")

  it("extract_php_function_keys ignores Route::get('/users', ...) for the 'route' target", function()
    local keys =
      ts_utils.extract_php_function_keys([[<?php Route::get('/users', [UserController::class, 'index']);]], "route")
    assert.same({}, keys)
  end)

  it("still extracts real route-name references (route(), Redirect::route(), URL::route())", function()
    assert.same({ "users.show" }, ts_utils.extract_php_function_keys([[<?php route('users.show');]], "route"))
    assert.same({ "users.show" }, ts_utils.extract_php_function_keys([[<?php Redirect::route('users.show');]], "route"))
    assert.same({ "profile.edit" }, ts_utils.extract_php_function_keys([[<?php URL::route('profile.edit');]], "route"))
  end)

  it("keeps scoped-call behavior for other targets (View::make, Config::get)", function()
    assert.same(
      { "admin.dashboard" },
      ts_utils.extract_php_function_keys([[<?php View::make('admin.dashboard');]], "view")
    )
    assert.same({ "app.name" }, ts_utils.extract_php_function_keys([[<?php Config::get('app.name');]], "config"))
  end)
end)

describe("regression: treesitter key extractors degrade gracefully without parsers", function()
  local parser_stub

  after_each(function()
    if parser_stub then
      parser_stub:revert()
      parser_stub = nil
    end
  end)

  it("extract_php_function_keys returns {} instead of throwing when the php parser is unavailable", function()
    local ts_utils = require("blade-nav.utils.treesitter")
    parser_stub = stub(vim.treesitter, "get_string_parser").invokes(function()
      error("simulated: no php parser available")
    end)

    local ok, keys = pcall(ts_utils.extract_php_function_keys, "<?php route('home');", "route")
    assert.is_true(ok, "extract_php_function_keys must not throw: " .. tostring(keys))
    assert.same({}, keys)
  end)

  it("extract_keys_from_code returns {} instead of throwing when the blade parser is unavailable", function()
    local ts_utils = require("blade-nav.utils.treesitter")
    parser_stub = stub(vim.treesitter, "get_string_parser").invokes(function()
      error("simulated: no blade parser available")
    end)

    local ok, keys = pcall(ts_utils.extract_keys_from_code, "{{ route('home') }}", "route")
    assert.is_true(ok, "extract_keys_from_code must not throw: " .. tostring(keys))
    assert.same({}, keys)
  end)
end)

describe("regression: php_array_to_lua preserves order and handles escapes", function()
  local ts_utils = require("blade-nav.utils.treesitter")

  it("preserves source order across mixed quote styles", function()
    local directive, args = ts_utils.extract_first_blade_argument([[@includeFirst(['a', "b", 'c'])]], "@includeFirst")
    assert.equals("@includeFirst", directive)
    assert.same({ "a", "b", "c" }, args)
  end)

  it("handles backslash-escaped quotes inside strings", function()
    local _, args = ts_utils.extract_first_blade_argument([[@includeFirst(['it\'s', "plain"])]], "@includeFirst")
    assert.same({ "it's", "plain" }, args)
  end)
end)

describe("regression: routes.get_route_names async option never blocks on artisan", function()
  local routes = require("blade-nav.utils.laravel.routes")
  local cache = require("blade-nav.utils.cache")
  local fs = require("blade-nav.utils.fs")

  before_each(function()
    cache.clear_prefix("route_list:")
  end)

  it("returns currently-known (empty) names and primes async when not primed", function()
    local root = fs.get_root_dir()

    local start = vim.uv.hrtime()
    local names = routes.get_route_names({ async = true })
    local elapsed_ms = (vim.uv.hrtime() - start) / 1e6

    assert.same({}, names)
    -- Must be far below the synchronous artisan timeout (2000ms).
    assert.is_true(elapsed_ms < 1000, "async get_route_names blocked for " .. elapsed_ms .. "ms")
    -- The empty result is cached only under the short-TTL key, never long-term.
    assert.is_nil(cache.get("route_list:route_name:" .. root, math.huge))
    assert.is_not_nil(cache.get("route_list:route_name_empty:" .. root, 2000))
  end)

  it("derives names from the primed map without any artisan call once primed", function()
    local root = fs.get_root_dir()
    cache.set("route_list:primed:" .. root, {
      beta = { controller = "C", method = "m" },
      alpha = { controller = "C2" },
    })

    local names = routes.get_route_names({ async = true })
    assert.same({ "alpha", "beta" }, names)

    -- Non-empty results are cached long-term.
    assert.same({ "alpha", "beta" }, cache.get("route_list:route_name:" .. root, math.huge))
  end)

  it("does not serve another project's primed routes after the root changes", function()
    local root = fs.get_root_dir()
    cache.set("route_list:primed:" .. root, { foo = { controller = "X", method = "y" } })

    assert.is_nil(cache.get("route_list:primed:/some/other/project", math.huge))
  end)
end)

describe("regression: debounce tolerates uv.new_timer() failure", function()
  local new_timer_stub

  after_each(function()
    if new_timer_stub then
      new_timer_stub:revert()
      new_timer_stub = nil
    end
  end)

  it("still runs the debounced function (scheduled) when no timer handle is available", function()
    local debounce = require("blade-nav.utils.debounce")
    new_timer_stub = stub(vim.uv, "new_timer").returns(nil)

    local ran = false
    local debounced = debounce(function()
      ran = true
    end, 10)

    debounced()
    vim.wait(500, function()
      return ran
    end)
    assert.is_true(ran)
  end)

  it("debounce_per_key still runs the function when no timer handle is available", function()
    local debounce = require("blade-nav.utils.debounce")
    new_timer_stub = stub(vim.uv, "new_timer").returns(nil)

    local ran_key = nil
    local debounced = debounce.debounce_per_key(function(key)
      ran_key = key
    end, 10)

    debounced("k1")
    vim.wait(500, function()
      return ran_key ~= nil
    end)
    assert.equals("k1", ran_key)
  end)
end)

describe("regression: choice picker label handling", function()
  local root_dir_stub, cmd_stub

  before_each(function()
    local fs = require("blade-nav.utils.fs")
    root_dir_stub = stub(fs, "get_root_dir").returns("/fake/laravel/root")
    cmd_stub = stub(vim, "cmd")
  end)

  after_each(function()
    root_dir_stub:revert()
    cmd_stub:revert()
  end)

  it("sanitize only strips the picker's own leading ✓/✗ annotation, keeping marks inside filenames", function()
    local choice = require("blade-nav.utils.choice")

    -- Single choice short-circuits the picker and goes straight to open_file.
    -- (The edit argument is fnameescape'd, so check with plain string finds.)
    choice.select_file("Select file", { "resources/views/report ✓ final.blade.php" }, function() end)
    local edit_arg = cmd_stub.calls[1].refs[1]
    assert.is_truthy(edit_arg:find("✓", 1, true), "inner ✓ must be preserved: " .. edit_arg)
    assert.is_truthy(edit_arg:find("report", 1, true))

    cmd_stub:clear()
    choice.select_file("Select file", { "✓ resources/views/selected.blade.php" }, function() end)
    edit_arg = cmd_stub.calls[1].refs[1]
    assert.is_falsy(edit_arg:find("✓", 1, true), "leading annotation mark must be stripped: " .. edit_arg)
    assert.is_truthy(edit_arg:find("selected.blade.php", 1, true))
  end)

  it("resolves labels starting with 'N: ' to the correct original entry", function()
    local choice = require("blade-nav.utils.choice")

    local orig_ui_select = vim.ui.select
    vim.ui.select = function(items, _, cb)
      -- Pick the display string of the second entry.
      cb(items[2])
    end

    local selected
    choice.select("Select", { "1: keeps-colon", "plain" }, function(s)
      selected = s
    end)

    vim.ui.select = orig_ui_select
    assert.equals("plain", selected)
  end)

  it("run_command_choice passes a timeout to vim.system", function()
    local choice = require("blade-nav.utils.choice")
    local system_stub = stub(vim, "system")

    local entry = {
      label = "php artisan make:component Foo",
      cmd = { "php", "artisan", "make:component", "Foo" },
    }
    choice.select_file("Select component", { entry }, function() end)

    assert.stub(system_stub).was_called()
    assert.equals(30000, system_stub.calls[1].refs[2].timeout)
    system_stub:revert()
  end)
end)

describe("regression: vue-imports path resolution (H4)", function()
  local tmpdir
  local root_dir_stub

  local function write_file(path, content)
    local fd = assert(vim.uv.fs_open(path, "w", 420))
    vim.uv.fs_write(fd, content, -1)
    vim.uv.fs_close(fd)
  end

  local function vue_buffer(name, import_line)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, name)
    vim.bo[bufnr].filetype = "vue"
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "<template>",
      "  <FooBar />",
      "</template>",
      "<script setup>",
      import_line,
      "</script>",
    })
    vim.api.nvim_set_current_buf(bufnr)
    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "vue")
    if ok and parser then
      pcall(function()
        parser:parse()
      end)
    end
    return bufnr
  end

  before_each(function()
    package.loaded["blade-nav.utils.vue-imports"] = nil
    require("blade-nav.core.config").setup({})

    tmpdir = vim.uv.fs_mkdtemp("/tmp/blade-nav-vue-test-XXXXXX")
    assert.is_truthy(tmpdir)
    -- macOS resolves /tmp to /private/tmp; compare against the real path.
    tmpdir = vim.uv.fs_realpath(tmpdir) or tmpdir
    vim.fn.mkdir(tmpdir .. "/src/components", "p")

    local fs = require("blade-nav.utils.fs")
    root_dir_stub = stub(fs, "get_root_dir").returns(tmpdir)
  end)

  after_each(function()
    root_dir_stub:revert()
    vim.fn.delete(tmpdir, "rf")
    package.loaded["blade-nav.utils.vue-imports"] = nil
  end)

  it("resolves relative imports against the importing buffer's directory, not the cwd", function()
    local vue_imports = require("blade-nav.utils.vue-imports")
    write_file(tmpdir .. "/src/components/FooBar.vue", "<template></template>")

    local bufnr = vue_buffer(tmpdir .. "/src/App.vue", "import FooBar from './components/FooBar.vue'")
    local path = vue_imports.resolve_path_for("<FooBar />")
    vim.api.nvim_buf_delete(bufnr, { force = true })

    assert.equals(vim.fs.normalize(tmpdir .. "/src/components/FooBar.vue"), path)
  end)

  it("probes extensions for extensionless imports and <name>/index.<ext> style", function()
    local vue_imports = require("blade-nav.utils.vue-imports")
    write_file(tmpdir .. "/src/components/FooBar.vue", "<template></template>")

    local bufnr = vue_buffer(tmpdir .. "/src/App.vue", "import FooBar from './components/FooBar'")
    local path = vue_imports.resolve_path_for("<FooBar />")
    vim.api.nvim_buf_delete(bufnr, { force = true })
    assert.equals(vim.fs.normalize(tmpdir .. "/src/components/FooBar.vue"), path)

    vim.fn.mkdir(tmpdir .. "/src/components/BazQux", "p")
    write_file(tmpdir .. "/src/components/BazQux/index.vue", "<template></template>")

    bufnr = vue_buffer(tmpdir .. "/src/App.vue", "import FooBar from './components/BazQux'")
    path = vue_imports.resolve_path_for("<FooBar />")
    vim.api.nvim_buf_delete(bufnr, { force = true })
    assert.equals(vim.fs.normalize(tmpdir .. "/src/components/BazQux/index.vue"), path)
  end)

  it("resolves jsconfig aliases to root-absolute paths and survives empty alias arrays", function()
    local vue_imports = require("blade-nav.utils.vue-imports")
    write_file(
      tmpdir .. "/jsconfig.json",
      vim.json.encode({
        compilerOptions = {
          paths = {
            ["@/*"] = { "resources/js/*" },
            ["@empty/*"] = {},
          },
        },
      })
    )
    vim.fn.mkdir(tmpdir .. "/resources/js/components", "p")
    write_file(tmpdir .. "/resources/js/components/FooBar.vue", "<template></template>")

    local bufnr = vue_buffer(tmpdir .. "/src/App.vue", "import FooBar from '@/components/FooBar.vue'")
    local path = vue_imports.resolve_path_for("<FooBar />")
    vim.api.nvim_buf_delete(bufnr, { force = true })
    assert.equals(vim.fs.normalize(tmpdir .. "/resources/js/components/FooBar.vue"), path)

    -- An alias mapping to an empty array must not crash; the import is left as-is.
    bufnr = vue_buffer(tmpdir .. "/src/App.vue", "import FooBar from '@empty/components/FooBar.vue'")
    local ok, raw = pcall(vue_imports.resolve_path_for, "<FooBar />")
    vim.api.nvim_buf_delete(bufnr, { force = true })
    assert.is_true(ok, tostring(raw))
    assert.equals("@empty/components/FooBar.vue", raw)
  end)

  it("invalidates the jsconfig cache when the file mtime changes", function()
    local vue_imports = require("blade-nav.utils.vue-imports")
    local jsconfig = tmpdir .. "/jsconfig.json"
    write_file(jsconfig, vim.json.encode({ compilerOptions = { paths = { ["@/*"] = { "resources/js/*" } } } }))

    local bufnr = vue_buffer(tmpdir .. "/src/App.vue", "import FooBar from '@/components/FooBar.vue'")
    local path1 = vue_imports.resolve_path_for("<FooBar />")
    assert.equals(vim.fs.normalize(tmpdir .. "/resources/js/components/FooBar.vue"), path1)

    -- Rewrite jsconfig with a different alias target and bump the mtime.
    write_file(jsconfig, vim.json.encode({ compilerOptions = { paths = { ["@/*"] = { "assets/*" } } } }))
    local stat = assert(vim.uv.fs_stat(jsconfig))
    vim.uv.fs_utime(jsconfig, stat.atime.sec, stat.mtime.sec + 5)

    -- Bump the buffer changedtick so imports re-parse from the new config.
    vim.api.nvim_buf_set_lines(bufnr, 4, 5, false, { "import FooBar from '@/components/FooBar.vue' // v2" })
    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "vue")
    if ok and parser then
      pcall(function()
        parser:parse()
      end)
    end

    local path2 = vue_imports.resolve_path_for("<FooBar />")
    vim.api.nvim_buf_delete(bufnr, { force = true })
    assert.equals(vim.fs.normalize(tmpdir .. "/assets/components/FooBar.vue"), path2)
  end)
end)

describe("regression: annotations.values lazy query init", function()
  local parse_stub

  before_each(function()
    package.loaded["blade-nav.features.annotations.values"] = nil
    parse_stub = stub(vim.treesitter.query, "parse").invokes(function(lang)
      error("simulated: no parser available for lang: " .. tostring(lang))
    end)
  end)

  after_each(function()
    parse_stub:revert()
    -- Drop the module instance that memoized the simulated failure so later
    -- specs get a fresh (real) query on their next require.
    package.loaded["blade-nav.features.annotations.values"] = nil
  end)

  it("get_php_query() degrades to nil (not an error) when the parser/query is unavailable", function()
    local ok_require, values = pcall(require, "blade-nav.features.annotations.values")
    assert.is_true(ok_require, "require() must not eagerly parse queries: " .. tostring(values))

    local ok_call, result = pcall(values.get_php_query)
    assert.is_true(ok_call, "get_php_query() must catch the parse failure internally")
    assert.is_nil(result)
  end)
end)
