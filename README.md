# blade-nav.nvim

[![release version](https://img.shields.io/github/v/release/ricardoramirezr/blade-nav.nvim?style=plastic&labelColor=darkred&display_name=tag)](https://github.com/ricardoramirezr/blade-nav.nvim/releases)
[![CI Status](https://github.com/ricardoramirezr/blade-nav.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/ricardoramirezr/blade-nav.nvim/actions/workflows/ci.yml)

Powerful navigation, completion, and inline value display for Laravel projects in Neovim.

Jump between controllers, routes, config files, Blade views, components, Inertia pages, and localization files with `gf`. See resolved config, env, and translation values as virtual text. Get smart completions for every Laravel construct.

<p align="center">
    <a href="https://dotfyle.com/plugins/RicardoRamirezR/blade-nav.nvim">
        <img src="https://dotfyle.com/plugins/RicardoRamirezR/blade-nav.nvim/shield" />
    </a>
</p>

## Demo

https://github.com/user-attachments/assets/1b0aa688-93fe-4d87-b6ee-a6dbb96391ed

## Features

### Navigation (`gf`)

Place your cursor on any reference and press `gf`:

| Context | Supported patterns |
|---|---|
| **Blade directives** | `@include`, `@extends`, `@component`, `@each`, `@includeIf`, `@includeWhen`, `@includeUnless`, `@includeFirst` |
| **Blade components** | `<x-button />`, `<x-input.date />` |
| **Livewire** | `<livewire:name />`, `@livewire('name')` |
| **Routes** | `route('name')`, `to_route('name')` |
| **Views** | `view('name')`, `View::make('name')`, `Route::view('url', 'name')` |
| **Inertia** | `inertia('Page/Name')`, `Inertia::render('Page/Name')` |
| **Config** | `config('app.key')`, `Config::get('key')`, `Config::set('key')` |
| **Environment** | `env('APP_KEY')` |
| **Translations** | `__('messages.welcome')`, `trans('messages.welcome')` |
| **Vue imports** | `<MyComponent />` (resolves from `<script>` imports in `.vue` files) |

Falls back to standard Neovim `gf` for unrecognized patterns.

### Completions

Smart completion items for `nvim-cmp`, `blink.cmp`, and `coq.nvim`:

| Trigger | What completes |
|---|---|
| `@include('`, `@extends('`, `@component('` | Blade view names |
| `<x-` | Component names |
| `<livewire:`, `@livewire('` | Livewire component names |
| `route('`, `to_route('` | Route names |
| `view('`, `View::make('`, `Route::view('` | View names |
| `inertia('`, `Inertia::render('` | Inertia page names |
| `config('`, `Config::get('`, `Config::set('` | Config keys |
| `env('` | Environment variable names |
| `__('`, `trans('` | Translation keys |

### Annotations (inline values)

Resolved values for `config()`, `env()`, `__()`, `trans()`, `Config::get()`, and `Config::set()` displayed as virtual text next to each call.

Works in PHP, Blade, and embedded JavaScript contexts.

**Commands:**

| Command | Description |
|---|---|
| `:BladeNavToggleShowValues` | Toggle virtual text annotations on/off |
| `:BladeNavClearCache` | Clear all cached config, env, and translation maps |

**Keymaps** (when `annotations.create_keymaps = true`, the default):

| Key | Action |
|---|---|
| `K` | Show resolved value in floating window (with LSP fallback) |
| `<leader>bv` | Toggle annotations |
| `<leader>bcc` | Clear cache |

For `__()` and `trans()` calls, `K` opens a floating window showing the translation across all locales.

---

## Installation

Requires Neovim >= 0.11 and `nvim-treesitter` with `php` and `html` parsers.

### lazy.nvim

```lua
{
    'ricardoramirezr/blade-nav.nvim',
    dependencies = { -- optional, for nvim-cmp integration
        'hrsh7th/nvim-cmp',
    },
    ft = { 'blade', 'php' },
    opts = {},
}
```

For blink.cmp users, no dependency is needed. See [blink.cmp configuration](#blinkcmp) below.

### vim-plug

```vim
call plug#begin()
    Plug 'hrsh7th/nvim-cmp'                      " optional
    Plug 'ricardoramirezr/blade-nav.nvim', { 'for': ['blade', 'php'] }
call plug#end()
lua require("blade-nav").setup()
```

### packer.nvim

```lua
use {
    'ricardoramirezr/blade-nav.nvim',
    requires = {
        'hrsh7th/nvim-cmp', -- optional
    },
    ft = { 'blade', 'php' },
    config = function()
        require('blade-nav').setup()
    end,
}
```

---

## Configuration

Works out of the box. All options and their defaults:

```lua
require('blade-nav').setup({
    -- Master switch. Auto-disabled outside Laravel unless force_enable = true.
    enable = true,
    force_enable = false,

    cache_timeout = 50000,            -- Cache TTL in ms
    debug = false,

    -- Completion behavior (applies to nvim-cmp, blink.cmp, and coq.nvim)
    close_tag_on_complete = true,
    include_routes_in_cmp = true,

    -- Inertia
    inertia_pages_path = nil,         -- nil = "Pages" (default)
    inertia_extensions = { 'vue', 'tsx', 'jsx', 'ts' },

    -- Vue
    jsconfig_path = './jsconfig.json',

    -- Extra directories for <x-component> resolution
    laravel_components_paths = {},

    -- Navigation targets (gf)
    handlers = {
        directive = true,
        view      = true,
        livewire  = true,
        route     = true,
        config    = true,
        component = true,
        inertia   = true,
        vue       = true,
        lang      = true,
    },

    -- Completion/integration sources
    integrations = {
        gf  = true,
        cmp = true,
        coq = true,
    },

    -- Inline value annotations
    annotations = {
        show           = false,       -- Start with annotations visible
        hl             = 'Comment',   -- Highlight group for virtual text
        prefix         = ' ⟶ ',      -- Prefix before each value
        max_len        = 160,         -- Max display length before truncation
        debounce_ms    = 120,         -- Debounce for re-rendering on edits
        show_on_load   = true,        -- Render annotations when a buffer loads
        create_keymaps = true,        -- Create K, <leader>bv, <leader>bcc maps
    },
})
```

### Laravel detection

A project is detected as Laravel if any of these are true:
- `artisan` file exists
- `routes/web.php` exists
- `resources/views/` directory exists
- `composer.json` requires `laravel/framework` or `laravel/lumen-framework`

Set `force_enable = true` to skip detection.

---

## Customization

### nvim-cmp

```lua
local kind_icons = {
    BladeNav = "",
}

require('cmp').setup({
    formatting = {
        format = function(entry, item)
            if kind_icons[item.kind] then
                item.kind = string.format('%s %s', kind_icons[item.kind], item.kind)
            end
            return item
        end,
    },
})
```

### blink.cmp

Register blade-nav as a source provider in your blink.cmp config:

```lua
require('blink.cmp').setup({
    sources = {
        default = { 'lsp', 'blade-nav', 'snippets', 'path', 'buffer' },
        providers = {
            ['blade-nav'] = {
                name = 'blade-nav',
                module = 'blade-nav.integrations.blink',
            },
        },
    },
})
```

To customize the icon:

```lua
completion = {
    menu = {
        draw = {
            components = {
                kind_icon = {
                    text = function(ctx)
                        if ctx.source_name == 'blade-nav' then
                            return ' '
                        end
                        return ctx.kind_icon
                    end,
                    highlight = function(ctx)
                        if ctx.source_name == 'blade-nav' then
                            return 'BlinkCmpKindBladeNav'
                        end
                        return 'BlinkCmpKind' .. ctx.kind
                    end,
                },
            },
        },
    },
}
```

### Extra component paths

```lua
require('blade-nav').setup({
    laravel_components_paths = {
        'app/View/Components/',
        'resources/views/common',
    },
})
```

### With autopairs

If your autopairs plugin closes tags automatically:

```lua
require('blade-nav').setup({
    close_tag_on_complete = false,
})
```

---

## Commands

| Command | Description |
|---|---|
| `:BladeNavToggleShowValues` | Toggle inline config/env/translation annotations |
| `:BladeNavClearCache` | Clear all caches (config, env, translations, routes, views) |
| `:BladeNavInstallArtisanCommand` | Install the BladeNav artisan command into your Laravel project |
| `:checkhealth blade-nav` | Diagnose setup issues |

---

## Health

Run `:checkhealth blade-nav` to verify:
- Treesitter parsers installed
- Laravel project detected
- PHP and artisan available
- Integration status (cmp, blink, coq)
- Handler configuration

---

## Contributing

Issues and pull requests welcome at [GitHub](https://github.com/ricardoramirezr/blade-nav.nvim).

## License

MIT. See [LICENSE](LICENSE).
