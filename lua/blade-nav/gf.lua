-- Custom opener for Laravel components
local utils = require("blade-nav.utils")

local M = {}
local rhs

local registered = false

local function get_keymap_rhs(mode, lhs)
  local mappings = vim.api.nvim_get_keymap(mode)
  for _, mapping in ipairs(mappings) do
    if mapping.lhs == lhs then
      return mapping.rhs:gsub("<[lL][tT]>", "<")
    end
  end

  return nil
end

local function exec_native_gf()
  if rhs then
    rhs = rhs:gsub("<[cC][fF][iI][lL][eE]>", M.cfile)
    rhs = rhs:gsub("<[cC][rR]>", "")
    vim.cmd(rhs)
  else
    vim.fn.execute("normal! gf")
  end
end

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
end

local function table_length(t)
  local count = 0
  for _ in pairs(t) do
    count = count + 1
  end
  return count
end

--- Obtain function and name
--- @param lang string
--- @param ts_node string
--- @param query_string string
--- @return table {fn = string, name = string}|{}
local function get_func_name(lang, ts_node, query_string)
  if not ts_node then
    return {}
  end

  local findings = {}
  local ts = vim.treesitter
  local query = ts.query.parse(lang, query_string)
  for _, matches, _ in query:iter_matches(ts_node, 0) do
    for id, node in pairs(matches) do
      if query.captures[id] == "fn" or query.captures[id] == "name" then
        findings[query.captures[id]] = ts.get_node_text(node, 0)
      end
    end
  end

  return findings
end

--- Check for config, view, route, to_route
--- @param lang string
--- @param ts_node TSNode
--- @return table {fn = string, name = string}
local function check_for_fn(lang, ts_node)
  local query = [[
    (function_call_expression
      function: (name) @fn (#any-of? @fn "config" "view" "route" "to_route")
      arguments: (arguments
        (argument
          (string (string_content) @name)))
    )
  ]]

  --- @type ts_node TSNode | nil
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
    return {}
  end

  return get_func_name(lang, node, query)
end

--- Check for Route::view or View::make on php filetype
--- @param lang string
--- @param node TSNode
--- @return table {fn = string, name = string}
local function check_for_scope(lang, node)
  if vim.bo.filetype ~= "php" then
    return {}
  end

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
    return {}
  end

  local findings = {}
  for _, view in ipairs(views) do
    findings = get_func_name(lang, node, query_template:format(view.fn, view.name))
    if table_length(findings) > 0 then
      findings.fn = view.fn .. "::" .. view.name
      break
    end
  end

  return findings
end

--- Find the function and name
--- comment
--- @return table
local function seek_func()
  local root, lang = utils.get_root_and_lang()
  if not root or not lang then
    return {}
  end

  local ts_utils = require("nvim-treesitter.ts_utils")
  local current_node = ts_utils.get_node_at_cursor()

  if not current_node then
    return {}
  end

  local findings = check_for_scope(lang, current_node)
  if table_length(findings) > 0 then
    return findings
  end

  return check_for_fn(lang, current_node)
end

local function find_name(text_input, col)
  local findings = seek_func()
  if table_length(findings) > 0 then
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
  local selected = selection:gsub("^%d+%.%s*", "")
  if selected:find("artisan") then
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

local function get_component_and_prefix()
  local _, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()

  -- Adjust column to be 1-based and within line length
  col = math.min(col + 1, #line)

  local prefix, gf_dest = find_name(line, col)
  if gf_dest then
    return prefix, gf_dest
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

function M.gf()
  local prefix, component_name = get_component_and_prefix()

  if not prefix or not component_name then
    return
  end

  local fn = gf_module(prefix)
  if fn then
    local module = package.loaded[fn] or require(fn)

    if module and type(module.gf) == "function" then
      return pcall(module.gf, component_name)
    end
  end

  if component_alias(component_name) then
    return
  end

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
        table.insert(choices, (#choices + 1) .. ". " .. file_path:gsub("%.blade%.php$", "/index.blade.php"))
      end
      table.insert(choices, (#choices + 1) .. ". php artisan make:component " .. component)
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

    vim.fn.mkdir(dest_dir, "p")

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

M.setup = function()
  if registered then
    return
  end

  registered = true

  rhs = get_keymap_rhs("n", "gf")

  vim.keymap.set("n", "gf", function()
    M.cfile = vim.fn.expand("<cfile>")
    M.gf()
  end, { noremap = true, silent = true, desc = "BladeNav: Open file under cursor" })

  create_command()
end

return M
