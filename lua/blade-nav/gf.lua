-- Custom opener for Laravel components
local utils = require("blade-nav.utils")

local M = {}
local gf_mapping

local registered = false

--- Get keymap
--- @param mode string
--- @param lhs string
--- @return vim.api.keyset.keymap|nil
local function get_keymap(mode, lhs)
  local keymaps = vim.api.nvim_get_keymap(mode)
  for _, keymap in ipairs(keymaps) do
    if keymap.lhs == lhs then
      return keymap
    end
  end
end

--- Run native gf
--- @return nil
local function gf_native()
  if gf_mapping then
    local rhs = vim.api.nvim_replace_termcodes(gf_mapping.rhs, true, true, true)
    vim.api.nvim_feedkeys(rhs, "n", false)
  else
    vim.fn.execute("normal! gf")
  end
end

--- Extract prefix and name
--- @param text string
--- @return string|nil, string|nil
local function extract_prefix_name(text)
  local patterns = {
    "(%S+)%s*%(%s*['\"]([%w%.%-%_]+)['\"]%s*,%s*['\"]([%w%.%-%_]+)['\"]%s*%)",
    "@*(%S+)%s*%(%s*['\"]([%w%.%-%_]+)['\"]",
    "<(x%-)([%w%-%_]+)(::)([%w%-%.%_]+)%s*[^>]*%s*/?>?",
    "<(x%-)([%w%-%.%_]+)%s*[^>]*%s*/?>?",
    "<(livewire)%:([%w%-%.]+)%s*[^>]*%s*/?>?",
    "(%S+)%s*%(%s*%[%s*['\"]([%w%.%-%_]+)['\"]%s*=>",
  }

  for _, pattern in ipairs(patterns) do
    local name, param1, param2, param3 = text:match(pattern)
    if param2 == "::" then
      return "package", param1 .. "," .. param3
    end

    if name and name == "Route::view" then
      if param2 then
        return name, param2
      end
    end

    if name and param1 then
      return name, param1
    end
  end

  return nil, nil
end

--- Obtain function and name in a treesitter tree
--- @param lang string
--- @param ts_node TSNode
--- @param query_string string
--- @param content? string|number
--- @return table,boolean {fn = string, name = string}|{},true|false
local function find_fn_and_name(lang, ts_node, query_string, content)
  if not ts_node then
    return {}, false
  end

  content = content or 0
  local ts = vim.treesitter
  local findings = { fn = nil, name = nil }
  local query = ts.query.parse(lang, query_string)

  for _, matches, _ in query:iter_matches(ts_node, content) do
    findings.fn = ts.get_node_text(matches[1], content)
    findings.name = ts.get_node_text(matches[2], content)
  end

  return findings, findings.fn ~= nil
end

--- Query string for function
--- @return string
local function query_string_for_function()
  return [[
    (function_call_expression
      function: (name) @fn (#any-of? @fn "config" "view" "route" "to_route")
      arguments: (arguments
        (argument
          (string (string_content) @name)))
    )
  ]]
end

--- Check for config, view, route, to_route
--- @param lang string
--- @param ts_node TSNode
--- @return table,boolean {fn = string, name = string},true|false
local function check_for_fn(lang, ts_node)
  --- @type TSNode | nil
  local node = ts_node
  while node do
    if node:type() == "function_call_expression" then
      if node:parent():type() ~= "argument" then
        break
      end
    end

    node = node:parent()
  end

  if not node then
    return {}, false
  end

  return find_fn_and_name(lang, node, query_string_for_function())
end

--- Check for Route::view or View::make on php filetype
--- @param lang string
--- @param ts_node TSNode
--- @return table,boolean {fn = string, name = string},true|false
local function check_for_scope(lang, ts_node)
  if vim.bo.filetype ~= "php" then
    return {}, false
  end
  --- @type TSNode | nil
  local node = ts_node

  local query_template = [[
    (scoped_call_expression
      scope: (name) @fn (#eq? @fn "%s")
      name: (name) @view (#eq? @view "%s")
      arguments: (arguments
        (argument
          (string
            (string_content)))?
        (argument
          (string
            (string_content) @name)
        )
      )
    )
  ]]
  local views = {
    { fn = "Route", name = "view" },
    { fn = "View",  name = "make" },
  }

  while node do
    if node:type() == "scoped_call_expression" then
      break
    end

    node = node:parent()
  end

  if not node then
    return {}, false
  end

  for _, view in ipairs(views) do
    local findings, ok = find_fn_and_name(lang, node, query_template:format(view.fn, view.name))
    if ok then
      findings.fn = view.fn .. "::" .. view.name
      return findings, true
    end
  end

  return {}, false
end

--- Function to parse a string with a specific language
--- @param lang string
--- @param content string
--- @return TSNode
local function parse_string(lang, content)
  local ts = vim.treesitter
  local parser = ts.get_string_parser(content, lang)
  local tree = parser:parse()[1]
  return tree:root()
end

--- Check for config, view, route, to_route in blade view
--- @param lang string
--- @param root TSNode
--- @return table,boolean {fn = string, name = string}|{},truse|false
local function check_in_blade(lang, root)
  if root:type() ~= "php_only" then
    return {}, false
  end

  lang = "php"

  local ts = vim.treesitter
  local content = "<?php\n" .. ts.get_node_text(root, 0)
  local ts_node = parse_string(lang, content)

  return find_fn_and_name(lang, ts_node, query_string_for_function(), content)
end

--- Find the function and name
--- @return table, boolean {fn = string, name = string}|{},true if found
local function seek_for_function_and_name()
  local root, lang = utils.get_root_and_lang()
  if not root or not lang then
    return {}, false
  end

  local ts_utils = require("nvim-treesitter.ts_utils")
  local current_node = ts_utils.get_node_at_cursor(0, true)

  if not current_node then
    return {}, false
  end

  local findings, ok = check_in_blade(lang, current_node)
  if ok then
    return findings, true
  end

  findings, ok = check_for_scope(lang, current_node)
  if ok then
    return findings, true
  end

  return check_for_fn(lang, current_node)
end

--- Find the function and name
--- @param text_input string
--- @param col number
--- @return table, boolean {fn = string, name = string}|{}, true if found
local function find_name(text_input, col)
  local findings, ok = seek_for_function_and_name()

  if ok then
    return findings.fn, findings.name
  end

  local text = text_input:gsub("%s+", " ")
  col = col - (#text_input - #text)
  local start_pos, end_pos = text:find("[,%s>%)]", col)
  if not start_pos then
    return
  end

  local found = text:sub(start_pos, end_pos)
  local end_tag = text:sub(start_pos - 1, end_pos - 1)
  if found == " " and end_tag == "," then
    start_pos, end_pos = text:find("[>%)]", col)
    end_tag = text:sub(start_pos - 1, end_pos - 1)
  end

  -- print("\n" .. text)
  -- print(string.rep("_", col - 1) .. "^   " .. "(" .. col .. ")")
  col = start_pos - 1
  -- print(string.rep("_", start_pos - 1) .. "^   " .. "(" .. start_pos .. ")")
  if not end_tag then
    return
  end

  -- Search backwards from the current column position
  local found_space = false
  start_pos = nil
  for i = col, 1, -1 do
    if text:sub(i, i):match("%s") then
      if text:sub(i + 1, i + 1):match("[cCrRvV]") then
        start_pos = i + 1
        break
      elseif text:sub(i + 1, i + 2):match("/>]") then
        found_space = true
        break
      end
    end

    if text:sub(i, i):match("[<@rRvV]") then
      if not text:sub(i - 1, i - 1):match("[%w%.%-%_:]") then
        start_pos = i
        break
      end
    end
  end

  if found_space or not start_pos then
    return
  end

  local tag = text:sub(start_pos, end_pos)

  return extract_prefix_name(tag)
end

local function has_telescope()
  return pcall(require, "telescope")
end

local function excec_action(selection)
  local selected = selection:gsub("^%d+[%:%.]%s*", "")
  if selected:find("artisan") then
    local _, ok = utils.execute_command_silent(selected)
    if ok then
      print("\nCommand executed successfully")
    else
      print("\nError executing command")
    end
  else
    vim.cmd("edit " .. selected)
  end
end

local function create_or_select(options)
  for _, option in ipairs(options) do
    if option:find("artisan") ~= nil then
      return "Create component"
    end
  end
  return "Select Component File"
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
        prompt_title = create_or_select(options),
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
  local choice_str = create_or_select(options) .. ":\n"
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

--- Get component name and prefix from the current cursor position
--- @return string|nil prefix
--- @return string|nil component_name
local function get_component_name_and_prefix()
  local _, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()

  -- Adjust column to be 1-based and within line length
  col = math.min(col + 1, #line)

  local prefix, gf_dest = find_name(line, col)
  if gf_dest then
    return prefix, gf_dest
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
    "app/Http/Livewire/" .. utils.kebab_to_pascal(component_name) .. ".php",
  }
end

local function check_for_filament_support(text)
  local support = {
    "actions",
    "avatar",
    "badge",
    "breadcrumbs",
    "button",
    "card",
    "dropdown",
    "fieldset",
    "grid",
    "icon",
    "icon-button",
    "input",
    "link",
    "loading-indicator",
    "loading-section",
    "modal",
    "pagination",
    "section",
    "tabs",
  }

  local package_name = text[1]:gsub("[%-.]", "/")
  local component_name = text[2]:gsub("[%-.]", "/")

  if utils.in_table(component_name, support) then
    package_name = package_name .. "/support"
  end

  return package_name, component_name
end

local function package_component(text)
  text = utils.explode(",", text)
  local package_name, component_name = check_for_filament_support(text)
  return {
    "vendor/" .. package_name .. "/resources/views/components/" .. component_name .. ".blade.php",
    nil,
  }
end

--- Get components aliases from blade-nav artisan command
--- @return table
local function get_components_aliases()
  if utils.check_blade_command() == false then
    return {}
  end

  local result = utils.execute_command_silent({
    "php",
    "artisan",
    "blade-nav:components-aliases",
  })

  if #result == 0 then
    return {}
  end

  return vim.fn.json_decode(result)
end

--- Check if component alias exists include filament support
--- @param component_name string
--- @return boolean|nil true if component alias exists
local function component_alias(component_name)
  local components_aliases = get_components_aliases()
  local filename = components_aliases[component_name]
  if filename then
    vim.cmd("edit " .. filename)
    return true
  end
end

local function get_paths(prefix, component_name)
  local prefix_map = {
    ["extends"] = laravel_view,
    ["include"] = laravel_view,
    ["livewire"] = livewire_component,
    ["x-"] = laravel_component,
    ["package"] = package_component,
  }

  return prefix_map[prefix](component_name)
end

local function gf_module(prefix)
  local gfs = {
    { prefixes = { "view", "View::make", "Route::view" }, fn = "gf_views" },
    { prefixes = { "config", "Config::[gs]et" },          fn = "gf_config" },
    { prefixes = { "route" },                             fn = "gf_routes" },
  }

  for _, gf in ipairs(gfs) do
    if utils.in_table(prefix, gf.prefixes) then
      return "blade-nav." .. gf.fn
    end
  end
end

--- Go to file for view, config, route
--- @param prefix string
--- @param component_name string
--- @return boolean|nil true if gf was successful
local function gf_by_module(prefix, component_name)
  local fn = gf_module(prefix)
  if fn then
    local module = package.loaded[fn] or require(fn)

    if module and type(module.gf) == "function" then
      pcall(module.gf, component_name)
      return true
    end
  end
end

--- Go to file or class for <x-*>|@include|@extends|@livewire|<livewire:*>
--- @param prefix string
--- @param component_name string
--- @return boolean|nil true if gf was successful
local function gf_file_or_class(prefix, component_name)
  component_name = string.gsub(component_name, "%.", "/")

  local file_path, class_path = unpack(get_paths(prefix, component_name))
  local choices = {}
  local file_that_exists

  if vim.fn.filereadable(file_path) == 1 then
    table.insert(choices, "1: " .. file_path)
    file_that_exists = file_path
  else
    local dir_path = file_path:gsub("%.blade%.php$", "")
    if vim.fn.isdirectory(dir_path) ~= 0 then
      vim.cmd("edit " .. dir_path .. "/index.blade.php")
      return true
    end
  end

  if vim.fn.filereadable(class_path) == 1 then
    table.insert(choices, "2: " .. class_path)
    file_that_exists = class_path
  elseif prefix == "livewire" and class_path then
    class_path = class_path:gsub("app/Http/Livewire", "app/Livewire")
    if vim.fn.filereadable(class_path) == 1 then
      table.insert(choices, "2: " .. class_path)
      file_that_exists = class_path
    end
  end

  if #choices == 1 then
    vim.cmd("edit " .. file_that_exists)
    return true
  end

  if #choices == 0 and file_path and not class_path then
    vim.cmd("edit " .. file_path)
    return true
  end

  local has_options = false
  if #choices == 0 then
    local component = capitalize(remove_prefix(component_name, prefix))
    if prefix == "x-" and component_name:find("%.") == nil then
      has_options = true
      table.insert(choices, "1: " .. file_path)
      if component_name:find("%.") == nil then
        table.insert(choices, (#choices + 1) .. ": " .. file_path:gsub("%.blade%.php$", "/index.blade.php"))
      end
      table.insert(choices, (#choices + 1) .. ": php artisan make:component " .. component)
    end

    if string.find(prefix, "livewire") then
      has_options = true
      table.insert(choices, "1: php artisan make:livewire " .. component:gsub("['()%)]", ""))
    end
  end

  if #choices >= 2 or has_options then
    component_picker(choices)
    return true
  end
end

function M.gf()
  local prefix, component_name = get_component_name_and_prefix()

  if not prefix or not component_name then
    return gf_native()
  end

  if gf_by_module(prefix, component_name) then
    return
  end

  if prefix == "x-" and component_alias(component_name) then
    return
  end

  if gf_file_or_class(prefix, component_name) then
    return
  end

  gf_native()
end

local function create_command()
  vim.api.nvim_create_user_command("BladeNavInstallArtisanCommand", function()
    local source = utils.get_blade_nav_filename()
    local root_dir = utils.get_root_dir()
    local dest_dir = root_dir .. "/app/Console/Commands/BladeNav.php"
    local src_content, err = utils.read_file(source)
    if not src_content then
      print("Error reading file: " .. err)
      return
    end

    vim.fn.mkdir(dest_dir:gsub("/BladeNav.php$", ""), "p")

    local dst_content = utils.modify_namespace(src_content, utils.psr4_app())
    local file, dst_err = utils.write_file(dest_dir, dst_content)
    if not file then
      print("Error writing file: " .. dst_err)
      return
    end

    print("BladeNav.php has been copied to app/Console/Commands/")
  end, {
    desc = "Copy BladeNav.php to app/Console/Commands/BladeNav.php",
  })
end

local function create_command_times()
  vim.api.nvim_create_user_command("BladeNavElapsedTimes", function()
    local function measure_time(func, func_name, ...)
      local start_time = os.clock()
      func(...)
      local end_time = os.clock()
      local elapsed_time = end_time - start_time
      print(string.format("Elapsed time: %.4f seconds on %s", elapsed_time, func_name))
    end

    measure_time(utils.check_blade_command, "check_blade_command")
    measure_time(get_components_aliases, "get_components_aliases")
    measure_time(utils.get_blade_files, "get_blade_files")
    measure_time(utils.get_root_dir, "get_root_dir")
    measure_time(utils.get_route_names, "get_route_names")
    measure_time(utils.get_routes, "get_routes", "")
  end, {
    desc = "Measure elapsed times for external commands",
  })
end

M.setup = function()
  if registered then
    return
  end

  registered = true

  gf_mapping = get_keymap("n", "gf")

  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("blade-nav-filetype-detection", { clear = true }),
    pattern = { "blade", "php" },
    callback = function()
      vim.keymap.set("n", "gf", function()
        M.gf()
      end, { buffer = true, noremap = true, silent = true, desc = "BladeNav: Open file under cursor" })
    end,
  })

  create_command()
  create_command_times()
end

return M
