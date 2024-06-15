-- Custom opener for Laravel components

local M = {}

local function has_telescope()
  return pcall(require, "telescope")
end

local function excec_action(selection)
  local selected = selection:gsub("^%d+%.%s*", "")
  local option = tonumber(string.match(selection, "^%d+%."))
  if option == 3 then
    local success, errorMsg = os.execute(selected)
    if success then
      print("\nCommand executed successfully")
    else
      print("\nError executing command:", errorMsg)
    end
  else
    vim.cmd("edit " .. selected)
  end
end

local function component_picker_telescope(opts, options)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  opts = opts or {}

  pickers
      .new(opts, {
        prompt_title = (#options == 3) and "Create component" or "Select Component File",
        finder = finders.new_table(options),
        sorter = conf.generic_sorter(opts),
        attach_mappings = function(bufnr, _)
          actions.select_default:replace(function()
            actions.close(bufnr)
            local selection = action_state.get_selected_entry()
            excec_action(selection[1])
          end)

          return true
        end,
      })
      :find()
end

local function component_picker_native(options)
  local choice_str = (#options == 3) and "Create component:\n" or "Choose a file:\n"
  for _, option in ipairs(options) do
    choice_str = choice_str .. option .. "\n"
  end

  local choice = vim.fn.input(choice_str .. "Enter number: ")
  local index = tonumber(choice)
  if index and options[index] then
    excec_action(options[index])
  else
    print("Invalid choice")
  end
end

local function component_picker(options)
  if has_telescope() then
    component_picker_telescope(require("telescope.themes").get_dropdown({}), options)
  else
    component_picker_native(options)
  end
end

local function starts_with(str, prefix)
  return string.sub(str, 1, string.len(prefix)) == prefix
end

local function remove_prefix(str, prefix)
  if str:sub(1, #prefix) == prefix then
    return str:sub(#prefix + 1)
  else
    return str
  end
end

local function capitalize(name)
  return name:gsub("(%a)([^/]*)", function(first, rest)
    return first:upper() .. rest
  end)
end

local function get_prefix(component_name, prefix_map)
  local prefix

  for key, _ in pairs(prefix_map) do
    if starts_with(component_name, key) then
      prefix = key
      break
    end
  end

  return prefix
end

local function get_component_type_and_name()
  local _, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()

  -- Adjust column to be 1-based and within line length
  col = math.min(col + 1, #line)

  -- Match the component pattern from the start of the line to the cursor position
  local start_tag = line:sub(1, col):match("[<@]")
  if not start_tag then
    return
  end

  -- Match the component pattern from the cursor position to the end of the line
  local end_tag = line:sub(col):match("[ >)]")
  if not end_tag then
    print("No end tag found")
    return
  end

  -- Concatenate the start and end tag parts
  local component_name = line:sub(line:find(start_tag), line:find(end_tag))

  -- Clean up the component name by removing any trailing characters like '>' or "'"
  local until_space = component_name:match("(.-)%s")
  if until_space then
    component_name = until_space
  end

  component_name = component_name:gsub("[<@/> ]", "")

  if component_name then
    return component_name
  else
    print("No component name found")
  end
end

local function laravel_component(component_name)
  return {
    "resources/views/components/" .. component_name .. ".blade.php",
    "app/View/Components/" .. capitalize(component_name) .. ".php",
  }
end

local function laravel_view(component_name)
  component_name = component_name:gsub("['()%)]", "")
  return {
    "resources/views/" .. component_name .. ".blade.php",
    nil,
  }
end

local function livewire_component(component_name)
  component_name = component_name:gsub("['()%)]", "")
  return {
    "resources/views/livewire/" .. component_name .. ".blade.php",
    "app/Http/Livewire/" .. capitalize(component_name) .. ".php",
  }
end

local function get_paths(component_name)
  local prefix_map = {
    ["extends("] = laravel_view,
    ["include("] = laravel_view,
    ["livewire("] = livewire_component,
    ["livewire:"] = livewire_component,
    ["x-"] = laravel_component,
  }
  local prefix = get_prefix(component_name, prefix_map)
  if prefix then
    component_name = remove_prefix(component_name, prefix)
    return prefix_map[prefix](component_name)
  end
end

function M.gf()
  local component_name = get_component_type_and_name()

  if not component_name then
    return
  end

  local prefix_map = {
    ["extends("] = true,
    ["include("] = true,
    ["livewire("] = true,
    ["livewire:"] = true,
    ["x-"] = true,
  }

  local prefix = get_prefix(component_name, prefix_map)

  if not prefix then
    return
  end

  component_name = string.gsub(component_name, "%.", "/")

  local file_path, class_path = unpack(get_paths(component_name))
  local choices = {}
  local file_that_exists

  if vim.fn.filereadable(file_path) == 1 then
    table.insert(choices, "1. " .. file_path)
    file_that_exists = file_path
  else
    local dir_path = file_path:gsub("%.blade%.php$", "")
    if vim.fn.isdirectory(dir_path) ~= 0 then
      vim.cmd("edit " .. dir_path .. "/index.blade.php")
      return true
    end
  end

  if vim.fn.filereadable(class_path) == 1 then
    table.insert(choices, "2. " .. class_path)
    file_that_exists = class_path
  end

  if #choices == 1 then
    vim.cmd("edit " .. file_that_exists)
    return true
  end

  if #choices == 0 and file_path and not class_path then
    vim.cmd("edit " .. file_path)
    return true
  end

  if #choices == 0 then
    local component = capitalize(remove_prefix(component_name, prefix))
    table.insert(choices, "1. " .. file_path)
    table.insert(choices, "2. " .. class_path)
    if string.find(prefix, "livewire") then
      table.insert(choices, "3. php artisan make:livewire " .. component:gsub("['()%)]", ""))
    else
      table.insert(choices, "3. php artisan make:component " .. component)
    end
  end

  if #choices >= 2 then
    component_picker(choices)
    return true
  end
end

return M
