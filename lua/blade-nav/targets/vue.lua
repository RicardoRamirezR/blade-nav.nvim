local vue_imports = require("blade-nav.utils.vue-imports")
local config = require("blade-nav.core.config")
local log = require("blade-nav.utils.log")

local M = {}

function M.get_target(context)
  log.debug("Vue target enabled: %s", context.filetype)
  if context.filetype ~= "vue" then
    return nil
  end

  local path = vue_imports.resolve_path_under_cursor()
  log.debug("Path: %s", path)
  if not path then
    return nil
  end

  local tag = vue_imports.get_tag_name_under_cursor()
  log.debug("Vue target resolved: %s -> %s", tag, path)

  return {
    type = "vue",
    name = tag or path,
    path = path,
  }
end

function M.resolve(target)
  if target.type ~= "vue" then
    return false
  end
  if target.path and vim.fn.filereadable(target.path) == 1 then
    vim.cmd("edit " .. vim.fn.fnameescape(target.path))
    return true
  end
  return false
end

return M
