-- lua/blade-nav/utils/laravel/completions.lua
local cache = require("blade-nav.utils.cache")
local config_keys = require("blade-nav.extractors.config")
local env_keys = require("blade-nav.extractors.env")
local fs = require("blade-nav.utils.fs")
local log = require("blade-nav.utils.log")

local M = {}

local function escape_lua_pattern(s)
  return (s:gsub("([^%w])", "%%%1"))
end

--- Find all views names
--- @param path string
--- @param extension? string
--- @param exclude_dirs? table
--- @return table
local function find_views_names(path, extension, exclude_dirs)
  extension = extension or "blade.php"

  local cache_key = "find_view_names:" .. path .. ":" .. extension
  local cached = cache.get(cache_key)
  if cached then
    return cached
  end

  local result = fs.find_files(path, extension, exclude_dirs)
  if not result then
    return {}
  end

  local views = {}
  local ext_pattern = "%." .. escape_lua_pattern(extension) .. "$"

  for _, filename in ipairs(result) do
    local view = filename:match(path .. "(.+)")
    if view then
      view = view:gsub("^/", ""):gsub(ext_pattern, ""):gsub("/", ".")
      table.insert(views, view)
    end
  end

  return cache.set(cache_key, views)
end

local function find_inertia()
  local config = require("blade-nav.core.config")
  local extensions = config.get("inertia_extensions") or { "vue", "tsx", "jsx", "ts" }
  local pages_path = config.get("inertia_pages_path") or "Pages"

  local base = "resources/js/" .. pages_path
  local all = {}
  local seen = {}

  for _, ext in ipairs(extensions) do
    local names = find_views_names(base, ext)
    for _, name in ipairs(names) do
      if not seen[name] then
        seen[name] = true
        table.insert(all, name)
      end
    end
  end

  return all
end

--- Find all translation keys
--- @return table
local function find_lang()
  local lang_keys = require("blade-nav.extractors.lang")
  return lang_keys.get_keys()
end

--- Find all config keys
--- @return table
local function find_config()
  local root = fs.get_root_dir()
  return config_keys.get_keys(root)
end

--- Find all components view
--- @return table
local function find_components()
  return find_views_names("resources/views/components")
end

--- Find all env keys
--- @return table
local function find_env()
  local root = fs.get_root_dir()
  return env_keys.get_keys(root)
end

--- Find all livewire views
--- @return table
local function find_livewire()
  return find_views_names("resources/views/livewire")
end

--- Find all routes
--- @return table
local function find_routes()
  return require("blade-nav.utils.laravel.routes").get_route_names()
end

--- Find all views excluding livewire and Laravel components
--- @return table
local function find_views()
  return find_views_names("resources/views", nil, { "resources/views/livewire", "resources/views/components" })
end

--- Get all view names
--- @param input string
--- @param not_include_closing_tag? boolean
--- @return number|nil, table
M.get_view_names = function(input, not_include_closing_tag)
  -- stylua: ignore start
  local patterns = {
    { pattern = "to_route%("        , tpl = "to_route('%s')"          , ft = { "blade" , "php" }, fn = find_routes     },
    { pattern = "route%("           , tpl = "route('%s')"             , ft = { "blade" , "php" }, fn = find_routes     },
    { pattern = "<x%-"              , tpl = "<x-%s />"                , ft = { "blade" }        , fn = find_components },
    { pattern = "<livewire"         , tpl = "<livewire:%s />"         , ft = { "blade" }        , fn = find_livewire   },
    { pattern = "@component%("      , tpl = "@component('%s')"        , ft = { "blade" }        , fn = find_views      },
    { pattern = "@extends%("        , tpl = "@extends('%s')"          , ft = { "blade" }        , fn = find_views      },
    { pattern = "@include%("        , tpl = "@include('%s')"          , ft = { "blade" }        , fn = find_views      },
    { pattern = "@livewire%("       , tpl = "@livewire('%s')"         , ft = { "blade" }        , fn = find_livewire   },
    { pattern = "Route::view%("     , tpl = "Route::view('uri', '%s')", ft = { "php" }          , fn = find_views      },
    { pattern = "View::make%("      , tpl = "View::make('%s')"        , ft = { "php" }          , fn = find_views      },
    { pattern = "view%("            , tpl = "view('%s')"              , ft = { "php" }          , fn = find_views      },
    { pattern = "inertia%("         , tpl = "inertia('%s')"           , ft = { "php" }          , fn = find_inertia    },
    { pattern = "Inertia::render%(" , tpl = "Inertia::render('%s')"   , ft = { "php" }          , fn = find_inertia    },
    { pattern = "config%("          , tpl = "config('%s')"            , ft = "*"                , fn = find_config     },
    { pattern = "Config::get%("     , tpl = "Config::get('%s')"       , ft = "*"                , fn = find_config     },
    { pattern = "Config::set%("     , tpl = "Config::set('%s')"       , ft = "*"                , fn = find_config     },
    { pattern = "env%("             , tpl = "env('%s')"               , ft = { "blade" , "php" }, fn = find_env        },
    { pattern = "__%("              , tpl = "__('%s')"                , ft = { "blade" , "php" }, fn = find_lang       },
    { pattern = "trans%("            , tpl = "trans('%s')"              , ft = { "blade" , "php" }, fn = find_lang       },
  }
  -- stylua: ignore end
  local index
  local items = {}
  log.debug("get_view_names called with input: %s", input)
  for i, p in ipairs(patterns) do
    if input:match(p.pattern) and (p.ft == "*" or vim.tbl_contains(p.ft, vim.bo.filetype)) then
      local names = p.fn()
      for _, name in ipairs(names) do
        if name then
          local new_text = p.tpl:format(name)
          if not_include_closing_tag then
            new_text = new_text:gsub("'%)", "")
          end
          table.insert(items, {
            filterText = input .. name,
            label = p.tpl:format(name):gsub("^%s+", ""),
            newText = new_text,
          })
        end
      end
      index = i
      break
    end
  end
  return index, items
end

M.__health_check_views = find_views

return M
