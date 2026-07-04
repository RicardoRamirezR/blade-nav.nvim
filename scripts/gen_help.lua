-- scripts/gen_help.lua
-- Generates doc/blade-nav.txt from the structured tables defined below.
-- This does NOT parse README.md: the content here is the source of truth
-- for reference documentation, while README.md stays the marketing/usage
-- doc. The option tables mirror `default_config` in
-- lua/blade-nav/core/config.lua; keep both in sync by hand when that
-- table changes.
--
-- Run via `make docs`, i.e. `nvim --headless -l scripts/gen_help.lua`.

local OUTFILE = "doc/blade-nav.txt"
local WIDTH = 78

--------------------------------------------------------------------------------
-- Layout helpers
--------------------------------------------------------------------------------

local function rule()
  return string.rep("=", WIDTH)
end

--- Right-align `tag` on the same line as `left`, keeping at least two
--- spaces between them when there's room.
local function tagline(left, tag)
  left = left or ""
  local pad = WIDTH - #left - #tag
  if pad < 1 then
    pad = 1
  end
  return left .. string.rep(" ", pad) .. tag
end

--- Word-wraps `text` to `WIDTH - indent` columns, prefixing every produced
--- line with `indent` spaces. Treats `text` as a single paragraph.
local function wrap(text, indent)
  indent = indent or 0
  local prefix = string.rep(" ", indent)
  local width = WIDTH - indent
  local lines = {}
  local line = nil
  for word in text:gmatch("%S+") do
    if not line then
      line = word
    elseif #line + 1 + #word <= width then
      line = line .. " " .. word
    else
      table.insert(lines, prefix .. line)
      line = word
    end
  end
  if line then
    table.insert(lines, prefix .. line)
  end
  return lines
end

local L = {}

local function add(line)
  table.insert(L, line or "")
end

local function add_wrapped(text, indent)
  for _, line in ipairs(wrap(text, indent)) do
    add(line)
  end
end

--- Starts a new top-level section: a rule, the right-aligned heading/tag,
--- and a blank line.
local function section(heading, tag)
  add(rule())
  add(tagline(heading, "*" .. tag .. "*"))
  add("")
end

--------------------------------------------------------------------------------
-- Content: source-of-truth tables
--------------------------------------------------------------------------------

local TOC = {
  { "1. Introduction", "blade-nav-introduction" },
  { "2. Requirements", "blade-nav-requirements" },
  { "3. Setup", "blade-nav-setup" },
  { "4. Configuration", "blade-nav-configuration" },
  { "5. Laravel detection", "blade-nav-laravel-detection" },
  { "6. Navigation (gf)", "blade-nav-navigation" },
  { "7. Annotations (inline values)", "blade-nav-annotations" },
  { "8. Hover (K)", "blade-nav-hover" },
  { "9. Commands", "blade-nav-commands" },
  { "10. Health", "blade-nav-health" },
  { "11. About", "blade-nav-about" },
}

local REQUIREMENTS = {
  "Neovim >= 0.11.",
  "nvim-treesitter with the `php`, `blade`, `vue`, and `html` parsers"
    .. " installed (checked by `:checkhealth blade-nav`).",
  "A Laravel project, auto-detected (see |blade-nav-laravel-detection|),"
    .. " or `force_enable = true` to skip detection.",
  "Optional: `php` and `artisan` on PATH, used by" .. " `:BladeNavInstallArtisanCommand` and related health checks.",
  "Optional: one of nvim-cmp, blink.cmp, or coq.nvim for completion (only"
    .. " the engines enabled in `integrations` are used).",
}

-- Top-level keys of `default_config` in lua/blade-nav/core/config.lua.
local OPTIONS = {
  {
    key = "enable",
    type = "boolean",
    default = "true",
    desc = "Master on/off switch. Auto-disabled outside a Laravel project unless `force_enable` is `true`.",
  },
  {
    key = "force_enable",
    type = "boolean",
    default = "false",
    desc = "Skip Laravel-project auto-detection (|blade-nav-laravel-detection|) and force the plugin on.",
  },
  {
    key = "cache_timeout",
    type = "number",
    default = "50000",
    desc = "Cache time-to-live, in milliseconds, for cached routes, views, config, and translation lookups.",
  },
  {
    key = "debug",
    type = "boolean",
    default = "false",
    desc = "Print verbose debug/info logging (visible in `:messages`).",
  },
  {
    key = "jsconfig_path",
    type = "string",
    default = '"./jsconfig.json"',
    desc = "Path to `jsconfig.json`, used to resolve Vue import aliases.",
  },
  {
    key = "close_tag_on_complete",
    type = "boolean",
    default = "true",
    desc = "Automatically close `<x-component>` tags after completion (nvim-cmp, blink.cmp, coq.nvim).",
  },
  {
    key = "include_routes_in_cmp",
    type = "boolean",
    default = "true",
    desc = "Include Laravel route names among completion results.",
  },
  {
    key = "inertia_pages_path",
    type = "string|nil",
    default = "nil",
    desc = 'Override the Inertia pages directory. `nil` resolves to "Pages".',
  },
  {
    key = "inertia_extensions",
    type = "table",
    default = '{ "vue", "tsx", "jsx", "ts" }',
    desc = "File extensions tried, in order, when resolving Inertia page components.",
  },
  {
    key = "laravel_components_paths",
    type = "table",
    default = "{}",
    desc = "Extra directories searched when resolving `<x-component>` tags.",
  },
}

local HANDLERS = {
  {
    key = "directive",
    default = "true",
    desc = "`@include`, `@extends`, `@component`, `@each`, and related directives.",
  },
  { key = "view", default = "true", desc = "`view()`, `View::make()`, `Route::view()`." },
  { key = "livewire", default = "true", desc = "`<livewire:name />`, `@livewire('name')`." },
  { key = "route", default = "true", desc = "`route('name')`, `to_route('name')`." },
  { key = "config", default = "true", desc = "`config('key')`, `env('KEY')`, `Config::get()`, `Config::set()`." },
  { key = "component", default = "true", desc = "`<x-button />`, `<x-input.date />`." },
  { key = "inertia", default = "true", desc = "`inertia('Page/Name')`, `Inertia::render('Page/Name')`." },
  { key = "vue", default = "true", desc = "`<MyComponent />`, resolved from `<script>` imports." },
  { key = "lang", default = "true", desc = "`__('key')`, `trans('key')`." },
}

local INTEGRATIONS = {
  { key = "gf", default = "true", desc = "Enhanced `gf` navigation (|blade-nav-navigation|)." },
  { key = "cmp", default = "true", desc = "nvim-cmp completion source." },
  { key = "coq", default = "true", desc = "coq.nvim completion source." },
}

local ANNOTATIONS = {
  { key = "show", type = "boolean", default = "false", desc = "Start with inline value annotations visible." },
  { key = "hl", type = "string", default = '"Comment"', desc = "Highlight group used for the virtual text." },
  { key = "prefix", type = "string", default = '" ⟶ "', desc = "Text inserted before each resolved value." },
  {
    key = "max_len",
    type = "number",
    default = "160",
    desc = "Maximum displayed length of a resolved value before truncation.",
  },
  {
    key = "debounce_ms",
    type = "number",
    default = "120",
    desc = "Debounce interval, in milliseconds, for re-rendering annotations after buffer changes.",
  },
  {
    key = "show_on_load",
    type = "boolean",
    default = "true",
    desc = "Render annotations as soon as a matching buffer loads.",
  },
  {
    key = "create_keymaps",
    type = "boolean",
    default = "true",
    desc = "Create the `K`, `<leader>bv`, and `<leader>bcc` keymaps (|blade-nav-annotations|).",
  },
}

local LARAVEL_DETECTION = {
  "`artisan` exists at the project root.",
  "`routes/web.php` exists.",
  "`resources/views/` exists.",
  "`composer.json` requires `laravel/framework` or `laravel/lumen-framework`.",
}

local NAV_PATTERNS = {
  {
    label = "Blade directives",
    handler = "handlers.directive",
    patterns = "@include, @extends, @component, @each, @includeIf, @includeWhen, @includeUnless, @includeFirst",
  },
  { label = "Blade components", handler = "handlers.component", patterns = "<x-button />, <x-input.date />" },
  { label = "Livewire", handler = "handlers.livewire", patterns = "<livewire:name />, @livewire('name')" },
  { label = "Routes", handler = "handlers.route", patterns = "route('name'), to_route('name')" },
  {
    label = "Views",
    handler = "handlers.view",
    patterns = "view('name'), View::make('name'), Route::view('url', 'name')",
  },
  {
    label = "Inertia",
    handler = "handlers.inertia",
    patterns = "inertia('Page/Name'), Inertia::render('Page/Name')",
  },
  {
    label = "Config / Environment",
    handler = "handlers.config",
    patterns = "config('app.key'), env('APP_KEY'), Config::get('key'), Config::set('key')",
  },
  {
    label = "Translations",
    handler = "handlers.lang",
    patterns = "__('messages.welcome'), trans('messages.welcome')",
  },
  {
    label = "Vue imports",
    handler = "handlers.vue",
    patterns = "<MyComponent /> (resolved from <script> imports in .vue files)",
  },
}

local COMMANDS = {
  {
    name = "BladeNavInstallArtisanCommand",
    desc = "Copies the bundled BladeNav.php artisan command into"
      .. " app/Console/Commands/BladeNav.php, rewriting its namespace to"
      .. ' match the project\'s PSR-4 "App\\" mapping. Installs the'
      .. " blade-nav:components-aliases artisan command, used to discover"
      .. " component aliases registered by third-party packages.",
  },
  {
    name = "BladeNavClearCache",
    desc = "Clears BladeNav's cached routes, views, config, env, and"
      .. " translation lookups (|blade-nav.cache_timeout|).",
  },
  {
    name = "BladeNavToggleShowValues",
    desc = "Toggles the inline config/env/translation value annotations"
      .. " (|blade-nav-annotations|) on or off for all open buffers.",
  },
}

local HEALTH_CHECKS = {
  "Environment: Neovim version, OS, PHP, and Artisan.",
  "Tree-sitter: `php`, `blade`, `vue`, and `html` parsers installed.",
  "External commands: `php`, `fd`, `find` availability.",
  "Project structure: Laravel detection, composer.json, resources/views, vendor/composer/autoload_psr4.php.",
  "BladeNav artisan command: whether it's installed and up to date.",
  "Configuration: loaded options summary.",
  "Integrations: enabled vs. available completion engines.",
  "Routes and views: cold/warm cache timing.",
}

--------------------------------------------------------------------------------
-- Renderers
--------------------------------------------------------------------------------

--- Renders one `key`/`type`/`default`/`desc` entry as a definition-list-style
--- vimdoc block, tagged `*tag_prefix.key*`.
local function render_option(tag_prefix, opt)
  add(tagline(opt.key, "*" .. tag_prefix .. "." .. opt.key .. "*"))
  add(string.rep(" ", 8) .. "Type: " .. (opt.type or "boolean") .. "    Default: " .. opt.default)
  add("")
  add_wrapped(opt.desc, 8)
  add("")
end

local function render_toc()
  section("Contents", "blade-nav-contents")
  for _, entry in ipairs(TOC) do
    local label, tag = entry[1], entry[2]
    local left = "    " .. label .. " "
    local dots_len = WIDTH - #left - #tag - 2 - 1
    if dots_len < 3 then
      dots_len = 3
    end
    add(left .. string.rep(".", dots_len) .. " |" .. tag .. "|")
  end
  add("")
end

local function render_introduction()
  section(TOC[1][1], TOC[1][2])
  add(tagline("", "*blade-nav*"))
  add_wrapped(
    "BladeNav.nvim adds Laravel-aware navigation, completion, and inline"
      .. " value annotations to Neovim. Jump between controllers, routes,"
      .. " config files, Blade views, components, Inertia pages, and"
      .. " localization files with `gf`. See resolved config, env, and"
      .. " translation values as virtual text or via `K`. Get completions"
      .. " for Laravel constructs through nvim-cmp, blink.cmp, or coq.nvim.",
    0
  )
  add("")
end

local function render_requirements()
  section(TOC[2][1], TOC[2][2])
  for _, req in ipairs(REQUIREMENTS) do
    add_wrapped("- " .. req, 0)
  end
  add("")
end

local function render_setup()
  section(TOC[3][1], TOC[3][2])
  add_wrapped(
    "BladeNav needs no setup call to work with its defaults: it lazy-loads"
      .. " itself the first time a `blade`, `php`, or `vue` buffer is"
      .. " opened, calling `setup()` if it hasn't run yet and the project"
      .. " passes Laravel detection (|blade-nav-laravel-detection|).",
    0
  )
  add("")
  add_wrapped("Call `setup()` yourself (e.g. from your plugin manager's `opts` or `config`) to pass custom options:", 0)
  add("")
  add(">")
  add("    require('blade-nav').setup({")
  add("      -- your options here, see |blade-nav-configuration|")
  add("    })")
  add("<")
  add("")
end

local function render_configuration()
  section(TOC[4][1], TOC[4][2])
  add_wrapped(
    "Every option below is type-checked against its declared type; a"
      .. " mismatch prints a `vim.notify` warning naming the offending key"
      .. " and the expected type, without stopping `setup()`.",
    0
  )
  add("")

  add("Top-level options ~")
  add("")
  for _, opt in ipairs(OPTIONS) do
    render_option("blade-nav", opt)
  end

  add(tagline("handlers", "*blade-nav.handlers*"))
  add(string.rep(" ", 8) .. "Type: table<string, boolean>")
  add("")
  add_wrapped("Enable or disable individual `gf`/completion target handlers (|blade-nav-navigation|):", 8)
  add("")
  for _, opt in ipairs(HANDLERS) do
    render_option("blade-nav.handlers", opt)
  end

  add(tagline("integrations", "*blade-nav.integrations*"))
  add(string.rep(" ", 8) .. "Type: table<string, boolean>")
  add("")
  add_wrapped("Enable or disable per-engine integrations:", 8)
  add("")
  for _, opt in ipairs(INTEGRATIONS) do
    render_option("blade-nav.integrations", opt)
  end
  add_wrapped(
    "blink.cmp is supported through a separate provider module"
      .. " (`blade-nav.integrations.blink`) registered directly in your"
      .. " blink.cmp config; it has no `integrations` flag of its own.",
    8
  )
  add("")

  add(tagline("annotations", "*blade-nav.annotations*"))
  add(string.rep(" ", 8) .. "Type: table")
  add("")
  add_wrapped("Inline value annotations, see |blade-nav-annotations| and |blade-nav-hover|:", 8)
  add("")
  for _, opt in ipairs(ANNOTATIONS) do
    render_option("blade-nav.annotations", opt)
  end
end

local function render_laravel_detection()
  section(TOC[5][1], TOC[5][2])
  add_wrapped("A project is auto-detected as Laravel if any of the following are true:", 0)
  add("")
  for _, rule_text in ipairs(LARAVEL_DETECTION) do
    add_wrapped("- " .. rule_text, 0)
  end
  add("")
  add_wrapped("Set |blade-nav.force_enable| to `true` to skip detection and force the plugin on regardless.", 0)
  add("")
end

local function render_navigation()
  section(TOC[6][1], TOC[6][2])
  add_wrapped(
    "Position the cursor over a reference and press `gf`. BladeNav tries to"
      .. " resolve it first, gated by the matching |blade-nav.handlers| flag:",
    0
  )
  add("")
  for _, row in ipairs(NAV_PATTERNS) do
    add("    " .. row.label .. " (|blade-nav." .. row.handler .. "|)")
    add_wrapped(row.patterns, 8)
    add("")
  end
  add_wrapped(
    "If no target is recognized or resolved, BladeNav falls back to your"
      .. " own global `gf` mapping (looked up at invocation time, so other"
      .. " plugins' `gf` mappings keep working), or Neovim's built-in `gf`"
      .. " otherwise. The mapping only applies to `blade`, `php`, and `vue`"
      .. " buffers, and is skipped where a buffer already has its own"
      .. " custom `gf` mapping.",
    0
  )
  add("")
  add_wrapped(
    "The same handlers back completion sources for nvim-cmp, blink.cmp,"
      .. " and coq.nvim (see |blade-nav.integrations|).",
    0
  )
  add("")
end

local function render_annotations()
  section(TOC[7][1], TOC[7][2])
  add_wrapped(
    "Resolved values for `config()`, `env()`, `__()`, `trans()`,"
      .. " `Config::get()`, and `Config::set()` calls are displayed as"
      .. " virtual text next to each call, styled with"
      .. " |blade-nav.annotations.hl| and |blade-nav.annotations.prefix|."
      .. " Applies to `php`, `blade`, `html`, `javascript`, and `vue` buffers.",
    0
  )
  add("")
  add_wrapped("Keymaps (created when |blade-nav.annotations.create_keymaps| is `true`, the default):", 0)
  add("")
  add("    K            Show the resolved value, see |blade-nav-hover|.")
  add("    <leader>bv   Toggle annotations, same as |:BladeNavToggleShowValues|.")
  add("    <leader>bcc  Clear caches, same as |:BladeNavClearCache|.")
  add("")
end

local function render_hover()
  section(TOC[8][1], TOC[8][2])
  add_wrapped(
    "Pressing `K` on a `config()`, `env()`, `__()`, `trans()`," .. " `Config::get()`, or `Config::set()` call:",
    0
  )
  add("")
  add_wrapped(
    "- Requests `textDocument/hover` from any attached LSP client that"
      .. " advertises `hoverProvider`, and shows its response in a"
      .. " floating window.",
    0
  )
  add_wrapped(
    "- Falls back to a floating window with BladeNav's own resolved value"
      .. " when no client responds with hover content.",
    0
  )
  add_wrapped(
    "- For `__()`/`trans()` keys, shows the value across every detected"
      .. " locale in the floating window instead of a single value.",
    0
  )
  add("")
  add_wrapped(
    "When |blade-nav.annotations.show| is enabled, `K` also forces a"
      .. " synchronous re-render of the buffer's inline annotations,"
      .. " instead of the normal background-queued render.",
    0
  )
  add("")
end

local function render_commands()
  section(TOC[9][1], TOC[9][2])
  for _, c in ipairs(COMMANDS) do
    add(tagline("", "*:" .. c.name .. "*"))
    add(":" .. c.name)
    add_wrapped(c.desc, 8)
    add("")
  end
end

local function render_health()
  section(TOC[10][1], TOC[10][2])
  add_wrapped("Run `:checkhealth blade-nav` to check:", 0)
  add("")
  for _, check in ipairs(HEALTH_CHECKS) do
    add_wrapped("- " .. check, 0)
  end
  add("")
end

local function render_about()
  section(TOC[11][1], TOC[11][2])
  add_wrapped(
    "This reference covers configuration options and commands. For"
      .. " installation snippets (lazy.nvim, packer.nvim, vim-plug) and"
      .. " completion-engine customization recipes, see the project"
      .. " README at:",
    0
  )
  add("")
  add("    https://github.com/ricardoramirezr/blade-nav.nvim")
  add("")
  add_wrapped("License: MIT.", 0)
  add("")
end

--------------------------------------------------------------------------------
-- Assemble
--------------------------------------------------------------------------------

add(tagline("*blade-nav.txt*", "BladeNav.nvim"))
add_wrapped("Laravel-aware navigation, completion, and inline value annotations for Neovim.", 0)
add("")

render_toc()
render_introduction()
render_requirements()
render_setup()
render_configuration()
render_laravel_detection()
render_navigation()
render_annotations()
render_hover()
render_commands()
render_health()
render_about()

add(rule())
add("vim:tw=78:ts=8:ft=help:norl:")

local generated_text = table.concat(L, "\n") .. "\n"

--------------------------------------------------------------------------------
-- Write (idempotent: only touches the file when content actually changed)
--------------------------------------------------------------------------------

vim.fn.mkdir(vim.fn.fnamemodify(OUTFILE, ":h"), "p")

local existing_text = nil
do
  local f = io.open(OUTFILE, "r")
  if f then
    existing_text = f:read("*a")
    f:close()
  end
end

if existing_text == generated_text then
  print(OUTFILE .. " is already up to date.")
  return
end

local out, err = io.open(OUTFILE, "w")
if not out then
  io.stderr:write("Failed to open " .. OUTFILE .. " for writing: " .. tostring(err) .. "\n")
  os.exit(1)
end

out:write(generated_text)
out:close()
print(OUTFILE .. " generated.")
