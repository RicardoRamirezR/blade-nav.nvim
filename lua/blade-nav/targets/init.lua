-- lua/blade-nav/targets/init.lua

local choice = require("blade-nav.utils.choice")
local log = require("blade-nav.utils.log")
local uv = vim.uv

local M = {}

M._handlers = {}
M._handler_order = {}
M._handler_modules = {}
M._failed_handlers = {}
M._handler_capabilities = {}

--- Explicit handler precedence: handlers listed here are tried (when enabled)
--- before the remaining ones, which fall back to alphabetical order. In .vue
--- files the `vue` handler (component tags) must win over `inertia`
--- (project-wide reverse lookup).
local HANDLER_PRIORITY = { "vue" }

--- Register a target handler after it's required.
--- @param name string
--- @param handler table
local function register_handler(name, handler)
  if type(handler.get_target) ~= "function" then
    error("Handler for '" .. name .. "' must have a 'get_target' function.")
  end
  if type(handler.resolve) ~= "function" then
    error("Handler for '" .. name .. "' must have a 'resolve' function.")
  end

  M._handlers[name] = handler
  log.debug("Registered target handler: %s", name)
end

--- Load capabilities for a handler (lazy loading).
--- @param name string
--- @return boolean
local function ensure_capabilities_loaded(name)
  if M._handler_capabilities[name] then
    return true
  end

  local handler = M._handlers[name]
  if not handler then
    return false
  end

  if type(handler.get_capabilities) == "function" then
    local ok, capabilities = pcall(handler.get_capabilities)
    if ok and capabilities then
      M._handler_capabilities[name] = capabilities
      log.debug("Loaded capabilities for handler '%s': %s", name, vim.inspect(capabilities))
      return true
    else
      log.warn("Failed to get capabilities for handler '%s'", name)
    end
  end

  M._handler_capabilities[name] = false
  return false
end

--- Ensure a handler module is loaded (lazy require).
--- @param name string
--- @return boolean
local function ensure_handler_loaded(name)
  if M._handlers[name] then
    return true
  end
  if M._failed_handlers[name] then
    return false
  end
  local module_path = M._handler_modules[name]
  if not module_path then
    return false
  end
  local ok, mod = pcall(require, module_path)
  if ok and mod then
    register_handler(name, mod)
    return true
  end

  log.error("Failed to load target handler '%s' (%s): %s", name, module_path, tostring(mod))
  M._failed_handlers[name] = true
  return false
end

--- Check if filetype matches capabilities.
--- @param capabilities table
--- @param filetype string|nil
--- @return boolean
local function is_filetype_supported(capabilities, filetype)
  if not capabilities.filetypes or not filetype then
    return true
  end

  return vim.tbl_contains(capabilities.filetypes, filetype) or vim.tbl_contains(capabilities.filetypes, "*")
end

--- Check if handler can handle the given context based on capabilities.
--- @param handler_name string
--- @param context BladeNavContext
--- @return boolean
local function can_handler_process_context(handler_name, context)
  if not ensure_handler_loaded(handler_name) then
    return false
  end

  ensure_capabilities_loaded(handler_name)

  local capabilities = M._handler_capabilities[handler_name]
  if not capabilities then
    return true
  end

  if not is_filetype_supported(capabilities, context.filetype) then
    return false
  end

  if not context.target then
    return true
  end

  if capabilities.targets then
    return vim.tbl_contains(capabilities.targets, context.target)
  end

  return true
end

--- Get relevant handlers for the given context.
--- @param context BladeNavContext
--- @return string[]
local function get_relevant_handlers(context)
  local relevant = {}

  for _, name in ipairs(M._handler_order) do
    if can_handler_process_context(name, context) then
      table.insert(relevant, name)
    end
  end

  return relevant
end

--- Discover handler files in a directory.
--- @param handler_dir_path string
--- @return string[]
local function discover_handlers(handler_dir_path)
  local handler_names = {}
  log.debug("Discovering handlers in: %s", handler_dir_path)

  local handle, err = uv.fs_scandir(handler_dir_path)
  if not handle then
    log.error("Failed to scan handler dir '%s': %s", handler_dir_path, err or "unknown")
    return handler_names
  end

  local name, ftype = uv.fs_scandir_next(handle)
  while name do
    if ftype == "file" and name:match("%.lua$") and name ~= "init.lua" and name ~= "shared.lua" then
      local handler_name = name:gsub("%.lua$", "")
      table.insert(handler_names, handler_name)
      log.debug("Discovered handler: %s", handler_name)
    end
    name, ftype = uv.fs_scandir_next(handle)
  end

  -- readdir order is OS-dependent; sort for deterministic handler precedence.
  table.sort(handler_names)

  return handler_names
end

--- Load handler metadata (lazy registration).
--- @param handler_module_base string
--- @param handler_dir_path string|nil
--- @param config table
function M.load_handlers(handler_module_base, handler_dir_path, config)
  handler_module_base = handler_module_base or "blade-nav.targets"

  M._handlers = {}
  M._handler_order = {}
  M._handler_modules = {}
  M._handler_capabilities = {}
  M._failed_handlers = {}

  if not handler_dir_path then
    local init_script_path = debug.getinfo(1, "S").source:sub(2)
    handler_dir_path = vim.fn.fnamemodify(init_script_path, ":p:h")
    log.debug("Derived handler dir path: %s", handler_dir_path)
  end

  local discovered = discover_handlers(handler_dir_path)

  local function is_enabled(name)
    if config.handlers and config.handlers[name] == false then
      log.debug("Skipping handler '%s' (disabled in config)", name)
      return false
    end
    return true
  end

  local ordered = {}
  local seen = {}
  for _, name in ipairs(HANDLER_PRIORITY) do
    if vim.tbl_contains(discovered, name) and is_enabled(name) then
      table.insert(ordered, name)
      seen[name] = true
    end
  end
  for _, name in ipairs(discovered) do
    if not seen[name] and is_enabled(name) then
      table.insert(ordered, name)
    end
  end

  for _, name in ipairs(ordered) do
    local module_path = handler_module_base .. "." .. name
    M._handler_modules[name] = module_path
    table.insert(M._handler_order, name)
  end

  log.info("Registered %d handlers (lazy)", #M._handler_order)
end

--- Resolve a target using handlers in order.
--- @param context BladeNavContext
--- @return boolean
function M.resolve_target(context)
  log.debug(
    "Starting target resolution for context: %s",
    vim.inspect({
      target = context.target,
      filetype = context.filetype,
    })
  )

  local relevant_handlers = get_relevant_handlers(context)

  if #relevant_handlers == 0 then
    log.debug("No relevant handlers found for context")
    return false
  end

  log.debug("Found %d relevant handlers: %s", #relevant_handlers, vim.inspect(relevant_handlers))

  for _, name in ipairs(relevant_handlers) do
    if not ensure_handler_loaded(name) then
      goto continue
    end

    local handler = M._handlers[name]
    local ok, result = pcall(handler.get_target, context)

    if not ok then
      log.error("Handler '%s' error: %s", name, tostring(result))
      goto continue
    end

    if not result then
      goto continue
    end

    log.debug("Handler '%s' matched target: %s", name, vim.inspect(result))

    if result.choices and #result.choices > 0 then
      choice.select_file("Select " .. (result.type or "target"), result.choices)
      return true
    end

    if result.resolved == true then
      return true
    end

    if type(handler.resolve) == "function" then
      local rok, rres = pcall(handler.resolve, result)
      if rok and rres == true then
        return true
      end
      if not rok then
        log.error("Handler '%s' resolve error: %s", name, tostring(rres))
      end
    end

    ::continue::
  end

  log.debug("No handler successfully resolved the target")
  return false
end

--- Get debugging information about handlers.
--- @return table
function M.get_handler_info()
  return {
    loaded = vim.tbl_keys(M._handlers),
    registered = M._handler_order,
    capabilities = vim.tbl_filter(function(v)
      return v ~= false
    end, M._handler_capabilities),
    failed = vim.tbl_keys(M._failed_handlers),
    modules = M._handler_modules,
  }
end

--- Get a loaded handler by name.
--- Only valid for names returned by get_compatible_handlers; it does not load handlers itself.
--- @param name string
--- @return table|nil
function M.get_handler(name)
  return M._handlers[name]
end

--- Get capabilities for a specific handler.
--- @param handler_name string
--- @return table|nil
function M.get_handler_capabilities(handler_name)
  if not ensure_handler_loaded(handler_name) then
    return nil
  end

  ensure_capabilities_loaded(handler_name)
  local caps = M._handler_capabilities[handler_name]
  return caps ~= false and caps or nil
end

--- List handlers that can process the given context.
--- @param context BladeNavContext
--- @return string[]
function M.get_compatible_handlers(context)
  return get_relevant_handlers(context)
end

return M
