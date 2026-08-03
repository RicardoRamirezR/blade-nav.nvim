-- lua/blade-nav/targets/shared.lua
-- Shared helpers used by multiple target handlers.

local log = require("blade-nav.utils.log")

local M = {}

--- Builds view/include file candidate path(s) for a dot-notated (optionally
--- namespaced) view name, e.g. "user.profile" or "vendor::pkg.view".
--- @param raw_name string
--- @param dirs string[] Base directories to check for non-namespaced names, each ending in "/".
--- dirs[1] is used as the vendor root.
--- @param ext string File extension suffix, e.g. ".blade.php".
--- @return string[] candidate paths
function M.build_view_paths(raw_name, dirs, ext)
  ext = ext or ".blade.php"
  local paths = {}

  if raw_name:find("::", 1, true) then
    local namespace, view_part = raw_name:match("^([^:]+)::(.+)$")
    if namespace and view_part then
      local relative_path = view_part:gsub("%.", "/") .. ext
      table.insert(paths, dirs[1] .. "vendor/" .. namespace .. "/" .. relative_path)
    end
    return paths
  end

  local relative_path = raw_name:gsub("%.", "/") .. ext
  for _, dir in ipairs(dirs) do
    table.insert(paths, dir .. relative_path)
  end
  return paths
end

--- Deduplicates a list while preserving the original order. User-configured
--- search dirs can overlap the standard ones, producing duplicate candidates.
--- @param list string[]
--- @return string[]
local function dedupe(list)
  local seen = {}
  local out = {}
  for _, item in ipairs(list) do
    if not seen[item] then
      seen[item] = true
      table.insert(out, item)
    end
  end
  return out
end

--- Filters candidate paths down to the ones that exist as files.
--- Falls back to returning all candidates when none exist.
--- @param fs table utils/fs module
--- @param candidates string[]
--- @return string[], boolean final choices, whether any existing file was found
function M.existing_or_all(fs, candidates)
  candidates = dedupe(candidates)

  local existing = {}
  for _, path in ipairs(candidates) do
    if fs.path_exists(path) and not fs.is_dir(path) then
      table.insert(existing, path)
    end
  end

  if #existing > 0 then
    return existing, true
  end

  return candidates, false
end

--- Builds a no-op resolve function for handlers that only work through
--- get_target's `choices` field (resolution is delegated to core/init.lua).
--- @param handler_label string Name used in the log message, e.g. "livewire".
--- @return fun(target_info: table): boolean
function M.noop_resolve(handler_label)
  return function(target_info)
    log.warn(
      "%s handler resolve function called unexpectedly. Target info: %s",
      handler_label,
      vim.inspect(target_info)
    )
    return false
  end
end

return M
