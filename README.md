# blade-nav.nvim

[![release version](https://img.shields.io/github/v/release/ricardoramirezr/blade-nav.nvim?style=plastic&labelColor=darkred&display_name=tag)](https://github.com/ricardoramirezr/blade-nav.nvim/releases)
[![CI Status](https://github.com/ricardoramirezr/blade-nav.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/ricardoramirezr/blade-nav.nvim/actions/workflows/ci.yml)
[![Coverage](https://codecov.io/gh/ricardoramirezr/blade-nav.nvim/branch/refactor/graph/badge.svg)](https://codecov.io/gh/ricardoramirezr/blade-nav.nvim)

Enhance your Laravel/Blade development experience in Neovim with powerful navigation, completion, and code analysis.

`blade-nav.nvim` simplifies moving between controllers, routes, configuration files, Blade views, components, and Inertia pages in Laravel applications by providing intelligent `gf` (go-to-file) functionality and autocompletion integration.

<p align="center">
    <a href="https://dotfyle.com/plugins/RicardoRamirezR/blade-nav.nvim">
        <img src="https://dotfyle.com/plugins/RicardoRamirezR/blade-nav.nvim/shield" />
    </a>
</p>

---

## Demo

https://github.com/user-attachments/assets/1b0aa688-93fe-4d87-b6ee-a6dbb96391ed

## Features

*   **Enhanced `gf` Navigation (`go-to-file`)**:
    *   Navigate seamlessly from references in your Blade, PHP, or Vue files directly to their corresponding target files.
    *   Supports standard Blade directives: `@include`, `@extends`, `@component`, `@each`, `@includeIf`, `@includeWhen`, `@includeUnless`, `@includeFirst`.
    *   Supports Livewire components: Navigate from `<livewire:component-name />` or `@livewire('component-name')` tags.
    *   Supports Laravel components: Navigate from `<x-component-name />` tags to their underlying Blade files or class definitions.
    *   Supports Laravel routes: Navigate from `route('route.name')` or `to_route('route.name')` calls to the corresponding controller method.
    *   Supports Laravel views: Navigate from `view('view.name')` calls.
    *   Supports Laravel Inertia: Navigate from `inertia('page.name')` or `Inertia::render('page.name')` calls to the corresponding Vue component (e.g., `resources/js/Pages/Page/Name.vue`).
    *   Supports Laravel configuration: Navigate from `config('app.key')` calls to the specific key within `config/app.php`.
    *   Supports Laravel environment variables: Navigate from `env('VAR_NAME')` calls.
    *   Supports navigation to imported Vue components within `.vue` files using `gf`.
    *   Falls back to standard Neovim `gf` behavior for unrecognized patterns.
*   **Autocompletion Integrations**:
    *   Provides smart completion items for Blade/Laravel constructs within `nvim-cmp`, `blink.cmp`, and `coq.nvim`.
    *   Offers completions for:
        *   Blade View Names (for `@include`, `@extends`, etc.)
        *   Laravel Route Names (for `route()`, `to_route()`)
        *   Livewire Component Names
        *   Laravel Component Names (aliases)
        *   Laravel Inertia Page Names (for `inertia()`, `Inertia::render()`)
        *   Laravel Configuration Keys (for `config()`)
        *   Laravel Environment Variables (for `env()`)
    *   Configurable inclusion of routes in completions.
*   **Display values as signature information**:
    *   Displays the config value in a floating window. 
    *   Displays the .env value in a floating window. 
*   **Display values as virtual text**:
    *   Displays all key values as virtual text.
*   **Vue Inertia Page Detection**:
    *   Identify and potentially navigate to Vue pages used within Inertia.js setups by parsing the page resolver configuration (e.g., in `app.js`).
*   **Flexible Configuration**:
    *   Enable/disable specific navigation/completion targets (views, routes, components, etc.).
    *   Enable/disable specific integrations (gf, cmp, blink, coq).
    *   Configure cache timeout for dynamic data (like routes).
    *   Specify additional directories to search for Laravel components.
    *   Toggle debug logging.
    *   Control tag closing behavior on completion.
*   **Performance**:
    *   Implements caching for potentially expensive operations like fetching route lists or view names, improving responsiveness.
    *   Includes cache invalidation mechanisms (e.g., triggered by `php artisan route:cache/clear`).
*   **Health Check**:
    *   Includes a health check command (`:checkhealth blade-nav`) to diagnose potential setup issues (missing dependencies, project detection, configuration status).

## Setup

```lua
require("blade-nav").setup({
  -- Auto-disable outside Laravel (default).
  -- To force load outside Laravel projects:
  -- force_enable = true,
})
```

### Detection heuristics

A project is considered **Laravel** if any of the following are true:
*   `artisan` file exists
*   `routes/web.php` exists
*   `resources/views` exists
*   `composer.json` requires `laravel/framework` or `laravel/lumen-framework`

---

## Navigation

### From Blade Views

*   Navigate to a parent view using `@extends('name')`
*   Navigate to included views using `@include('name')`
*   Open Blade components with `<x-name />`
*   Open Livewire components with `<livewire:name />` or `@livewire('name')`
*   Open components with `@component('name')`

### From Controllers and Routes

*   Open Blade views from controller or route definitions:
    *   `Route::view('url', 'name')`
    *   `View::make('name')`
    *   `view('name')`
*   Open Inertia pages from controller definitions:
    *   `inertia('page.name')`
    *   `Inertia::render('page.name')`

### From any PHP or Blade file

*   Jump to controllers using route names:
    *   `route('name')`
    *   `to_route('name')`
*   Jump to configuration files:
    *   `config('file.key')`

---

## Usage

1.  **Navigate to a Blade view or its class/Livewire component/Inertia page**:
    *   Place the cursor over the file name (e.g., in `@include('partials.header')`, `<x-button.primary />`, `inertia('User/Profile')`) and use the `gf` command.
    *   If the component view exists but no corresponding class does, it opens the view.
    *   If the class exists but not its view, it opens the class.
    *   If neither exists and it's a Livewire component, it presents the option to create the component using `php artisan make:livewire`.
    *   If neither exists and it's a Blade component, it can present options to:
        *   Create the view component
        *   Create the component via `php artisan make:component`
        *   (Optional) Create an Anonymous Index Component
2.  **Navigate to a controller associated with a route name**:
    *   Place the cursor over the route name and use `gf`.
3.  **Navigate to a configuration file or environment variable**:
    *   Place the cursor over the config key or env var name and use `gf`.
4.  **Navigate to a custom imported Vue component within a `.vue` file**:
    *   Place the cursor on the tag name of the imported component within the `<template>` section (e.g., `<MyCustomComponent />`).
    *   Use the `gf` command.
    *   BladeNav will parse the `<script>` section to find the corresponding `import` statement and open the imported component's `.vue` file.
5.  **Use completion sources**:
    *   Blade files:
        *   `@extends('`
        *   `@include('`
        *   `<x-`
        *   `<livewire:`
        *   `@livewire('`
    *   Controllers/Routes/Inertia:
        *   `Route::view('`
        *   `View::make('`
        *   `view('`
        *   `inertia('`
        *   `Inertia::render('`
    *   Any PHP/Blade file:
        *   `route('`
        *   `to_route('`
        *   `config('`
        *   `env('`

---

## Installation

Use your preferred Neovim plugin manager. Ensure you have `nvim-treesitter` installed and configured for `php` and `html` (for Blade).

### Using vim-plug

```vim
call plug#begin()
    Plug 'hrsh7th/nvim-cmp'                     " optional: cmp
    Plug 'ms-jpq/coq_nvim', { 'branch': 'coq' } " optional: coq
    Plug 'saghen/blink.cmp'                     " optional: blink.cmp
    Plug 'ricardoramirezr/blade-nav.nvim', {'for': ['blade', 'php']}
call plug#end()
lua << EOF
    require("blade-nav").setup({
      close_tag_on_complete = true, -- default: true
    })
EOF
```

### Using packer.nvim

```lua
use {
  "ricardoramirezr/blade-nav.nvim",
  requires = {
    "hrsh7th/nvim-cmp",                    -- optional: cmp
    { "ms-jpq/coq_nvim", branch = "coq" }, -- optional: coq
    "saghen/blink.cmp",                    -- optional: blink.cmp
  },
  ft = { "blade", "php" },
  config = function()
    require("blade-nav").setup({
      close_tag_on_complete = true, -- default: true
    })
  end,
}
```

### Using lazy.nvim

```lua
{
    'ricardoramirezr/blade-nav.nvim',
    dependencies = { -- optional
        'hrsh7th/nvim-cmp',                    -- optional: cmp
        { "ms-jpq/coq_nvim", branch = "coq" }, -- optional: coq
        'saghen/blink.cmp',                    -- optional: blink.cmp
    },
    ft = {'blade', 'php'}, -- improves startup time
    opts = {
        close_tag_on_complete = true, -- default: true
    },
}
```

---

## Configuration

BladeNav works out-of-the-box for standard Laravel projects. You can customize its behavior by passing an options table to the `setup` function.

Default configuration:

```lua
{
  enable = true, -- Master switch, automatically disabled if not a Laravel project (unless force_enable=true)
  cache_timeout = 50000, -- 50 seconds
  debug = false,
  close_tag_on_complete = true, -- For cmp/blink completion
  include_routes_in_cmp = true, -- Include route names in completion suggestions
  jsconfig_path = "./jsconfig.json", -- Path for Vue jsconfig (used for path aliases)
  laravel_components_paths = {}, -- List of additional directories to search for Laravel components (e.g., {"app/View/Components/"})
  force_enable = false, -- Force enable even if not auto-detected as Laravel project
  handlers = {
    component = true, -- Enable standard Laravel component resolution/navigation
    config = true, -- Enable config() and env() resolution/navigation
    directive = true, -- Enable Blade directive resolution/navigation
    inertia = true, -- Enable inertia() resolution/navigation
    livewire = true, -- Enable Livewire component resolution/navigation
    route = true, -- Enable route name resolution/navigation
    view = true, -- Enable view name resolution/navigation
  },
  integrations = {
    gf = true, -- Enable enhanced `gf` mapping
    cmp = true, -- Enable nvim-cmp integration
    blink = true, -- Enable blink.cmp integration
    coq = true, -- Enable coq.nvim integration
  }
}
```

### Extra Laravel component paths

Specify additional directories to search for Laravel components:

```lua
-- Using setup options (recommended)
require("blade-nav").setup({
  laravel_components_paths = {
    "app/View/Components/",
    "resources/views/common", -- Example custom path
  }
})

-- Or using legacy global variable (if configured before setup)
vim.g.blade_nav = {
  laravel_components = {
    "resources/views/common",
  },
}
```

### Disable routes completion

```lua
-- Using setup options (recommended)
require("blade-nav").setup({
  include_routes_in_cmp = false,
})

-- Or using legacy global variable (if configured before setup)
vim.g.blade_nav = {
  include_routes = false,
}
```

### With autopairs

If using an autopairs plugin that automatically closes tags, you might want to disable BladeNav's tag closing on completion:

```lua
require("blade-nav").setup({
  close_tag_on_complete = false, -- default: true
})
```

---

## Customization with nvim-cmp

```lua
local kind_icons = {
    BladeNav = "",
}

local cmp = require('cmp')

cmp.setup({
  formatting = {
    format = function(entry, item)
      if kind_icons[item.kind] then
        item.kind = string.format('%s %s', kind_icons[item.kind], item.kind)
      end
      return item
    end
  },
})
```

---

## Customization with blink.cmp

```lua
completion = {
  menu = {
    draw = {
      padding = { 0, 1 },
      components = {
        kind_icon = {
          text = function(ctx)
            local icon = ctx.kind_icon
            if ctx.source_name == 'Blade-nav' then
                icon = ''
            end
            return ' ' .. icon .. ctx.icon_gap .. ' '
          end,
          highlight = function(ctx)
            local hl = 'BlinkCmpKind' .. ctx.kind
            if ctx.source_name == 'Blade-nav' then
              hl = 'BlinkCmpKindBladeNav'
            end
            return hl
          end,
        },
      },
    },
  },
}
```

---

## Health

Run `:checkhealth blade-nav` to verify installation and setup.

---

## Contributing

Feel free to submit issues or pull requests to improve the plugin.

---

## License

MIT License. See the LICENSE file for details.

---

## Acknowledgments

Thanks to the Neovim and Laravel communities for their continuous support and contributions.
