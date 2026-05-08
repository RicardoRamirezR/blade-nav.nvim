-- lua/blade-nav/utils/choice.lua
-- Unified choice picker utility for blade-nav
-- Supports Telescope, vim.ui.select, and inputlist as fallback.

local log = require("blade-nav.utils.log")

local M = {}

--- Normalize numbered choices for consistent formatting.
--- @param choices string[]
--- @return string[]
local function normalize_choices(choices)
  local normalized = {}
  for i, choice in ipairs(choices) do
    if tostring(choice):match("^" .. i .. ": ") then
      table.insert(normalized, choice)
    else
      table.insert(normalized, i .. ": " .. choice)
    end
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
  filename = filename:gsub("[%s]*[✓✗][%s]*", "")
  return vim.trim(filename)
end

--- Opens a file in the current window safely.
--- Optionally runs a callback after opening.
--- @param filename string
--- @param after_open? fun(filename: string)
local function open_file(filename, after_open)
  if not filename or filename == "" then
    log.warn("open_file called with empty filename")
    return
  end

  filename = sanitize_filename(filename)

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

--- Presents a list of choices to the user and calls a callback with the selection.
--- @param title string
--- @param choices string[]
--- @param on_select fun(choice: string|nil)
function M.select(title, choices, on_select)
  if not choices or #choices == 0 then
    log.warn("choice.select called with empty list")
    return
  end

  if #choices == 1 then
    on_select(choices[1])
    return
  end

  choices = normalize_choices(choices)

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
        finder = finders.new_table(choices),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr, _)
          actions.select_default:replace(function()
            actions.close(prompt_bufnr)
            local selection = action_state.get_selected_entry()
            if selection and selection[1] then
              local value = selection[1]:gsub("%d+: ", "")
              on_select(value)
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
    vim.ui.select(choices, { prompt = title }, function(choice)
      if choice then
        local value = choice:gsub("%d+: ", "")
        on_select(value)
      else
        on_select(nil)
      end
    end)
    return
  end

  -- Final fallback: inputlist (CLI style)
  local choice_idx = vim.fn.inputlist(choices)
  local selected = choices[choice_idx]
  if selected then
    on_select(selected:gsub("%d+: ", ""))
  else
    on_select(nil)
  end
end

--- Convenience wrapper: choose a file and open it.
--- Optionally run a callback after opening the file.
--- @param title string
--- @param files string[]
--- @param after_open? fun(filename: string)
function M.select_file(title, files, after_open)
  M.select(title, files, function(selected)
    if selected then
      open_file(selected, after_open)
    end
  end)
end

return M
