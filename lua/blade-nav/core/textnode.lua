-- lua/blade-nav/core/textnode.lua

local log = require("blade-nav.utils.log")
-- LuaJIT has no table.unpack; fall back to the global unpack (deprecated in Lua 5.2+).
---@diagnostic disable-next-line: deprecated
local unpack = table.unpack or unpack -- luacheck: ignore 143

local M = {}
local ts = vim.treesitter

local TARGET_LISTS = {
  php = {
    "Config::get",
    "Config::set",
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
    "__",
    "trans",
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
}

local function is_target(name, interest_type)
  if not name or not interest_type then
    return false
  end

  if interest_type == "component" then
    return name:match("^x%-") ~= nil or name:match("^livewire:") ~= nil
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
  local cleaned = text:gsub("[\r\n]+", " "):gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
  return cleaned
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
  local ft = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
  if not ft or ft == "" then
    log.debug("No filetype detected")
    return nil
  end

  local ok, parser = pcall(ts.get_parser, bufnr, ft)
  if not ok or not parser then
    log.debug("No parser available for buffer")
    return nil
  end

  local row, col = get_cursor_pos()
  local ok2, node = pcall(function()
    if ts.get_node then
      return ts.get_node({ bufnr = bufnr, pos = { row, col } })
    elseif ts.get_node_at_pos then
      return ts.get_node_at_pos(bufnr, row, col, {})
    else
      local tree = parser:parse()[1]
      return tree and tree:root():descendant_for_range(row, col, row, col)
    end
  end)

  if not ok2 then
    log.debug("Error getting node: %s", tostring(node))
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

function M.set_target_lists(lists)
  if lists.php then
    TARGET_LISTS.php = lists.php
  end
  if lists.directive then
    TARGET_LISTS.directive = lists.directive
  end
end

function M.get_target_lists()
  return TARGET_LISTS
end

--- Extract PHP function/method call info starting from the node at the cursor.
--- Walks up once to the nearest interesting ancestor (function/scoped call, or a
--- php_only statement); if that call isn't itself a recognized target, continues
--- walking up the same chain looking for an enclosing call that is.
--- @param node TSNode Tree-sitter node at cursor position
--- @param bufnr integer Buffer number
--- @return string|nil, string|nil, string|nil complete node text, function name, first argument
function M.extract_php(node, bufnr)
  local start_node = find_parent(node, function(n)
    return vim.tbl_contains({ "php_statement", "function_call_expression", "scoped_call_expression" }, n:type())
  end)
  if not start_node then
    return nil, nil, nil
  end

  local function get_first_argument(target_node, buf, function_name)
    for child in target_node:iter_children() do
      if child:type() == "arguments" then
        local args = {}
        for arg_child in child:iter_children() do
          if arg_child:type() ~= "(" and arg_child:type() ~= ")" and arg_child:type() ~= "," then
            local raw_arg = node_text(arg_child, buf)
            args[#args + 1] = clean_text(raw_arg)
          end
        end

        if #args > 0 then
          -- Excepción: en Route::view el "first_arg" de interés es el segundo parámetro
          local index = 1
          if function_name == "Route::view" and #args >= 2 then
            index = 2
          end

          local raw = args[index]
          return raw, extract_first_argument(raw)
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

      local first_arg, clean_first_arg = get_first_argument(target_node, bufnr, function_name)
      if first_arg and function_name then
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

      local first_arg, clean_first_arg = get_first_argument(target_node, bufnr, function_name)
      if first_arg and function_name then
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
        local clean_first_arg
        if first_arg and function_name then
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

  local text, function_name, first_arg = extract_from_node(start_node)

  if not function_name then
    return text, nil, first_arg
  end

  if is_target(function_name, "php") then
    return text, function_name, first_arg
  end

  -- Not a recognized target on its own: walk up the ancestor chain once,
  -- looking for an enclosing call that is (e.g. cursor on `auth()` nested
  -- inside `Inertia::render(..., ['user' => auth()->user()])`).
  local current = start_node:parent()
  while current do
    if vim.tbl_contains({ "function_call_expression", "scoped_call_expression" }, current:type()) then
      local p_text, p_function_name, p_first_arg = extract_from_node(current)
      if p_function_name and is_target(p_function_name, "php") then
        return p_text, p_function_name, p_first_arg
      end
    elseif current:type() == "php_statement" then
      for child in current:iter_children() do
        if child:type() == "php_only" then
          local p_function_name = extract_function_name_from_php_only(child, bufnr)
          if p_function_name and is_target(p_function_name, "php") then
            local p_text, fname, p_first_arg = extract_from_node(current)
            return p_text, fname, p_first_arg
          end
        end
      end
    end
    current = current:parent()
  end

  return text, function_name, first_arg
end

local function classify_tag_name(tag_name)
  if not tag_name then
    return "component", nil
  end
  if tag_name:match("^x%-") then
    return "component", tag_name:gsub("^x%-", "")
  end
  if tag_name:match("^livewire:") then
    return "livewire", tag_name:gsub("^livewire:", "")
  end
  return "component", tag_name
end

function M.extract_component(bufnr)
  local row, col = get_cursor_pos()
  local ok, html_parser = pcall(ts.get_parser, bufnr, "html")
  if not ok or not html_parser then
    log.debug("HTML parser not available for buffer")
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
      local component_type, component_path = classify_tag_name(tag_name)
      return full_text, component_type, component_path
    end

    if t == "tag_name" then
      local parent = target_node:parent()
      if parent and (parent:type() == "start_tag" or parent:type() == "self_closing_tag") then
        local full_text = clean_text(node_text(parent, bufnr))
        local tag_name = full_text:match("<%s*([%w%-:%.]+)")
        local component_type, component_path = classify_tag_name(tag_name)
        return full_text, component_type, component_path
      end
    end

    if t == "component" then
      for child in target_node:iter_children() do
        if child:type() == "start_tag" then
          local full_text = clean_text(node_text(child, bufnr))
          local tag_name = full_text:match("<%s*([%w%-:%.]+)")
          local component_type, component_path = classify_tag_name(tag_name)
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
      local tag_name = text:match("<%s*([%w%-:%.]+)")
      if tag_name and is_target(tag_name, "component") then
        return text, component_type, component_path
      end
    end
    current = current:parent()
  end

  return nil, nil, nil
end

-- Helper: read buffer text between two positions (inclusive start, inclusive endcol)
local function get_text_range(bufnr, sr, sc, er, ec)
  local lines = vim.api.nvim_buf_get_lines(bufnr, sr, er + 1, false)
  if not lines or #lines == 0 then
    return ""
  end
  if sr == er then
    return string.sub(lines[1], sc + 1, ec)
  end
  local out = {}
  out[#out + 1] = string.sub(lines[1], sc + 1)
  for i = 2, #lines - 1 do
    out[#out + 1] = lines[i]
  end
  out[#out + 1] = string.sub(lines[#lines], 1, ec)
  return table.concat(out, "\n")
end

-- Find matching closing parenthesis starting from directive start (returns full substring up to
-- matching ')', and end row/col). Requires '(' to immediately follow the directive name, and
-- bounds the scan to avoid walking to the end of the buffer for directives with no parameter list.
local MAX_CLOSING_PAREN_SCAN_LINES = 50

local function find_closing_paren(bufnr, start_row, start_col, name_len)
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_row, start_row + MAX_CLOSING_PAREN_SCAN_LINES, false)
  if not lines or #lines == 0 then
    return nil
  end

  local paren_col = start_col + (name_len or 0)
  local first_line = lines[1] or ""
  if first_line:sub(paren_col + 1, paren_col + 1) ~= "(" then
    return nil
  end

  local row = start_row
  local col = start_col
  local found_open = false
  local depth = 0
  local in_quote = nil
  local parts = {}

  while row - start_row + 1 <= #lines do
    local line = lines[row - start_row + 1] or ""
    local line_len = #line
    while col <= line_len do
      local ch = line:sub(col + 1, col + 1)
      parts[#parts + 1] = ch

      if not found_open then
        if ch == "(" then
          found_open = true
          depth = 1
        end
      else
        if in_quote then
          if ch == "\\" then
            -- include escaped char (if inside same line)
            col = col + 1
            local nxt = line:sub(col + 1, col + 1)
            if nxt ~= "" then
              parts[#parts + 1] = nxt
            end
          elseif ch == in_quote then
            in_quote = nil
          end
        else
          if ch == "'" or ch == '"' or ch == "`" then
            in_quote = ch
          elseif ch == "(" then
            depth = depth + 1
          elseif ch == ")" then
            depth = depth - 1
            if depth == 0 then
              local full = table.concat(parts)
              -- return full string and end position (row, col) where col is 0-based index of ')'
              return full, row, col
            end
          end
        end
      end

      col = col + 1
    end

    -- newline char between lines
    parts[#parts + 1] = "\n"
    row = row + 1
    col = 0
  end

  return nil
end

-- Split a parameter block into top-level parameters (ignore commas inside quotes/brackets/parentheses)
local function split_top_level_params(s)
  if not s then
    return {}
  end
  local i, len = 1, #s
  local depth = 0
  local in_quote = nil
  local acc = {}
  local cur = {}

  while i <= len do
    local c = s:sub(i, i)
    if in_quote then
      if c == "\\" then
        cur[#cur + 1] = c
        i = i + 1
        local nxt = s:sub(i, i)
        if nxt ~= "" then
          cur[#cur + 1] = nxt
        end
      elseif c == in_quote then
        in_quote = nil
        cur[#cur + 1] = c
      else
        cur[#cur + 1] = c
      end
    else
      if c == "'" or c == '"' or c == "`" then
        in_quote = c
        cur[#cur + 1] = c
      elseif c == "(" or c == "[" or c == "{" then
        depth = depth + 1
        cur[#cur + 1] = c
      elseif c == ")" or c == "]" or c == "}" then
        if depth > 0 then
          depth = depth - 1
        end
        cur[#cur + 1] = c
      elseif c == "," and depth == 0 then
        local item = table.concat(cur)
        acc[#acc + 1] = clean_text(item)
        cur = {}
      else
        cur[#cur + 1] = c
      end
    end
    i = i + 1
  end

  if #cur > 0 then
    acc[#acc + 1] = clean_text(table.concat(cur))
  end
  return acc
end

local directive_query_cache = nil

-- Parse the directive/parameter query once and reuse it (it never changes: `ft` is
-- always "blade").
local function get_directive_query()
  if directive_query_cache ~= nil then
    return directive_query_cache or nil
  end

  local query_str = [[
    (directive) @directive
    (parameter) @parameter
  ]]

  local parse_query = (ts.query and ts.query.parse) or ts.parse_query
  local okq, q = pcall(parse_query, "blade", query_str)
  directive_query_cache = okq and q or false
  return directive_query_cache or nil
end

-- Collect directives and param_nodes grouped by parent (params attached only to immediately preceding directive)
local function collect_directives(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local ft = "blade"
  local ok, parser = pcall(ts.get_parser, bufnr, ft)
  if not ok or not parser then
    return {}
  end
  local tree = parser:parse()[1]
  if not tree then
    return {}
  end
  local root = tree:root()

  local q = get_directive_query()
  if not q then
    return {}
  end

  -- group by parent node
  local groups = {}
  for id, cap_node in q:iter_captures(root, bufnr, 0, -1) do
    local cap_name = (q.captures and q.captures[id]) or ""
    local parent = cap_node:parent()
    if parent then
      local psr, psc, per, pec = parent:range()
      local key = string.format("%d:%d:%d:%d", psr, psc, per, pec)
      if not groups[key] then
        groups[key] = { parent = parent, caps = {} }
      end
      local caps = groups[key].caps
      caps[#caps + 1] = { name = cap_name, node = cap_node }
    end
  end

  local directives = {}

  for _, g in pairs(groups) do
    table.sort(g.caps, function(a, b)
      local ar, ac = a.node:range()
      local br, bc = b.node:range()
      if ar == br then
        return ac < bc
      end
      return ar < br
    end)

    local current = nil
    for _, cap in ipairs(g.caps) do
      if cap.name == "directive" then
        if current then
          directives[#directives + 1] = current
        end
        local sr, sc, er, ec = cap.node:range()
        local dir_text = node_text(cap.node, bufnr) or ""
        current = {
          name = dir_text:match("^@[%w_]+") or dir_text,
          node_type = "directive",
          directive_node = cap.node,
          start = { sr, sc },
          endpos = { er, ec },
          param_nodes = {},
          params = {}, -- will be replaced by split result later
        }
      elseif cap.name == "parameter" then
        if current then
          current.param_nodes[#current.param_nodes + 1] = cap.node
          local _, _, per, pec = cap.node:range()
          -- keep endpos updated to last parameter end (fallback)
          current.endpos = { per, pec }
        end
      end
    end

    if current then
      directives[#directives + 1] = current
    end
  end

  table.sort(directives, function(a, b)
    local ar, ac = a.start[1], a.start[2]
    local br, bc = b.start[1], b.start[2]
    if ar == br then
      return ac < bc
    end
    return ar < br
  end)

  return directives
end

-- Find directive at cursor; build robust full_text and split params top-level
function M.find_directive_at_cursor(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local directives = collect_directives(bufnr)
  local r, c = get_cursor_pos()

  for _, d in ipairs(directives) do
    local sr, sc = unpack(d.start)
    local er, ec = unpack(d.endpos)
    local inside = (r > sr or (r == sr and c >= sc)) and (r < er or (r == er and c <= ec))
    if inside then
      -- attempt to find real closing paren after directive start
      local raw_full, end_r, end_c = find_closing_paren(bufnr, sr, sc, #(d.name or ""))
      if raw_full then
        d.full_text = clean_text(raw_full)
        d.endpos = { end_r, end_c }
      else
        -- fallback: use from directive start to last param end (may miss trailing ')')
        d.full_text = clean_text(get_text_range(bufnr, sr, sc, er, ec) or "")
      end

      -- extract parameter block (content inside the outermost parentheses)
      local open_i = d.full_text and d.full_text:find("(", 1, true)
      local close_i = d.full_text and #d.full_text
      local param_block = nil
      if open_i and close_i and close_i > open_i then
        param_block = d.full_text:sub(open_i + 1, close_i - 1)
      else
        -- fallback: assemble from param_nodes raw text contiguous
        if d.param_nodes and #d.param_nodes > 0 then
          local p0 = d.param_nodes[1]
          local last = d.param_nodes[#d.param_nodes]
          local p0_sr, p0_sc = p0:range()
          local _, _, last_er, last_ec = last:range()
          param_block = get_text_range(bufnr, p0_sr, p0_sc, last_er, last_ec)
        end
      end

      -- split into top-level params robustly
      local params = split_top_level_params(param_block or "")
      if #params == 0 and d.param_nodes and #d.param_nodes > 0 then
        -- last resort: use raw param node texts joined
        local acc = {}
        for _, n in ipairs(d.param_nodes) do
          acc[#acc + 1] = clean_text(node_text(n, bufnr) or "")
        end
        params = { table.concat(acc, ", ") }
      end

      d.params = params
      d.first_arg = nil
      if params and params[1] then
        d.first_arg = extract_first_argument(params[1])
      end

      return d
    end
  end

  return nil
end

--- Extract Blade directive info consistent with extract_php / extract_component contract.
--- Returns: full_text (string), fname (string, like "@include"), first_arg (string | table)
--- first_arg rules:
---   - @extends, @include, @each -> first_arg = first parameter (cleaned string)
---   - @includeWhen, @includeUnless -> first_arg = second parameter (cleaned string)
---   - @includeFirst -> first_arg = table of all views inside the array (no [ ])
function M.extract_directive(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- get the structured directive found at cursor (uses collect_directives / find_directive_at_cursor)
  local d = M.find_directive_at_cursor(bufnr)
  if not d then
    return nil, nil, nil
  end

  -- full text and directive name
  local full_text = d.full_text or (d.directive_node and node_text(d.directive_node, bufnr)) or nil
  local fname = d.name or (full_text and full_text:match("^@[%w_]+")) or nil
  if not fname then
    return nil, nil, nil
  end

  -- small helpers
  local function strip_quotes(s)
    if not s then
      return nil
    end
    local stripped = s:gsub("^%s*['\"](.-)['\"]%s*$", "%1")
    return stripped
  end

  local function extract_views_from_array(raw)
    if not raw then
      return {}
    end
    raw = clean_text(raw)
    -- remove outer brackets if present
    if raw:match("^%[.*%]$") then
      raw = raw:sub(2, -2)
    end
    local out = {}
    -- extract quoted entries in a single pass (either quote style) to preserve source order
    for _, v in raw:gmatch("(['\"])(.-)%1") do
      out[#out + 1] = v
    end
    -- fallback: split by top-level commas (simple)
    if #out == 0 then
      for item in raw:gmatch("([^,]+)") do
        local c = strip_quotes(clean_text(item))
        if c and c ~= "" then
          out[#out + 1] = c
        end
      end
    end
    return out
  end

  local first_arg = nil
  local params = d.params or {}

  -- Decide which param(s) represent the view(s)
  if fname == "@includeWhen" or fname == "@includeUnless" then
    -- second parameter is the view (first parameter is the boolean condition)
    local candidate = params[2]
    if candidate then
      first_arg = extract_first_argument(candidate) or strip_quotes(candidate) or clean_text(candidate)
    end
  elseif fname == "@includeFirst" then
    -- first parameter is an array of views -> return ALL views (no brackets) as a table
    local raw = params[1] or ""
    local views = extract_views_from_array(raw)
    if #views > 0 then
      first_arg = views
    else
      -- fallback: if nothing parsed, attempt simple extract_first_argument
      local maybe = extract_first_argument(raw)
      if maybe then
        first_arg = { maybe }
      else
        first_arg = {}
      end
    end
  elseif fname == "@each" then
    -- first param is main view, fourth param (if any) is the empty view
    local views = {}
    if params[1] then
      views[#views + 1] = extract_first_argument(params[1]) or strip_quotes(params[1]) or clean_text(params[1])
    end
    if params[4] then
      views[#views + 1] = extract_first_argument(params[4]) or strip_quotes(params[4]) or clean_text(params[4])
    end
    first_arg = views
  else
    -- default: first parameter is the view (@extends, @include, @each, @component, etc.)
    local candidate = params[1]
    if candidate then
      first_arg = extract_first_argument(candidate) or strip_quotes(candidate) or clean_text(candidate)
    end
  end

  return full_text, fname, first_arg
end

--- Try to extract interesting text from the current cursor position.
--- Order matters: PHP calls > Blade components/tags > Blade directives.
function M.get_text_node()
  local bufnr = vim.api.nvim_get_current_buf()
  local node = safe_get_node_at_cursor(bufnr)
  if not node then
    return nil, nil, nil
  end

  local text, fname, first_arg = M.extract_php(node, bufnr)
  if text then
    return text, fname, first_arg
  end

  text, fname, first_arg = M.extract_component(bufnr)
  if text then
    return text, fname, first_arg
  end

  text, fname, first_arg = M.extract_directive(bufnr)
  if text then
    return text, fname, first_arg
  end

  return nil, nil, nil
end

return M
