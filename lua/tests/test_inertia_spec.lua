local stub = require("luassert.stub")

local function clear_blade_nav_modules()
  for k in pairs(package.loaded) do
    if k:match("^blade%-nav") then
      package.loaded[k] = nil
    end
  end
end

describe("Inertia path extractor", function()
  local extractor

  before_each(function()
    clear_blade_nav_modules()
    extractor = require("blade-nav.utils.inertia-path-extractor")
  end)

  it("extracts Pages from resolvePageComponent", function()
    local content = [[resolvePageComponent(`./Pages/${name}.vue`, import.meta.glob('./Pages/**/*.vue'))]]
    assert.equals("Pages", extractor.extract_pages_path(content))
  end)

  it("extracts from Vite eager glob", function()
    local content = [[const pages = import.meta.glob('./Pages/**/*.vue', { eager: true })]]
    assert.equals("Pages", extractor.extract_pages_path(content))
  end)

  it("extracts from Vite standard glob", function()
    local content = [[const pages = import.meta.glob('./Pages/**/*.vue')]]
    assert.equals("Pages", extractor.extract_pages_path(content))
  end)

  it("extracts from webpack require", function()
    local content = [[resolve: name => require(`./Pages/${name}`)]]
    assert.equals("Pages", extractor.extract_pages_path(content))
  end)

  it("extracts custom path", function()
    local content = [[resolvePageComponent(`./Views/${name}.vue`, import.meta.glob('./Views/**/*.vue'))]]
    assert.equals("Views", extractor.extract_pages_path(content))
  end)

  it("returns nil for no match", function()
    local result, err = extractor.extract_pages_path("no inertia here")
    assert.is_nil(result)
    assert.equals("NO_MATCH", err.type)
  end)

  it("allows paths with .. for monorepo support", function()
    local content = [[resolvePageComponent(`../packages/pages/${name}.vue`)]]
    local result = extractor.extract_pages_path(content)
    assert.is_not_nil(result)
  end)
end)

describe("Inertia target handler", function()
  local inertia, config, cache

  before_each(function()
    clear_blade_nav_modules()
    config = require("blade-nav.core.config")
    config.setup()
    cache = require("blade-nav.utils.cache")
    cache.clear()
    inertia = require("blade-nav.targets.inertia")
  end)

  describe("get_target", function()
    it("returns reverse target for vue filetype in Pages dir", function()
      -- Simulate being in a Pages vue file
      local bufnr = vim.api.nvim_create_buf(false, true)
      local fixtures_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/fixtures"
      vim.api.nvim_buf_set_name(bufnr, fixtures_dir .. "/resources/js/Pages/Dashboard.vue")
      vim.api.nvim_set_current_buf(bufnr)

      local fs = require("blade-nav.utils.fs")
      local root_dir_stub = stub(fs, "get_root_dir").returns(fixtures_dir)

      local result = inertia.get_target({ filetype = "vue", line = "<template>" })
      assert.is_not_nil(result)
      assert.equals("inertia_reverse", result.type)
      assert.equals("Dashboard", result.name)

      root_dir_stub:revert()
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("returns nil for vue file outside Pages dir", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(bufnr, "/some/other/Component.vue")
      vim.api.nvim_set_current_buf(bufnr)

      local result = inertia.get_target({ filetype = "vue", line = "<template>" })
      assert.is_nil(result)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("returns target from context.first_arg", function()
      local result = inertia.get_target({
        filetype = "php",
        target = "inertia",
        first_arg = "Dashboard",
        line = "inertia('Dashboard')",
      })
      assert.equals("inertia", result.type)
      assert.equals("Dashboard", result.name)
    end)

    it("returns target for Inertia::render", function()
      local result = inertia.get_target({
        filetype = "php",
        target = "Inertia::render",
        first_arg = "Admin/Users",
        line = "Inertia::render('Admin/Users')",
      })
      assert.equals("inertia", result.type)
      assert.equals("Admin/Users", result.name)
    end)

    it("ignores non-inertia targets", function()
      local result = inertia.get_target({
        filetype = "php",
        target = "view",
        first_arg = "home",
        line = "view('home')",
      })
      assert.is_nil(result)
    end)

    it("preserves dot notation in name", function()
      local result = inertia.get_target({
        filetype = "php",
        target = "inertia",
        first_arg = "Admin.Dashboard",
        line = "inertia('Admin.Dashboard')",
      })
      assert.equals("Admin.Dashboard", result.name)
    end)

    it("extracts the page name after a nested pages directory at any depth", function()
      clear_blade_nav_modules()
      config = require("blade-nav.core.config")
      config.setup({ inertia_pages_path = "src/Pages" })
      cache = require("blade-nav.utils.cache")
      cache.clear()
      inertia = require("blade-nav.targets.inertia")

      local fixtures_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/fixtures"
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(bufnr, fixtures_dir .. "/resources/js/src/Pages/Home.vue")
      vim.api.nvim_set_current_buf(bufnr)

      local fs = require("blade-nav.utils.fs")
      local root_dir_stub = stub(fs, "get_root_dir").returns(fixtures_dir)

      local result = inertia.get_target({ filetype = "vue", line = "<template>" })

      root_dir_stub:revert()
      vim.api.nvim_buf_delete(bufnr, { force = true })

      assert.is_not_nil(result)
      assert.equals("inertia_reverse", result.type)
      assert.equals("Home", result.name)
    end)
  end)

  describe("reverse lookup", function()
    it("anchors the grep pattern with a closing quote and excludes vendor/", function()
      local fs = require("blade-nav.utils.fs")
      local cmd = require("blade-nav.utils.cmd")

      local captured
      local root_dir_stub = stub(fs, "get_root_dir").returns("/fake/root")
      local cmd_exists_stub = stub(fs, "command_exists", function(c)
        return c == "grep"
      end)
      local exec_stub = stub(cmd, "execute_silent", function(argv)
        captured = argv
        return "", false
      end)

      local ok = inertia.resolve({ type = "inertia_reverse", name = "Admin/User" })

      root_dir_stub:revert()
      cmd_exists_stub:revert()
      exec_stub:revert()

      assert.is_false(ok)
      assert.is_table(captured)
      assert.is_true(vim.tbl_contains(captured, "--exclude-dir=vendor"))
      local pattern = captured[#captured - 1]
      -- 'Admin/User' must not also match 'Admin/UserList': closing quote anchor
      assert.is_truthy(pattern:find([=[Admin/User['"]]=], 1, true), "missing closing anchor in: " .. pattern)
      assert.is_truthy(pattern:find([=[Admin\.User['"]]=], 1, true), "missing dot-notation anchor in: " .. pattern)
    end)

    it("caches the reverse lookup per buffer so repeat gf does not re-grep", function()
      local fs = require("blade-nav.utils.fs")
      local cmd = require("blade-nav.utils.cmd")

      local calls = 0
      local root_dir_stub = stub(fs, "get_root_dir").returns("/fake/root")
      local cmd_exists_stub = stub(fs, "command_exists", function(c)
        return c == "grep"
      end)
      local exec_stub = stub(cmd, "execute_silent", function()
        calls = calls + 1
        return "", false
      end)

      inertia.resolve({ type = "inertia_reverse", name = "Admin/User" })
      inertia.resolve({ type = "inertia_reverse", name = "Admin/User" })

      root_dir_stub:revert()
      cmd_exists_stub:revert()
      exec_stub:revert()

      assert.equals(1, calls, "expected a single grep for repeated gf on the same page")
    end)
  end)

  describe("page path resolution", function()
    it("handles an empty inertia_extensions table without erroring", function()
      clear_blade_nav_modules()
      config = require("blade-nav.core.config")
      config.setup({ inertia_extensions = {} })
      cache = require("blade-nav.utils.cache")
      cache.clear()
      inertia = require("blade-nav.targets.inertia")

      local fs = require("blade-nav.utils.fs")
      local root_dir_stub = stub(fs, "get_root_dir").returns("/fake/root")

      local ok, result = pcall(inertia.resolve, { type = "inertia", name = "Home" })

      root_dir_stub:revert()

      assert.is_true(ok, "resolve() raised: " .. tostring(result))
      assert.is_false(result)
    end)

    it("probes Page/index.<ext> when resolving a page name", function()
      local tmpdir = vim.uv.fs_mkdtemp("/tmp/blade-nav-inertia-test-XXXXXX")
      assert.is_truthy(tmpdir)
      tmpdir = vim.uv.fs_realpath(tmpdir) or tmpdir

      vim.fn.mkdir(tmpdir .. "/resources/js/Pages/Profile", "p")
      vim.fn.writefile({ "<template></template>" }, tmpdir .. "/resources/js/Pages/Profile/index.vue")

      local fs = require("blade-nav.utils.fs")
      local root_dir_stub = stub(fs, "get_root_dir").returns(tmpdir)

      local ok = inertia.resolve({ type = "inertia", name = "Profile" })

      root_dir_stub:revert()

      assert.is_true(ok)
      assert.equals(tmpdir .. "/resources/js/Pages/Profile/index.vue", vim.api.nvim_buf_get_name(0))

      vim.cmd("silent! bwipeout!")
      vim.fn.delete(tmpdir, "rf")
    end)
  end)

  describe("capabilities", function()
    it("reports correct targets", function()
      local caps = inertia.get_capabilities()
      assert.is_true(vim.tbl_contains(caps.targets, "inertia"))
      assert.is_true(vim.tbl_contains(caps.targets, "Inertia::render"))
    end)

    it("supports php and vue filetypes", function()
      local caps = inertia.get_capabilities()
      assert.is_true(vim.tbl_contains(caps.filetypes, "php"))
      assert.is_true(vim.tbl_contains(caps.filetypes, "vue"))
    end)
  end)

  describe("config defaults", function()
    it("has inertia_extensions in default config", function()
      local extensions = config.get("inertia_extensions")
      assert.is_table(extensions)
      assert.is_true(vim.tbl_contains(extensions, "vue"))
      assert.is_true(vim.tbl_contains(extensions, "tsx"))
    end)

    it("has nil inertia_pages_path by default", function()
      assert.is_nil(config.get("inertia_pages_path"))
    end)

    it("respects user-configured pages path", function()
      clear_blade_nav_modules()
      config = require("blade-nav.core.config")
      config.setup({ inertia_pages_path = "CustomPages" })
      assert.equals("CustomPages", config.get("inertia_pages_path"))
    end)

    it("respects user-configured extensions", function()
      clear_blade_nav_modules()
      config = require("blade-nav.core.config")
      config.setup({ inertia_extensions = { "tsx", "vue" } })
      local exts = config.get("inertia_extensions")
      assert.equals("tsx", exts[1])
      assert.equals("vue", exts[2])
    end)
  end)

  describe("pages path resolution", function()
    it("uses config override when set", function()
      config.set("inertia_pages_path", "MyPages")
      cache.clear()

      -- get_target should work regardless of pages path
      local result = inertia.get_target({
        filetype = "php",
        target = "inertia",
        first_arg = "Home",
        line = "inertia('Home')",
      })
      assert.equals("Home", result.name)
    end)
  end)
end)
