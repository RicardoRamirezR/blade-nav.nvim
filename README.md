# blade-nav.nvim
Navigating Blade views, components, routes, and configs within Laravel projects.

`blade-nav.nvim` is a Neovim plugin that enhances navigation within Laravel projects.  
It allows quick access to Blade views and their corresponding classes, navigation to the controller associated with a route name, and access to configuration files.  
This plugin simplifies moving between controllers, routes, configuration files, Blade views, and components in Laravel applications.

<p align="center">
  <a href="https://github.com/ricardoramirezr/blade-nav.nvim/releases">
    <img src="https://img.shields.io/github/v/release/ricardoramirezr/blade-nav.nvim?style=plastic&labelColor=darkred&display_name=tag" alt="release version">
  </a>
  <a href="https://github.com/ricardoramirezr/blade-nav.nvim/actions/workflows/ci.yml">
    <img src="https://github.com/ricardoramirezr/blade-nav.nvim/actions/workflows/ci.yml/badge.svg" alt="CI Status">
  </a>
  <a href="https://codecov.io/gh/ricardoramirezr/blade-nav.nvim">
    <img src="https://codecov.io/gh/ricardoramirezr/blade-nav.nvim/branch/refactor/graph/badge.svg" alt="Coverage">
  </a>
</p>

---

## Demo

### In a Blade view

![x-livewire](https://github.com/RicardoRamirezR/blade-nav.nvim/assets/6526545/8e10106f-d28e-40dc-b0df-c45f0f842980)

### From Controllers and Routes

![gf-view](https://github.com/RicardoRamirezR/blade-nav.nvim/assets/6526545/e6ddb3ec-829f-4055-b8d1-581635bfb18c)

<p align="center">
    <a href="https://dotfyle.com/plugins/RicardoRamirezR/blade-nav.nvim">
        <img src="https://dotfyle.com/plugins/RicardoRamirezR/blade-nav.nvim/shield" />
    </a>
</p>

---

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
- `artisan` file exists
- `routes/web.php` exists
- `resources/views` exists
- `composer.json` requires `laravel/framework` or `laravel/lumen-framework`

---

## Navigation

### From Blade Views

- Navigate to a parent view using `@extends('name')`
- Navigate to included views using `@include('name')`
- Open Blade components with `<x-name />`
- Open Livewire components with `<livewire:name />` or `@livewire('name')`
- Open components with `@component('name')`

### From Controllers and Routes

Open Blade views from controller or route definitions:
- `Route::view('url', 'name')`
- `View::make('name')`
- `view('name')`

### From any PHP or Blade file

- Jump to controllers using route names:
  - `route('name')`
  - `to_route('name')`
- Jump to configuration files:
  - `config('file.key')`

---

## Features

- Uses Neovim’s `gf` (goto file) command for navigation.
- Provides completion sources for:
  - [nvim-cmp](https://github.com/hrsh7th/nvim-cmp)
  - [coq](https://github.com/ms-jpq/coq_nvim)
  - [blink.cmp](https://github.com/Saghen/blink.cmp/)
- Supports Livewire components (v2 and v3).
- Supports Filament components.
- Supports custom paths for Blade components.
- Provides health checks via `:checkhealth blade-nav`.
- Offers artisan integration with `BladeNavInstallArtisanCommand`.

---
## Performance

To keep navigation fast in large Laravel projects, blade-nav.nvim uses an internal caching layer:

- Cached items:
  - Route names (from php artisan route:list)
  - View names (from resources/views scanning)
  - Config keys (from config/*.php)

- Benefits:
  - Significantly reduces filesystem scans.
  - Avoids repeated expensive Artisan calls.
  - Keeps completion sources responsive.

- Cache invalidation:
  - The cache is automatically invalidated when you run php artisan route:cache or php artisan route:clear.
  - Adding or modifying routes will refresh the route cache.
  - You can also clear cache manually with:
  - :lua require("blade-nav.utils.cache").clear_all()

---

## Installation

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
      cmp_close_tag = true, -- default: true
    })
EOF
```

### Using packer

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
      cmp_close_tag = true, -- default: true
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

## Usage

1. **Navigate to a Blade view or its class**:
   - Place the cursor over the file name and use the `gf` command.
   - If the component view exists but no corresponding class does, it opens the view.
   - If the class exists but not its view, it opens the class.
   - If neither exists and it’s a Livewire component, it presents the option to create the component using `php artisan make:livewire`.
   - If neither exists and it’s a Blade component, it can present options to:
     - Create the view component
     - Create the component via `php artisan make:component`
     - (Optional) Create an Anonymous Index Component

2. **Navigate to a controller associated with a route name**:
   - Place the cursor over the route name and use `gf`.

3. **Navigate to a configuration file**:
   - Place the cursor over the config name and use `gf`.

4. **Use completion sources**:
   - Blade files:
     - `@extends('`
     - `@include('`
     - `<x-`
     - `<livewire:`
     - `@livewire('`
   - Controllers/Routes:
     - `Route::view('`
     - `View::make('`
     - `view('`
   - Any PHP/Blade file:
     - `route('`
     - `to_route('`

---

## Configuration

- Works out of the box with `gf`.
- Provides completion support for:
  - **cmp**: `cmp-config.performance.max_view_entries`
  - **coq**: `coq_settings.match.max_results`
  - **blink.cmp**: `completion.list.max_items`

### Example for blink.cmp

```lua
require('blink.cmp').setup({
  sources = {
    default = { 'lsp', 'buffer', 'snippets', 'path', 'blade-nav' },
    providers = {
      ['blade-nav'] = {
        module = 'blade-nav.blink',
        opts = {
          close_tag_on_complete = true, -- default: true
        },
      },
    },
  }
})
```

### With autopairs

```lua
close_tag_on_complete = false -- default: true
```

### Extra Laravel component paths

```lua
vim.g.blade_nav = {
  laravel_components = {
    "resources/views/common",
  },
}
```

### Disable routes completion

```lua
vim.g.blade_nav = {
  include_routes = false,
}
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

