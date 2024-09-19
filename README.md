# blade-nav.nvim
Navigating Blade views, components, routes and configs within Laravel projects

`blade-nav.nvim` is a Neovim plugin designed to enhance navigation within 
Laravel projects. It allows quick access to Blade views and their corresponding
classes, enables navigation to the controller associated with a route name, and
to configuration files.
This plugin simplifies moving between controllers, routes, configuration files,
Blade views, and components in Laravel applications.

<p align="center">
  <a href="https://github.com/ricardoramirezr/blade-nav.nvim/releases">
    <img src="https://img.shields.io/github/v/release/ricardoramirezr/blade-nav.nvim?style=plastic&labelColor=darkred&display_name=tag" alt="release version">
  </a>
</p>

## In a Blade view

![x-livewire](https://github.com/RicardoRamirezR/blade-nav.nvim/assets/6526545/8e10106f-d28e-40dc-b0df-c45f0f842980)

## From Controller and Routes

![gf-view](https://github.com/RicardoRamirezR/blade-nav.nvim/assets/6526545/e6ddb3ec-829f-4055-b8d1-581635bfb18c)

<p align="center">
    <a href="https://dotfyle.com/plugins/RicardoRamirezR/blade-nav.nvim">
        <img src="https://dotfyle.com/plugins/RicardoRamirezR/blade-nav.nvim/shield" />
    </a>
</p>

## Navigation

### From Blade View

- Navigate to the parent view using `@extends('name')`
- Navigate to included views using `@include('name')`
- Open Blade components using `<x-name />`
- Open Livewire components using `<livewire:name />` or `@livewire('name')`

### From Controllers and Routes:

Open Blade views from controller or route definitions like 
- `Route::view('url', 'name')`
- `View::make('name')`
- `view('name')`

### From any PHP or Blade file:
- Open the controller associated with the route name: `route('name')` or `to_route('name')`
- Open configuration files using `config('file.key')`

## Features

- Utilizes the `gf` (goto file) command for navigation.
- Provides a custom source for [nvim-cmp](https://github.com/hrsh7th/nvim-cmp)
  (requires installation and configuration) for component selection.
- Provides a custom source for [coq](https://github.com/ms-jpq/coq_nvim) (requires
  installation and configuration).
- Has support for Livewire components v2 and v3.
- Has support for Filament components.
- Provides support for additional paths for Laravel Blade components.

## Installation

To get started with `blade-nav.nvim`, add the plugin to your `init.lua` or `init.vim` file:

**Using packer**:

```lua
use {
  "ricardoramirezr/blade-nav.nvim",
  requires = {
    "hrsh7th/nvim-cmp",                    -- if using nvim-cmp
    { "ms-jpq/coq_nvim", branch = "coq" }, -- if using coq
  },
  ft = { "blade", "php" },
  config = function()
    require("blade-nav").setup({
      cmp_close_tag = true, -- default: true
    })
  end,
}
```
    
**Using lazy**:

```lua
{
    'ricardoramirezr/blade-nav.nvim',
    dependencies = { -- totally optional
        'hrsh7th/nvim-cmp', -- if using nvim-cmp
        { "ms-jpq/coq_nvim", branch = "coq" }, -- if using coq
    },
    ft = {'blade', 'php'} -- optional, improves startup time
    opts = {
        close_tag_on_complete = true, -- default: true
    },
}
```

## Usage

1. **To navigate to a Blade view or its corresponding class**:

  - Place the cursor over the file name and use the `gf` command.
    - If the component view exists but there is no corresponding class, it 
    opens the view file.
    - If the class exists but not its view, the class is opened.
    - If neither exists and is a Livewire component, it presents the option to
    create the component using `php artisan make:livewire`.
    - If neither exists and is a Blade component, it can present two or three
    options, depending on the component type. The options are, create the view
    component and cretate the component via `php artisan make:component`. A
    third option will be presented if you want to create an Anonymous Index Component.

    > If the file does not exist and is in a subfolder that does not exist yet,
    > you should create the directory, it can be done writing the file using 
    > [`++p`](https://neovim.io/doc/user/editing.html#%3Awrite)

2. **To navigate to a controller associated with a route name**:
    - Place the cursor over the route name and use the `gf` command.

3. **To navigate to a configuration file**:
    - Place the cursor over the configuration file name and use the `gf` command.

4. **Select an existing resource using the custom source**, write either:
  - in a Blade file:
    - `@extends('`
    - `@include('`
    - `<x-`
    - `<livewire:`
    - `@livewire('`

  - in a Controller or Route:
    - `Route::view('`
    - `View::make('`
    - `view('`

  - in any PHP or Blade file:
    - `route('`
    - `to_route('`

    And the list of files will appear, and with the magic of completion the
    list if filtered while you write. 
    
## Configuration

No additional configuration is required. The plugin works out-of-the-box with the default `gf` command.

For [cmd](https://github.com/hrsh7th/nvim-cmp) you should install the plugin.

For [coq](https://github.com/ms-jpq/coq_nvim), you should install the plugin,
`coq_settings.match.max_results` limits the result shown.

For completion to place nice with autopairs, you can set the
`close_tag_on_complete` to false, blade-nav will not close the tag on complete.

```lua
  close_tag_on_complete = false, -- default: true
```

For packages that has Blade components, you should run the Ex command
`BladeNavInstallArtisanCommand` to install the artisan command.

If you want `blade-nav` to search in other paths when using `gf` on a Laravel
component, you can specify this by enabling the `exrc` option and adding to one
of the supported files, i.e.:

```lua
vim.g.blade_nav = {
  laravel_componets = {
    "resources/views/common",
  },
}
```

See `:h VIMINIT`

## Health

To check the health of the plugin, run `:checkhealth blade-nav`.

## Contributing

Feel free to submit issues or pull requests to enhance the functionality of this plugin.

## License

This plugin is open-source and distributed under the MIT License. See the LICENSE file for more details.

## Acknowledgments

Special thanks to the Neovim and Laravel communities for their continuous support and contributions.
