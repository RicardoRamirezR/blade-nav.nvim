-- lua/blade-nav/core/textnode.lua
local M = {}

local ts = vim.treesitter

function M.node_text(node, bufnr)
  if not node then
    return nil
  end
  if vim.treesitter.get_node_text then
    return vim.treesitter.get_node_text(node, bufnr)
  elseif ts.query then
    return ts.query.get_node_text(node, bufnr)
  end
  return nil
end

function M.clean_text(text)
  if not text then
    return nil
  end
  return text:gsub("[\r\n]+", " "):gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
end

function M.get_cursor_pos()
  local cursor = vim.api.nvim_win_get_cursor(0)
  return cursor[1] - 1, cursor[2]
end

function M.find_parent(node, predicate)
  local current = node
  while current do
    if predicate(current) then
      return current
    end
    current = current:parent()
  end
  return nil
end

function M.safe_get_node_at_cursor(bufnr)
  local ft = vim.api.nvim_buf_get_option(bufnr, "filetype")
  if not ft or ft == "" then
    vim.notify("No filetype detected", vim.log.levels.WARN)
    return nil
  end

  local ok, parser = pcall(ts.get_parser, bufnr, ft)
  if not ok or not parser then
    print("NO PARSER FOR", ft)

    vim.notify("No parser available for buffer", vim.log.levels.WARN)
    return nil
  end

  local row, col = M.get_cursor_pos()
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

function M.extract_php(node, bufnr)
  node = M.find_parent(node, function(n)
    return n:type() == "php_statement" or n:type() == "function_call_expression"
  end)

  if not node then
    return nil
  end

  if node:type() == "function_call_expression" then
    return M.clean_text(M.node_text(node, bufnr))
  end

  for child in node:iter_children() do
    if child:type() == "php_only" then
      return M.clean_text(M.node_text(child, bufnr))
    end
  end

  return nil
end

function M.extract_element(bufnr)
  local row, col = M.get_cursor_pos()
  local ok, html_parser = pcall(ts.get_parser, bufnr, "html")
  if not ok or not html_parser then
    vim.notify("HTML parser not available for buffer", vim.log.levels.WARN)
    return nil
  end

  local trees = html_parser:parse()
  if not trees or #trees == 0 then
    return nil
  end

  local root = trees[1]:root()
  local node = root:descendant_for_range(row, col, row, col)
  if not node then
    return nil
  end

  local current = node
  while current do
    local t = current:type()
    if t == "start_tag" or t == "self_closing_tag" then
      return M.clean_text(M.node_text(current, bufnr))
    end
    if t == "tag_name" then
      local parent = current:parent()
      if parent and (parent:type() == "start_tag" or parent:type() == "self_closing_tag") then
        return M.clean_text(M.node_text(parent, bufnr))
      end
    end
    if t == "element" then
      for child in current:iter_children() do
        if child:type() == "start_tag" then
          return M.clean_text(M.node_text(child, bufnr))
        end
      end
    end
    current = current:parent()
  end

  return nil
end

function M.find_directive_context(node)
  -- First, try to find a directive node directly
  local directive_node = M.find_parent(node, function(n)
    return n:type() == "directive"
  end)

  if directive_node then
    return directive_node
  end

  -- If cursor is in parameters, look for directive among siblings
  -- Traverse up to find a node that has directive siblings
  local current = node
  while current do
    local parent = current:parent()
    if parent then
      -- Check if any sibling is a directive
      for child in parent:iter_children() do
        if child:type() == "directive" then
          return child
        end
      end
    end
    current = parent
  end

  return nil
end

function M.extract_directive(node, bufnr)
  if not node then
    return nil
  end

  -- Find the directive node (could be current node or a sibling)
  local directive_node = M.find_directive_context(node)

  if not directive_node or directive_node:type() ~= "directive" then
    return nil
  end

  -- Get the row range for the directive
  local start_row, start_col, _, _ = directive_node:range()

  -- Find the end of the directive by looking at siblings
  local end_row, end_col = directive_node:range() -- fallback to directive itself

  -- Look for the last parameter or directive_end sibling
  local parent = directive_node:parent()
  if parent then
    local last_relevant_node = directive_node
    local found_parameters = false

    for child in parent:iter_children() do
      local child_start_row = child:range()

      -- Only consider nodes that come after the directive
      if child_start_row >= start_row then
        if child:type() == "parameter" then
          last_relevant_node = child
          found_parameters = true
        elseif child:type() == "directive_end" then
          last_relevant_node = child
          break
        elseif found_parameters and child:type() ~= "directive" then
          -- Stop if we've found parameters and hit a different type of node
          break
        end
      end
    end

    _, _, end_row, end_col = last_relevant_node:range()
  end

  -- Extract the complete text from start to end
  local lines = vim.api.nvim_buf_get_text(bufnr, start_row, start_col, end_row, end_col, {})
  local raw_text = table.concat(lines, "\n")

  return M.clean_text(raw_text)
end

function M.get_text_node()
  local bufnr = vim.api.nvim_get_current_buf()
  local node = M.safe_get_node_at_cursor(bufnr)
  if not node then
    return nil
  end

  return M.extract_php(node, bufnr) or M.extract_directive(node, bufnr) or M.extract_element(bufnr) or nil
end

return M
