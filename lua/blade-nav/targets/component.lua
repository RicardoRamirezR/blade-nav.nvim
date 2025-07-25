-- lua/blade-nav/targets/component.lua
local log = require("blade-nav.utils.log")

local M = {}

-- Mapping of Blade component patterns to their argument index or extraction logic
-- For directives like @component('name'), index refers to the argument.
-- For tags like <x-name />, we'll identify the tag name differently.
local COMPONENT_PATTERNS = {
  { pattern = "^@component$", arg_index = 0 }, -- Matches @component('alert')
  -- Add others if needed, like custom directives
}

--- Extract component name from function call arguments node using Tree-sitter.
--- @param arguments_node TSNode The arguments node from the function call
--- @param arg_index integer Index of the argument containing the component alias (0-based)
--- @param buffer integer Buffer number for text extraction
--- @return string|nil Extracted component alias or nil
local function extract_component_name_from_args(arguments_node, arg_index, buffer)
  log.debug("Called with arg_index: %s", tostring(arg_index))
  if not arguments_node then
    log.debug("arguments_node is nil")
    return nil
  end

  local arg_node = arguments_node:named_child(arg_index)
  log.debug("arg_node type: %s", tostring(arg_node and arg_node:type() or "nil"))
  if not arg_node or arg_node:type() ~= "argument" then
    log.debug("arg_node is nil or not 'argument' type")
    return nil
  end

  local value_node = arg_node:named_child(0) -- The actual value (string, variable, etc.)
  log.debug("value_node type: %s", tostring(value_node and value_node:type() or "nil"))
  if not value_node or value_node:type() ~= "string" then
    log.debug("value_node is nil or not 'string' type")
    return nil
  end

  local content_node = value_node:named_child(0)
  log.debug("content_node type: %s", tostring(content_node and content_node:type() or "nil"))
  if not content_node or content_node:type() ~= "string_content" then
    log.debug("content_node is nil or not 'string_content' type")
    return nil
  end

  local text = vim.treesitter.get_node_text(content_node, buffer)
  log.debug("Extracted text: '%s'", tostring(text))
  if not text or text == "" then
    log.debug("text is nil or empty")
    return nil
  end
  -- Normalize if needed (e.g., dot to slash)
  local normalized = text:gsub("%.", "/")
  log.debug("Normalized text: '%s'", tostring(normalized))
  return normalized
end

--- Gets target information if the cursor is on a Laravel Blade component reference.
--- @param context BladeNavContext Context created by context.lua
--- @return BladeNavTargetInfo|nil { type = "component", name = "component.name" } or nil
function M.get_target(context)
  local ts_node = context.ts_node
  if not ts_node then
    log.debug("No TS node available in context.")
    return nil
  end

  local node_type = ts_node:type()
  local func_name = nil
  local args_node = nil
  local component_tag_name = nil -- For <x-...> tags

  -- Ascend the tree to find the relevant structure
  local current_node = ts_node
  while current_node do
    local current_type = current_node:type()
    log.debug("Ascending - Current node type: %s (Filetype: %s)", current_type, context.filetype)

    if current_type == "function_call_expression" then
      local name_node = current_node:child(0)
      if name_node then
        func_name = vim.treesitter.get_node_text(name_node, context.buffer)
        args_node = current_node:child(1) -- Arguments node
        log.debug(
          "Found function_call_expression. Func: %s Args type: %s",
          func_name,
          args_node and args_node:type() or "nil"
        )
      end
      break -- Stop after finding the function call
    elseif current_type == "element" and context.filetype == "blade" then
      -- Handle <x-component ...> tags
      -- element -> (open_tag | self_closing_tag) -> element_name -> tag_name
      local open_tag_node = current_node:child(0)          -- Could be open_tag or self_closing_tag
      if open_tag_node then
        local element_name_node = open_tag_node:child(0)   -- element_name
        if element_name_node and element_name_node:type() == "element_name" then
          local tag_name_node = element_name_node:child(0) -- tag_name
          if tag_name_node and tag_name_node:type() == "tag_name" then
            local full_tag_text = vim.treesitter.get_node_text(tag_name_node, context.buffer)
            log.debug("Found tag_name node text: '%s'", full_tag_text)
            -- Check if it starts with x- (case-insensitive)
            if full_tag_text and full_tag_text:lower():match("^x%-") then
              -- Extract the part after 'x-'
              component_tag_name = full_tag_text:match("^x%-(.+)")
              if component_tag_name then
                log.debug("Matched component tag: '%s'", component_tag_name)
                -- Normalize tag name (e.g., kebab-case to directory structure if needed)
                -- For now, just return the name. Resolution logic might need to convert kebab-case.
                return { type = "component", name = component_tag_name, tag_based = true } -- Flag to indicate source
              end
            end
          end
        end
      end
      break -- Stop after processing the element
    elseif current_type == "directive" and context.filetype == "blade" then
      -- Handle Blade directives like @component('name')
      local dir_name_node = current_node:child(0) -- First child is usually the directive name (e.g., @component)
      if dir_name_node then
        func_name = vim.treesitter.get_node_text(dir_name_node, context.buffer)
        -- The argument is typically within the parameter node following the directive name
        -- directive -> @component -> parameter -> program -> ... -> string_content
        local param_node = dir_name_node:next_sibling() -- Get the node after @component
        log.debug("Directive param_node type: %s", tostring(param_node and param_node:type() or "nil"))
        if param_node and param_node:type() == "bracket_start" then
          param_node = param_node:next_sibling() -- Move to parameter node
          log.debug("Moved to parameter node type: %s", tostring(param_node and param_node:type() or "nil"))
        end
        if param_node and param_node:type() == "parameter" then
          -- The arguments are inside the parameter's program
          args_node = param_node -- Pass the parameter node for extraction logic if needed
          -- For simple cases like @component('name'), the string_content is directly inside.
        end
      end
      log.debug("Found directive. Func: %s Args type: %s", func_name, args_node and args_node:type() or "nil")
      break -- Stop after processing the directive
    end
    current_node = current_node:parent()
  end

  -- Handle function call or directive matches
  if func_name and args_node then
    for _, func_info in ipairs(COMPONENT_PATTERNS) do
      if
          func_name == func_info.pattern -- Exact match for directives/functions
          or func_name:match(func_info.pattern)
      then                             -- Pattern match for functions
        log.debug("Function/directive pattern matched: %s", func_info.pattern)
        local component_name = extract_component_name_from_args(args_node, func_info.arg_index, context.buffer)
        if component_name then
          log.debug("Extracted component name: %s", component_name)
          return { type = "component", name = component_name, tag_based = false }
        end
      end
    end
    log.debug("Function '%s' not matched by COMPONENT_PATTERNS.", func_name)
  end

  -- If we reached here, it wasn't a recognized component pattern under the cursor
  log.debug("No matching component pattern found.")
  return nil
end

return M
