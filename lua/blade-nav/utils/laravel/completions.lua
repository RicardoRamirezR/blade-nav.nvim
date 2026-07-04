-- lua/blade-nav/utils/laravel/completions.lua
local cache = require("blade-nav.utils.cache")
local config_keys = require("blade-nav.extractors.config")
local env_keys = require("blade-nav.extractors.env")
local fs = require("blade-nav.utils.fs")
local log = require("blade-nav.utils.log")

local M = {}

--- Find all views names
--- @param path string
--- @param extension? string
--- @param exclude_dirs? table
--- @return table
local function find_views_names(path, extension, exclude_dirs)
  extension = extension or "blade.php"

  local cache_key = "find_view_names:" .. path .. ":" .. extension .. ":" .. table.concat(exclude_dirs or {}, ",")
  local cached = cache.get(cache_key)
  if cached then
    return cached
  end

  local result = fs.find_files(path, extension, exclude_dirs)
  if not result then
    return {}
  end

  local views = {}
  local ext_pattern = "%." .. vim.pesc(extension) .. "$"

  for _, filename in ipairs(result) do
    local view = filename:match(vim.pesc(path) .. "(.+)")
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

-- stylua: ignore start
local PATTERNS = {
  { pattern = "to_route%("        , tpl = "to_route('%s')"          , ft = { "blade" , "php" }, fn = find_routes     , kind = "route"     },
  { pattern = "route%("           , tpl = "route('%s')"             , ft = { "blade" , "php" }, fn = find_routes     , kind = "route"     },
  { pattern = "<x%-"              , tpl = "<x-%s />"                , ft = { "blade" }        , fn = find_components , kind = "component" },
  { pattern = "<livewire"         , tpl = "<livewire:%s />"         , ft = { "blade" }        , fn = find_livewire   , kind = "livewire"  },
  { pattern = "@component%("      , tpl = "@component('%s')"        , ft = { "blade" }        , fn = find_views      , kind = "view"      },
  { pattern = "@extends%("        , tpl = "@extends('%s')"          , ft = { "blade" }        , fn = find_views      , kind = "view"      },
  { pattern = "@include%("        , tpl = "@include('%s')"          , ft = { "blade" }        , fn = find_views      , kind = "view"      },
  { pattern = "@livewire%("       , tpl = "@livewire('%s')"         , ft = { "blade" }        , fn = find_livewire   , kind = "livewire"  },
  { pattern = "Route::view%("     , tpl = "Route::view('uri', '%s')", ft = { "php" }          , fn = find_views      , kind = "view"      },
  { pattern = "View::make%("      , tpl = "View::make('%s')"        , ft = { "php" }          , fn = find_views      , kind = "view"      },
  { pattern = "view%("            , tpl = "view('%s')"              , ft = { "php" }          , fn = find_views      , kind = "view"      },
  { pattern = "inertia%("         , tpl = "inertia('%s')"           , ft = { "php" }          , fn = find_inertia    , kind = "inertia"   },
  { pattern = "Inertia::render%(" , tpl = "Inertia::render('%s')"   , ft = { "php" }          , fn = find_inertia    , kind = "inertia"   },
  { pattern = "config%("          , tpl = "config('%s')"            , ft = "*"                , fn = find_config     , kind = "config"    },
  { pattern = "Config::get%("     , tpl = "Config::get('%s')"       , ft = "*"                , fn = find_config     , kind = "config"    },
  { pattern = "Config::set%("     , tpl = "Config::set('%s')"       , ft = "*"                , fn = find_config     , kind = "config"    },
  { pattern = "env%("             , tpl = "env('%s')"               , ft = { "blade" , "php" }, fn = find_env        , kind = "env"       },
  { pattern = "__%("              , tpl = "__('%s')"                , ft = { "blade" , "php" }, fn = find_lang       , kind = "lang"      },
  { pattern = "trans%("            , tpl = "trans('%s')"              , ft = { "blade" , "php" }, fn = find_lang       , kind = "lang"      },
}
-- stylua: ignore end

--- Get all view names
--- @param input string
--- @param not_include_closing_tag? boolean
--- @return number|nil, table, string|nil
M.get_view_names = function(input, not_include_closing_tag)
  local index
  local items = {}
  log.debug("get_view_names called with input: %s", input)
  for i, p in ipairs(PATTERNS) do
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
  return index, items, index and PATTERNS[index].kind
end

--- Compute canonical completion items for the text before the cursor.
--- Shared helper used by cmp/blink/coq integrations.
--- @param line_before_cursor string
--- @return { label: string, new_text: string, kind: string }[]|nil
function M.items_for_prefix(line_before_cursor)
  if not line_before_cursor or line_before_cursor == "" then
    return nil
  end

  local input_prefix = line_before_cursor:match("%S*$") or ""
  local index, entries, kind = M.get_view_names(input_prefix)
  if not index or not entries or #entries == 0 then
    return nil
  end

  local items = {}
  for _, entry in ipairs(entries) do
    table.insert(items, {
      label = entry.label,
      new_text = entry.newText,
      kind = kind or "blade-nav",
    })
  end
  return items
end

M.__health_check_views = find_views

return M
