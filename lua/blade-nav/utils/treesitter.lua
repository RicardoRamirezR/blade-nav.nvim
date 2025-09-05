-- lua/blade-nav/utils/treesitter.lua
-- Utility functions for advanced Tree-sitter operations.

local log = require("blade-nav.utils.log")

local M = {}

--- Extracts the Blade directive name from a line of text using Tree-sitter.
--- @param line_text string The line of text containing the directive.
--- @return string|nil The directive name (e.g., "@extends") or nil.
local function extract_blade_directive(line_text, target_fn)
  local ok, parser = pcall(vim.treesitter.get_string_parser, line_text, "blade")
  if not ok or not parser then
    log.debug("TS Blade parser creation failed for line: %s. Error: %s", line_text, tostring(parser))
    return nil
  end

  local ok_tree, tree = pcall(function()
    return parser:parse()[1]
  end)
  if not ok_tree or not tree then
    log.debug("TS Blade parsing failed for line: %s. Error: %s", line_text, tostring(tree))
    return nil
  end
  local root = tree:root()

  local ok_query, query = pcall(
    vim.treesitter.query.parse,
    "blade",
    string.format(
      [[
        ((directive) @directive
          (#any-of? @directive "%s"))
        ]],
      target_fn
    )
  )
  if not ok_query or not query then
    log.debug("TS Blade query parsing failed. Error: %s", tostring(query))
    return nil
  end

  log.debug("TS Blade query matches: %s", vim.inspect(query:iter_captures(root, line_text)))
  for id, node, _ in query:iter_captures(root, line_text) do
    if query.captures[id] == "directive" then
      local text = vim.treesitter.get_node_text(node, line_text)
      return text
    end
  end

  return nil
end

--- Converts a simple PHP array string to a Lua table of strings.
--- Note: This is a basic implementation. For complex arrays, full PHP TS parsing is needed.
--- @param text string The PHP array literal string (e.g., '['a', 'b']').
--- @return table List of string values.
local function php_array_to_lua(text)
  local items = {}

  for str in text:gmatch("'([^']*)'") do
    table.insert(items, str)
  end

  for str in text:gmatch('"([^"]*)"') do
    table.insert(items, str)
  end
  return items
end

--- Extracts the first argument (and potentially the fourth for @each) from a Blade directive line.
--- Uses the technique of transforming the directive into synthetic PHP and parsing it.
--- @param line_text string The line containing the Blade directive.
--- @param target_fn string The target Blade directive to match (e.g., "@livewire").
--- @return string|nil, table|nil Directive name, table containing the extracted argument(s).
function M.extract_first_blade_argument(line_text, target_fn)
  local directive = extract_blade_directive(line_text, target_fn)
  if not directive then
    log.debug("No target Blade directive found in line: %s", line_text)
    return nil, nil
  end

  local php_function_name = "blade_" .. directive:sub(2)
  local php_code = "<?php\n" .. line_text:gsub("^%s*" .. directive:gsub("%p", "%%%0"), php_function_name) .. ";"
  log.debug("Synthetic PHP code for parsing '%s': %s", directive, php_code)

  local ok, parser = pcall(vim.treesitter.get_string_parser, php_code, "php")
  if not ok or not parser then
    log.debug("TS PHP parser creation failed for synthetic code: %s. Error: %s", php_code, tostring(parser))
    return directive, nil
  end

  local ok_tree, tree = pcall(function()
    return parser:parse()[1]
  end)
  if not ok_tree or not tree then
    log.debug("TS PHP parsing failed for synthetic code: %s. Error: %s", php_code, tostring(tree))
    return directive, nil
  end
  local root = tree:root()

  local result = {}

  local ok_query_main, query_main = pcall(
    vim.treesitter.query.parse,
    "php",
    [[
        (function_call_expression
          function: (name) @fn
          arguments: (arguments
            (argument (string (string_content) @first_str))
            (_)*
          )
        )
        (function_call_expression
          function: (name) @fn
          arguments: (arguments
            (argument (array_creation_expression) @first_arr)
            (_)*
          )
        )
        ]]
  )
  if not ok_query_main or not query_main then
    log.debug("TS PHP main query parsing failed. Error: %s", tostring(query_main))
    return directive, result
  end

  local found_first = false
  for id, node, _ in query_main:iter_captures(root, php_code) do
    local name = query_main.captures[id]
    if not found_first and name == "first_str" then
      local str_text = vim.treesitter.get_node_text(node, php_code)
      log.debug("Found first argument (string): %s", str_text)
      table.insert(result, str_text)
      found_first = true
    elseif not found_first and name == "first_arr" then
      local raw_array_text = vim.treesitter.get_node_text(node, php_code)
      log.debug("Found first argument (array): %s", raw_array_text)
      local array_items = php_array_to_lua(raw_array_text)
      if type(array_items) == "table" then
        for _, item in ipairs(array_items) do
          if type(item) == "string" then
            table.insert(result, item)
          end
        end
      end
      found_first = true
    end
    if found_first then
      break
    end
  end

  if directive == "@each" then
    local ok_query_each, query_each = pcall(
      vim.treesitter.query.parse,
      "php",
      [[
            (function_call_expression
              arguments: (arguments
                (_) (_) (_)
                (argument (string (string_content) @empty_view))?
              )
            )
            ]]
    )
    if ok_query_each and query_each then
      for id, node, _ in query_each:iter_captures(root, php_code) do
        if query_each.captures[id] == "empty_view" then
          local empty_view_text = vim.treesitter.get_node_text(node, php_code)
          log.debug("Found @each 4th argument (empty view): %s", empty_view_text)
          table.insert(result, empty_view_text)
        end
      end
    else
      log.debug("TS PHP @each query parsing failed. Error: %s", tostring(query_each))
    end
  end

  return directive, result
end

--- Extracts Blade component names from a line using Tree-sitter.
--- Based directly on the provided research code.
--- @param line_text string The line of text to parse.
--- @return string|nil The extracted component name or nil if not found.
function M.extract_component(line_text, target_name)
  log.debug("Extracting component names from line: %s, target: %s", line_text, target_name)
  local parser = vim.treesitter.get_string_parser(line_text, "html")
  local tree = parser:parse()[1]
  local root = tree:root()

  local query = vim.treesitter.query.parse(
    "html",
    string.format(
      [[
      ((start_tag
         (tag_name) @tag_name
         (attribute (attribute_name) @attribute))
       (#match? @tag_name "%s"))

      ((self_closing_tag
         (tag_name) @tag_name
         (attribute (attribute_name) @attribute))
       (#match? @tag_name "%s"))

      ((start_tag (tag_name) @tag_name)
       (#match? @tag_name "%s"))

      ((self_closing_tag (tag_name) @tag_name)
       (#match? @tag_name "%s"))
    ]],
      target_name,
      target_name,
      target_name,
      target_name
    )
  )

  local current_tag = nil
  local parts = {}

  for id, node in query:iter_captures(root, line_text) do
    local name = query.captures[id]
    local text = vim.treesitter.get_node_text(node, line_text)

    if name == "tag_name" then
      current_tag = text:gsub("^x%-", "")
    elseif name == "attribute" and text:sub(1, 1) == "." then
      table.insert(parts, text:sub(2))
    end
  end

  if current_tag and #parts > 0 then
    return current_tag .. "." .. table.concat(parts, ".")
  end

  return current_tag
end

function M.extract_php_function_keys(php_code, target_fn)
  local keys = {}

  if not php_code:match("^%s*<%?php") then
    php_code = "<?php " .. php_code
  end
  log.debug(php_code)

  local php_parser = vim.treesitter.get_string_parser(php_code, "php")
  local php_tree = php_parser:parse()[1]
  if not php_tree then
    log.debug(
      "TS PHP parsing failed in extract_php_config_keys for code: %s",
      php_code:sub(1, 50) .. (php_code:len() > 50 and "..." or "")
    )
    return keys
  end

  local php_root = php_tree:root()

  local query_string = [[
    ; Standard function call:
    ; config('key'), env('key') route('name') view('view') markdown('markdown') interia('view')
    (function_call_expression
      function: (name) @fn_name
      arguments: (arguments
        (argument
          [
            (string (string_content) @key_str)
            (array_creation_expression
              (array_element_initializer
                (string (string_content) @key_str)))
          ])
        . (_)*)
      (#eq? @fn_name "%s"))

      ; Scoped call:
      ; Config::get('key'), Config::set('key', ...) Route::view('view', ...) View::make('view') Inertia::render('view')
      ; This part matches when target_fn is the method name (e.g., "get", "set", "make", "view", "render")
      (scoped_call_expression
        scope: (name) @scope
        name: (name) @method
        arguments: (arguments
          (argument
            (string
              (string_content) @key_str)))
        (#eq? @scope "%s")
        (#any-of? @method "get" "set" "make" "view" "render"))
  ]]

  local scope = target_fn:gsub("^%l", string.upper)
  local php_query = vim.treesitter.query.parse("php", string.format(query_string, target_fn, scope))

  for id, node in php_query:iter_captures(php_root, php_code) do
    if php_query.captures[id] == "key_str" then
      table.insert(keys, vim.treesitter.get_node_text(node, php_code))
    end
  end

  return keys
end

local function extract_blade_function_keys(line_text, target_fn)
  local keys = {}
  local blade_parser = vim.treesitter.get_string_parser(line_text, "blade")
  local blade_tree = blade_parser:parse()[1]
  local blade_root = blade_tree:root()

  local php_only_query = vim.treesitter.query.parse("blade", "(php_only) @php")

  for _, node in php_only_query:iter_captures(blade_root, line_text) do
    local php_code = vim.treesitter.get_node_text(node, line_text)
    local partial_keys = M.extract_php_function_keys(php_code, target_fn)
    vim.list_extend(keys, partial_keys)
  end

  return keys
end

function M.extract_keys_from_code(line_text, target_fn)
  log.debug("Extracting keys from code: %s, target_fn: %s", line_text, target_fn)
  local keys = extract_blade_function_keys(line_text, target_fn)
  if #keys == 0 then
    keys = M.extract_php_function_keys(line_text, target_fn)
  end
  log.debug("Extracted keys: %s", vim.inspect(keys))
  return keys
end

--- Gets the Tree-sitter root node and language for the current buffer.
--- @return table|nil, string|nil Root node and language, or nils.
function M.gets_root_and_lang()
  local ts_status, ts = pcall(require, "vim.treesitter")
  if not ts_status or not ts then
    log.warn("BladeNav Route (goto_method): vim.treesitter not available.")
    return nil, nil
  end

  local bufnr = 0
  local lang = ts.language.get_lang(vim.api.nvim_buf_get_option(bufnr, "filetype"))
  if not lang then
    log.warn("BladeNav Route (goto_method): Could not determine language for current buffer.")
    return nil, nil
  end

  local parser = ts.get_parser(bufnr, lang)
  if not parser then
    log.warn("BladeNav Route (goto_method): Could not get TS parser for buffer %d lang %s.", bufnr, lang)
    return nil, lang
  end

  local tree = parser:parse()[1]
  if not tree then
    log.warn("BladeNav Route (goto_method): Could not parse buffer %d.", bufnr)
    return nil, lang
  end

  local root = tree:root()
  return root, lang
end

return M
