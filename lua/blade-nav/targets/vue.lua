-- /lua/blade-nav/targets/vue.lua

local log = require("blade-nav.utils.log")
local vue_imports = require("blade-nav.utils.vue-imports")

local M = {}

function M.get_capabilities()
  return {
    filetypes = { "vue" },
  }
end

function M.get_target(context)
  log.debug("Vue target enabled: %s", context.filetype)
  if context.filetype ~= "vue" then
    return nil
  end

  log.debug("Resolving Vue target for line: %s", context.line)
  local path = vue_imports.resolve_path_for(context.line)
  log.debug("Path: %s", path)
  if not path then
    return nil
  end

  local tag = vue_imports.get_tag_name_for(context.line)
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
