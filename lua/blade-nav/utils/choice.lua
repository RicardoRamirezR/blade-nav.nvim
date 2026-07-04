-- lua/blade-nav/utils/choice.lua
-- Unified choice picker utility for blade-nav
-- Supports Telescope, vim.ui.select, and inputlist as fallback.

local fs = require("blade-nav.utils.fs")
local log = require("blade-nav.utils.log")

local M = {}

local CHECK_MARKS = { "✓", "✗" }

--- Compute the display label for a choice entry.
--- @param choice string|{ label: string, cmd: string[] }
--- @param i integer
--- @return string
local function display_label(choice, i)
  local label = choice
  if type(choice) == "table" then
    label = choice.label or ""
  end
  label = tostring(label)

  local prefix = i .. ": "
  if label:sub(1, #prefix) == prefix then
    return label
  end
  return prefix .. label
end

--- Normalize choices into a display-string list (Telescope/vim.ui.select
--- both operate on strings; original entries are recovered by index).
--- @param choices (string|table)[]
--- @return string[]
local function normalize_choices(choices)
  local normalized = {}
  for i, choice in ipairs(choices) do
    table.insert(normalized, display_label(choice, i))
  end
  return normalized
end

--- Sanitize file name by removing symbols like ✓ or ✗
--- @param filename string
--- @return string
local function sanitize_filename(filename)
  if not filename then
    return ""
  end
  for _, mark in ipairs(CHECK_MARKS) do
    filename = filename:gsub("%s*" .. vim.pesc(mark) .. "%s*", "")
  end
  return vim.trim(filename)
end

--- Opens a file in the current window safely.
--- Optionally runs a callback after opening.
--- @param filename string
--- @param after_open? fun(filename: string)
--- @param base_dir? string Resolve filename against this dir when relative.
local function open_file(filename, after_open, base_dir)
  if not filename or filename == "" then
    log.warn("open_file called with empty filename")
    return
  end

  filename = sanitize_filename(filename)

  if base_dir and filename:sub(1, 1) ~= "/" then
    filename = base_dir .. "/" .. filename
  end

  -- Attempt to open safely
  local ok, err = pcall(function()
    vim.cmd("edit " .. vim.fn.fnameescape(filename))
  end)

  if not ok then
    log.error("Failed to open file: " .. tostring(err))
    return
  end

  if type(after_open) == "function" then
    -- Ejecutar callback después de abrir
    local success, cb_err = pcall(after_open, filename)
    if not success then
      log.error("Error in after_open callback: " .. tostring(cb_err))
    end
  end
end

--- Best-effort guess of the file created by an `artisan make:*` command,
--- from its argv or its output.
--- @param argv string[]
--- @param output string
--- @return string|nil
local function derive_created_file(argv, output)
  if output then
    local bracketed = output:match("%[([%w_%-/%.]+%.php)%]")
    if bracketed then
      return bracketed
    end
  end

  local subcommand = argv[3]
  local name = argv[#argv]
  if not subcommand or not name then
    return nil
  end

  local class_path = name:gsub("%.", "/")
  if subcommand == "make:component" then
    return "app/View/Components/" .. class_path .. ".php"
  elseif subcommand == "make:livewire" then
    return "app/Livewire/" .. class_path .. ".php"
  end

  return nil
end

--- Execute a create-command choice (e.g. `php artisan make:component Foo`).
--- @param entry { label: string, cmd: string[] }
--- @param after_open? fun(filename: string)
local function run_command_choice(entry, after_open)
  local argv = entry.cmd
  if type(argv) ~= "table" or #argv == 0 then
    log.error("choice.select_file: invalid cmd entry: %s", vim.inspect(entry))
    return
  end

  local root = fs.get_root_dir()

  local ok, err = pcall(vim.system, argv, { text = true, cwd = root }, function(obj)
    vim.schedule(function()
      if obj.code ~= 0 then
        local output = vim.trim((obj.stdout or "") .. (obj.stderr or ""))
        log.error("Command failed: %s (%s)", table.concat(argv, " "), output)
        return
      end

      local created_file = derive_created_file(argv, (obj.stdout or "") .. (obj.stderr or ""))
      if created_file then
        open_file(created_file, after_open, root)
      end
    end)
  end)

  if not ok then
    log.error("Failed to execute command: %s (%s)", table.concat(argv, " "), tostring(err))
  end
end

--- Presents a list of choices to the user and calls a callback with the selection.
--- @param title string
--- @param choices (string|{ label: string, cmd: string[] })[]
--- @param on_select fun(choice: string|table|nil)
function M.select(title, choices, on_select)
  if not choices or #choices == 0 then
    log.warn("choice.select called with empty list")
    return
  end

  if #choices == 1 then
    on_select(choices[1])
    return
  end

  local original_choices = choices
  local display_choices = normalize_choices(choices)

  --- Map a display string back to the original entry (string or table).
  local function resolve(display)
    if not display then
      return nil
    end
    local idx = tonumber(display:match("^(%d+): "))
    if idx and original_choices[idx] ~= nil then
      return original_choices[idx]
    end
    return (display:gsub("^%d+: ", "", 1))
  end

  -- Try Telescope first
  local ok_telescope, telescope = pcall(require, "telescope")
  if ok_telescope and telescope then
    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")

    pickers
      .new({}, {
        prompt_title = title,
        finder = finders.new_table(display_choices),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr, _)
          actions.select_default:replace(function()
            actions.close(prompt_bufnr)
            local selection = action_state.get_selected_entry()
            if selection and selection[1] then
              on_select(resolve(selection[1]))
            else
              on_select(nil)
            end
          end)
          return true
        end,
      })
      :find()
    return
  end

  -- Fallback: vim.ui.select if available
  if vim.ui and vim.ui.select then
    vim.ui.select(display_choices, { prompt = title }, function(choice)
      on_select(resolve(choice))
    end)
    return
  end

  -- Final fallback: inputlist (CLI style)
  local choice_idx = vim.fn.inputlist(display_choices)
  on_select(resolve(display_choices[choice_idx]))
end

--- Convenience wrapper: choose a file and open it, or run a create-command choice.
--- Optionally run a callback after opening the file.
--- @param title string
--- @param files (string|{ label: string, cmd: string[] })[]
--- @param after_open? fun(filename: string)
function M.select_file(title, files, after_open)
  M.select(title, files, function(selected)
    if not selected then
      return
    end
    if type(selected) == "table" then
      run_command_choice(selected, after_open)
    else
      open_file(selected, after_open)
    end
  end)
end

return M
