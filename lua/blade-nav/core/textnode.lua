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

function M.extract_directive(node, bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2]

  -- Get parser for current buffer
  local parser = vim.treesitter.get_parser(bufnr, "blade")
  if not parser then
    return nil, "No Blade parser available"
  end

  -- Parse and get the root node
  local tree = parser:parse()
  local root = tree[1]:root()

  -- Find the node at cursor position
  local cursor_node = root:descendant_for_range(row, col, row, col)
  if not cursor_node then
    return nil, "No node found at cursor position"
  end

  -- Find the nearest directive or parameter node, handling parentheses
  local current_node = cursor_node
  local directive_node = nil
  local parameter_node = nil

  while current_node do
    local node_type = current_node:type()

    if node_type == "directive" then
      directive_node = current_node
      break
    elseif node_type == "parameter" then
      parameter_node = current_node
      -- Continue searching for directive node
      local prev_sibling = current_node:prev_named_sibling()
      if prev_sibling and prev_sibling:type() == "directive" then
        directive_node = prev_sibling
        break
      end
    elseif node_type == "(" then
      -- Handle opening parenthesis
      local next_sibling = current_node:next_named_sibling()
      if next_sibling and next_sibling:type() == "parameter" then
        parameter_node = next_sibling
        -- Find the directive node
        local prev_sibling = parameter_node:prev_named_sibling()
        if prev_sibling and prev_sibling:type() == "directive" then
          directive_node = prev_sibling
          break
        end
      end
    elseif node_type == ")" then
      -- Handle closing parenthesis - this is trickier
      -- Look for the parameter node that should contain this parenthesis
      local parent = current_node:parent()

      -- If the parenthesis is directly under a parameter node
      if parent and parent:type() == "parameter" then
        parameter_node = parent
        local prev_sibling = parent:prev_named_sibling()
        if prev_sibling and prev_sibling:type() == "directive" then
          directive_node = prev_sibling
          break
        end
      else
        -- If not, look for siblings that might be parameter nodes
        local prev_sibling = current_node:prev_named_sibling()
        while prev_sibling do
          if prev_sibling:type() == "parameter" then
            parameter_node = prev_sibling
            local directive_sibling = prev_sibling:prev_named_sibling()
            if directive_sibling and directive_sibling:type() == "directive" then
              directive_node = directive_sibling
              break
            end
            break
          end
          prev_sibling = prev_sibling:prev_named_sibling()
        end

        if directive_node then
          break
        end
      end
    end

    current_node = current_node:parent()
  end

  -- If we found a parameter but no directive, search siblings
  if parameter_node and not directive_node then
    directive_node = parameter_node:prev_named_sibling()
  end

  -- If we still don't have a directive node, check if we're in a directive context
  if not directive_node then
    -- Check if we're between a directive and its parameter
    local parent = cursor_node:parent()
    if parent and parent:type() == "directive" then
      directive_node = parent
    else
      return nil
    end
  end

  -- Extract directive name
  local directive_text = M.node_text(directive_node, bufnr)
  if not directive_text then
    return nil
  end

  -- Clean directive text (remove @ and parentheses if present)
  directive_text = directive_text:match("^([%w_]+)%)?") or directive_text:match("^([%w_]+)") or directive_text

  -- Find parameter node if it exists
  if not parameter_node then
    parameter_node = directive_node:next_named_sibling()
    if parameter_node and parameter_node:type() ~= "parameter" then
      parameter_node = nil
    end
  end

  local parameter_text = nil

  if parameter_node and parameter_node:type() == "parameter" then
    parameter_text = M.node_text(parameter_node, bufnr)
  end

  -- Format the return string
  if parameter_text then
    parameter_text = M.clean_text(parameter_text)
    -- Wrap parameter in parentheses if not already
    if not parameter_text:match("^%s*%b()$") then
      parameter_text = "(" .. parameter_text .. ")"
    end
    return directive_text .. parameter_text
  else
    return directive_text
  end
end

function M.get_text_node()
  local bufnr = vim.api.nvim_get_current_buf()
  local node = M.safe_get_node_at_cursor(bufnr)
  if not node then
    return nil
  end

  local text = M.extract_php(node, bufnr) or M.extract_directive(node, bufnr) or M.extract_element(bufnr) or nil

  return text
end

return M
