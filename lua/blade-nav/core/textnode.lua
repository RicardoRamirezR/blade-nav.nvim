-- lua/blade-nav/core/textnode.lua

local log = require("blade-nav.utils.log")

local M = {}
local ts = vim.treesitter

local TARGET_LISTS = {
  php = {
    "Config::get()",
    "Config::set()",
    "Inertia::render",
    "Route::view",
    "View::make",
    "config",
    "env",
    "inertia",
    "markdown",
    "route",
    "to_route",
    "view",
  },
  directive = {
    "@component",
    "@each",
    "@extends",
    "@includeUnless",
    "@includeFirst",
    "@includeWhen",
    "@includeIf",
    "@include",
  },
  component = {},
  livewire = {},
}

local function is_target(name, interest_type)
  if interest_type == "component" then
    return true
  end

  if not name or not interest_type then
    return false
  end

  local list = TARGET_LISTS[interest_type]
  if not list then
    return false
  end

  local clean_name = name:gsub("%s+", "")

  for _, item in ipairs(list) do
    if clean_name == item then
      return true
    end
  end

  return false
end

local function node_text(node, bufnr)
  if not node then
    return nil
  end

  if vim.treesitter.get_node_text then
    return ts.get_node_text(node, bufnr)
  end

  if ts.query then
    return ts.query.get_node_text(node, bufnr)
  end

  return nil
end

local function clean_text(text)
  if not text then
    return nil
  end
  return text:gsub("[\r\n]+", " "):gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
end

local function extract_first_argument(text)
  if not text then
    return nil
  end

  local array_content = text:match("^%s*%[%s*['\"`]([^'\"`]+)['\"`]%s*%]%s*$")
  if array_content then
    return array_content
  end

  local simple_quoted = text:match("^%s*['\"`]([^'\"`]+)['\"`]%s*$")
  if simple_quoted then
    return simple_quoted
  end

  local cleaned = text:gsub("^['\"`](.+)['\"`]$", "%1")
  cleaned = clean_text(cleaned)
  return cleaned
end

local function get_cursor_pos()
  local cursor = vim.api.nvim_win_get_cursor(0)
  return cursor[1] - 1, cursor[2]
end

local function find_parent(node, predicate)
  local current = node
  while current do
    if predicate(current) then
      return current
    end
    current = current:parent()
  end
  return nil
end

local function safe_get_node_at_cursor(bufnr)
  local ft = vim.api.nvim_buf_get_option(bufnr, "filetype")
  if not ft or ft == "" then
    vim.notify("No filetype detected", vim.log.levels.WARN)
    return nil
  end

  local ok, parser = pcall(ts.get_parser, bufnr, ft)
  if not ok or not parser then
    vim.notify("No parser available for buffer", vim.log.levels.WARN)
    return nil
  end

  local row, col = get_cursor_pos()
  local ok2, node = pcall(function()
    if ts.get_node_at_pos then
      return ts.get_node_at_pos(bufnr, row, col, {})
    elseif ts.get_node then
      return ts.get_node({ bufnr = bufnr, pos = { row, col } })
    else
      local tree = parser:parse()[1]
      return tree and tree:root():descendant_for_range(row, col, row, col)
    end
  end)

  if not ok2 then
    vim.notify("Error getting node: " .. tostring(node), vim.log.levels.ERROR)
    return nil
  end

  return node
end

local function node_text_from_string(node, source_string)
  local start_row, start_col, end_row, end_col = node:range()
  local lines = vim.split(source_string, "\n")

  if start_row == end_row then
    return string.sub(lines[start_row + 1], start_col + 1, end_col)
  else
    local result = {}
    for i = start_row, end_row do
      local line = lines[i + 1] or ""
      if i == start_row then
        table.insert(result, string.sub(line, start_col + 1))
      elseif i == end_row then
        table.insert(result, string.sub(line, 1, end_col))
      else
        table.insert(result, line)
      end
    end
    return table.concat(result, "\n")
  end
end

local function extract_function_name_from_php_only(php_only_node, bufnr)
  local text = node_text(php_only_node, bufnr)
  local php_code = "<?php " .. text .. ";"

  local ok, parser = pcall(vim.treesitter.get_string_parser, php_code, "php")
  if not ok then
    local function_name = text:match("^([%w_\\]+)%(")
    if function_name then
      local clean_name = function_name:match("([%w_]+)$") or function_name
      return clean_name
    end
    return nil
  end

  local tree = parser:parse()[1]
  local root = tree:root()

  local function find_function_call(node)
    if node:type() == "function_call_expression" then
      local function_node = node:child(0)
      if function_node and function_node:type() == "name" then
        return node_text_from_string(function_node, php_code)
      end
    end

    if node:type() == "scoped_call_expression" then
      local scope_node = node:field("scope")[1]
      local name_node = node:field("name")[1]

      if scope_node and name_node then
        local scope_text = node_text_from_string(scope_node, php_code)
        local name_text = node_text_from_string(name_node, php_code)
        return scope_text .. "::" .. name_text
      end
    end

    for child in node:iter_children() do
      local result = find_function_call(child)
      if result then
        return result
      end
    end

    return nil
  end

  local function_name = find_function_call(root)

  if not function_name then
    function_name = text:match("^([%w_\\]+)%(")
    if function_name then
      local clean_name = function_name:match("([%w_]+)$") or function_name
      return clean_name
    end
  end

  return function_name
end

local function find_interesting_php_parent(start_node, bufnr)
  local current = start_node:parent()

  while current do
    if vim.tbl_contains({ "function_call_expression", "scoped_call_expression" }, current:type()) then
      local _, function_name, _ = M.extract_php(current, bufnr)
      if function_name and is_target(function_name, "php") then
        return current
      end
    end

    if current:type() == "php_statement" then
      for child in current:iter_children() do
        if child:type() == "php_only" then
          local function_name = extract_function_name_from_php_only(child, bufnr)
          if function_name and is_target(function_name, "php") then
            return current
          end
        end
      end
    end

    current = current:parent()
  end

  return nil
end

function M.set_target_lists(lists)
  if lists.php then
    TARGET_LISTS.php = lists.php
  end
  if lists.directive then
    TARGET_LISTS.directive = lists.directive
  end
  if lists.component then
    TARGET_LISTS.component = lists.component
  end
end

function M.get_target_lists()
  return TARGET_LISTS
end

--- Extract function name from php_only node
--- @param php_only_node TSNode The php_only node
--- @param bufnr integer Buffer number
--- @return string|nil, string|nil, string|nil complete node text, function name, first argument
function M.extract_php(node, bufnr)
  node = find_parent(node, function(n)
    return vim.tbl_contains({ "php_statement", "function_call_expression", "scoped_call_expression" }, n:type())
  end)
  if not node then
    return nil, nil, nil
  end

  local function get_first_argument(target_node, bufnr)
    for child in target_node:iter_children() do
      if child:type() == "arguments" then
        for arg_child in child:iter_children() do
          if arg_child:type() ~= "(" and arg_child:type() ~= ")" and arg_child:type() ~= "," then
            local raw_arg = node_text(arg_child, bufnr)
            return clean_text(raw_arg), extract_first_argument(raw_arg)
          end
        end
      end
    end
    return nil, nil
  end

  local function extract_from_node(target_node)
    if target_node:type() == "function_call_expression" then
      local function_name
      local function_node = target_node:child(0)
      if function_node and function_node:type() == "name" then
        function_name = node_text(function_node, bufnr)
      end

      local first_arg, clean_first_arg = get_first_argument(target_node, bufnr)
      if first_arg then
        return function_name .. "(" .. first_arg .. ")", function_name, clean_first_arg
      else
        return clean_text(node_text(target_node, bufnr)), function_name, nil
      end
    end

    if target_node:type() == "scoped_call_expression" then
      local function_name
      local scope_node = target_node:field("scope")[1]
      local name_node = target_node:field("name")[1]

      if scope_node and name_node then
        local scope_text = node_text(scope_node, bufnr)
        local name_text = node_text(name_node, bufnr)
        function_name = scope_text .. "::" .. name_text
      end

      local first_arg, clean_first_arg = get_first_argument(target_node, bufnr)
      if first_arg then
        return function_name .. "(" .. first_arg .. ")", function_name, clean_first_arg
      else
        return clean_text(node_text(target_node, bufnr)), function_name, nil
      end
    end

    for child in target_node:iter_children() do
      if child:type() == "php_only" then
        local function_name = extract_function_name_from_php_only(child, bufnr)
        local php_text = node_text(child, bufnr)

        local first_arg = php_text:match("^[%w_:]+%s*%(%s*([^,)]+)")
        local clean_first_arg = nil
        if first_arg then
          first_arg = clean_text(first_arg)
          clean_first_arg = extract_first_argument(first_arg)
          return function_name .. "(" .. first_arg .. ")", function_name, clean_first_arg
        else
          return clean_text(php_text), function_name, nil
        end
      end
    end

    return nil, nil, nil
  end

  local text, function_name, first_arg = extract_from_node(node)

  if function_name and not is_target(function_name, "php") then
    local parent_node = find_interesting_php_parent(node, bufnr)
    if parent_node then
      local parent_text, parent_function_name, parent_first_arg = extract_from_node(parent_node)
      if parent_text and parent_function_name then
        return parent_text, parent_function_name, parent_first_arg
      end
    end
  end

  return text, function_name, first_arg
end

function M.extract_component(bufnr)
  local row, col = get_cursor_pos()
  local ok, html_parser = pcall(ts.get_parser, bufnr, "html")
  if not ok or not html_parser then
    vim.notify("HTML parser not available for buffer", vim.log.levels.WARN)
    return nil, nil, nil
  end

  local trees = html_parser:parse()
  if not trees or #trees == 0 then
    return nil, nil, nil
  end

  local root = trees[1]:root()
  local node = root:descendant_for_range(row, col, row, col)
  if not node then
    return nil, nil, nil
  end

  local function extract_from_component_node(target_node)
    local t = target_node:type()
    if t == "start_tag" or t == "self_closing_tag" then
      local full_text = clean_text(node_text(target_node, bufnr))
      local tag_name = full_text:match("<%s*([%w%-:%.]+)")

      local component_path = nil
      local component_type = "component"

      if tag_name then
        if tag_name:match("^x%-") then
          component_path = tag_name:gsub("^x%-", "")
          component_type = "component"
        elseif tag_name:match("^livewire:") then
          component_path = tag_name:gsub("^livewire:", "")
          component_type = "livewire"
        else
          component_path = tag_name
          component_type = "component"
        end
      end

      return full_text, component_type, component_path
    end

    if t == "tag_name" then
      local parent = target_node:parent()
      if parent and (parent:type() == "start_tag" or parent:type() == "self_closing_tag") then
        local full_text = clean_text(node_text(parent, bufnr))
        local tag_name = clean_text(node_text(target_node, bufnr))

        local component_path = nil
        local component_type = "component"

        if tag_name:match("^x%-") then
          component_path = tag_name:gsub("^x%-", "")
          component_type = "component"
        elseif tag_name:match("^livewire:") then
          component_path = tag_name:gsub("^livewire:", "")
          component_type = "livewire"
        else
          component_path = tag_name
          component_type = "component"
        end

        return full_text, component_type, component_path
      end
    end

    if t == "component" then
      for child in target_node:iter_children() do
        if child:type() == "start_tag" then
          local full_text = clean_text(node_text(child, bufnr))
          local tag_name = full_text:match("<%s*([%w%-:]+)")

          local component_path = nil
          local component_type = "component"

          if tag_name then
            if tag_name:match("^x%-") then
              component_path = tag_name:gsub("^x%-", "")
              component_type = "component"
            elseif tag_name:match("^livewire:") then
              component_path = tag_name:gsub("^livewire:", "")
              component_type = "livewire"
            else
              component_path = tag_name
              component_type = "component"
            end
          end

          return full_text, component_type, component_path
        end
      end
    end
    return nil, nil, nil
  end

  local current = node
  while current do
    local text, component_type, component_path = extract_from_component_node(current)
    if text and component_type then
      local tag_name = text:match("<%s*([%w%-:]+)")
      if tag_name and is_target(tag_name, "component") then
        return text, component_type, component_path
      end
    end
    current = current:parent()
  end

  return nil, nil, nil
end

function M.extract_directive(node, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row, col = cursor[1] - 1, cursor[2]

  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "blade")
  if not ok or not parser then
    return nil, "No Blade parser available", nil
  end

  local trees = parser:parse()
  if not trees or #trees == 0 then
    return nil, "No parse tree", nil
  end

  local root = trees[1]:root()
  local directives = {}
  local function collect_directives(n)
    for child in n:iter_children() do
      if child:type() == "directive" then
        table.insert(directives, child)
      end
      collect_directives(child)
    end
  end
  collect_directives(root)

  if #directives == 0 then
    return nil, nil, nil
  end

  local function abs_pos(r, c)
    return r * 100000 + c
  end

  local cursor_abs = abs_pos(row, col)
  local best = nil
  local best_score = math.huge

  for _, d in ipairs(directives) do
    local sr, sc, er, ec = d:range()
    if sr <= row and row <= er then
      local score = (row - sr) * 1000 + math.max(0, col - sc)
      if score < best_score then
        best = d
        best_score = score
      end
    elseif sr <= row then
      local score = (row - sr) * 1000 + math.abs(col - sc)
      if score < best_score then
        best = d
        best_score = score
      end
    end
  end

  if not best then
    local best_before = nil
    local best_before_pos = -1
    for _, d in ipairs(directives) do
      local sr, sc = d:range()
      local start_abs = abs_pos(sr, sc)
      if start_abs <= cursor_abs and start_abs > best_before_pos then
        best_before_pos = start_abs
        best_before = d
      end
    end
    best = best_before
  end

  if not best and #directives > 0 then
    best = directives[1]
    for _, d in ipairs(directives) do
      local sr, sc = d:range()
      local start_abs = abs_pos(sr, sc)
      local best_start = abs_pos(best:range())
      if start_abs < best_start then
        best = d
      end
    end
  end

  if not best then
    return nil, nil, nil
  end

  local parts = {}
  local sibling = best:next_named_sibling()
  while sibling and sibling:type() == "parameter" do
    local txt = node_text(sibling, bufnr)
    if txt and txt:match("%S") then
      table.insert(parts, txt)
    end
    sibling = sibling:next_named_sibling()
  end

  if #parts == 0 then
    local parent = best:parent()
    if parent then
      local collect = false
      for child in parent:iter_children() do
        if collect and child:type() == "parameter" then
          local txt = node_text(child, bufnr)
          if txt and txt:match("%S") then
            table.insert(parts, txt)
          end
        end
        if child == best then
          collect = true
        end
      end
    end
  end

  if #parts == 0 then
    local up = best
    while up do
      local prev = up:prev_named_sibling()
      while prev do
        if prev:type() == "parameter" then
          local txt = node_text(prev, bufnr)
          if txt and txt:match("%S") then
            table.insert(parts, 1, txt)
          end
        else
          break
        end
        prev = prev:prev_named_sibling()
      end
      up = up:parent()
    end
  end

  local parameter_text = ""
  if #parts > 0 then
    parameter_text = table.concat(parts, "")
    parameter_text = clean_text(parameter_text)
  end

  local raw_directive_text = node_text(best, bufnr) or ""
  local directive_name = raw_directive_text:match("^@[%w_:-]+")
      or raw_directive_text:match("^[%w_:-]+")
      or raw_directive_text

  local function extract_first_arg_from_param_text(text)
    if not text or text:match("^%s*$") then
      return nil
    end
    local inner = text:match("^%s*%((.*)%)%s*$") or text
    local i, len = 1, #inner
    local nesting = 0
    local in_quote = nil
    local escaped = false
    local buf = {}
    while i <= len do
      local ch = inner:sub(i, i)
      if in_quote then
        if ch == "\\" and not escaped then
          escaped = true
          table.insert(buf, ch)
        else
          if ch == in_quote and not escaped then
            in_quote = nil
            table.insert(buf, ch)
          else
            table.insert(buf, ch)
            escaped = false
          end
        end
      else
        if ch == "'" or ch == '"' then
          in_quote = ch
          table.insert(buf, ch)
        elseif ch == "(" or ch == "[" or ch == "{" then
          nesting = nesting + 1
          table.insert(buf, ch)
        elseif ch == ")" or ch == "]" or ch == "}" then
          if nesting > 0 then
            nesting = nesting - 1
            table.insert(buf, ch)
          else
            break
          end
        elseif ch == "," and nesting == 0 then
          break
        else
          table.insert(buf, ch)
        end
      end
      i = i + 1
    end
    local s = table.concat(buf)
    s = clean_text(s)
    if s == "" then
      return nil
    end
    return s
  end

  local first_arg = nil
  if parameter_text and parameter_text ~= "" then
    local first_raw = extract_first_arg_from_param_text(parameter_text)
    if first_raw then
      first_arg = extract_first_argument(first_raw)
    end
  end

  if parameter_text and parameter_text ~= "" then
    if not parameter_text:match("^%s*%b()$") then
      parameter_text = "(" .. parameter_text .. ")"
    end
    return raw_directive_text .. parameter_text, directive_name, first_arg
  else
    return raw_directive_text, directive_name, nil
  end
end

function M.get_text_node()
  local bufnr = vim.api.nvim_get_current_buf()
  local node = safe_get_node_at_cursor(bufnr)
  if not node then
    return nil, nil, nil
  end

  local text, fname, first_arg = M.extract_php(node, bufnr)
  if not text then
    text, fname, first_arg = M.extract_directive(node, bufnr)
  end
  if not text then
    text, fname, first_arg = M.extract_component(bufnr)
  end

  if false then
    if text and fname then
      if first_arg then
        print("Extracted text: " .. text .. " (" .. fname .. ") -> " .. first_arg)
      else
        print("Extracted text: " .. text .. " (" .. fname .. ")")
      end
    else
      print("No interesting text found at cursor position")
    end
  end

  return text, fname, first_arg
end

return M
