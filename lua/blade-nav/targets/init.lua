-- lua/blade-nav/targets/init.lua
local log = require("blade-nav.utils.log")
local uv = vim.loop

local M = {}

-- Internal registries
M._handlers = {}        -- Loaded handler modules
M._handler_order = {}   -- Order of handler names
M._handler_modules = {} -- Map name → module path for lazy require

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

--- Ensure a handler module is loaded (lazy require).
--- @param name string
--- @return boolean
local function ensure_handler_loaded(name)
  if M._handlers[name] then
    return true
  end
  local module_path = M._handler_modules[name]
  if not module_path then
    return false
  end
  local ok, mod = pcall(require, module_path)
  if ok and mod then
    register_handler(name, mod)
    return true
  else
    log.error("Failed to load target handler '%s' (%s): %s", name, module_path, tostring(mod))
    return false
  end
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
    if ftype == "file" and name:match("%.lua$") and name ~= "init.lua" then
      local handler_name = name:gsub("%.lua$", "")
      table.insert(handler_names, handler_name)
      log.debug("Discovered handler: %s", handler_name)
    end
    name, ftype = uv.fs_scandir_next(handle)
  end
  return handler_names
end

--- Load handler metadata (lazy registration).
--- @param handler_module_base string
--- @param handler_dir_path string|nil
--- @param config table
function M.load_handlers(handler_module_base, handler_dir_path, config)
  handler_module_base = handler_module_base or "blade-nav.targets"
  if not handler_dir_path then
    local init_script_path = debug.getinfo(1, "S").source:sub(2)
    handler_dir_path = vim.fn.fnamemodify(init_script_path, ":p:h")
    log.debug("Derived handler dir path: %s", handler_dir_path)
  end

  local discovered = discover_handlers(handler_dir_path)
  for _, name in ipairs(discovered) do
    if config.handlers and config.handlers[name] == false then
      log.info("Skipping handler '%s' (disabled in config)", name)
    else
      local module_path = handler_module_base .. "." .. name
      M._handler_modules[name] = module_path
      table.insert(M._handler_order, name)
    end
  end
  log.info("Registered %d handler names (lazy)", #M._handler_order)
end

--- Show choices with Telescope if available, otherwise vim.ui.select.
--- @param title string
--- @param choices string[]
function M.show_choices(title, choices)
  if not choices or #choices == 0 then
    log.warn("show_choices called with empty list")
    return
  end

  if #choices == 1 then
    vim.cmd("edit " .. vim.fn.fnameescape(choices[1]))
    return
  end

  local ok, telescope = pcall(require, "telescope")
  if ok and telescope then
    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")

    pickers
        .new({}, {
          prompt_title = title,
          finder = finders.new_table(choices),
          sorter = conf.generic_sorter({}),
          attach_mappings = function(prompt_bufnr, _)
            actions.select_default:replace(function()
              actions.close(prompt_bufnr)
              local selection = action_state.get_selected_entry()
              if selection and selection[1] then
                vim.cmd("edit " .. vim.fn.fnameescape(selection[1]))
              end
            end)
            return true
          end,
        })
        :find()
  else
    vim.ui.select(choices, { prompt = title }, function(choice)
      if choice then
        vim.cmd("edit " .. vim.fn.fnameescape(choice))
      end
    end)
  end
end

--- Resolve a target using handlers in order.
--- @param context BladeNavContext
--- @return boolean
function M.resolve_target(context)
  log.debug("Starting target resolution")
  for _, name in ipairs(M._handler_order) do
    if ensure_handler_loaded(name) then
      local handler = M._handlers[name]
      local ok, result = pcall(handler.get_target, context)
      if ok and result then
        log.debug("Handler '%s' matched target: %s", name, vim.inspect(result))
        if result.choices and #result.choices > 0 then
          M.show_choices("Select " .. (result.type or "target"), result.choices)
          return true
        elseif result.resolved == true then
          return true
        elseif type(handler.resolve) == "function" then
          local rok, rres = pcall(handler.resolve, result)
          if rok and rres == true then
            return true
          end
        end
      elseif not ok then
        log.error("Handler '%s' error: %s", name, tostring(result))
      end
    end
  end
  log.debug("No handler matched")
  return false
end

return M
