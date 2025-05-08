--- @diagnostic disable: duplicate-doc-field

--- @module 'blink.cmp"
--- @class blink.cmp.Source
--- @field opts BladeNavBlinkSourceOpts
local source = {}

local utils = require("blade-nav.utils")

--- @class BladeNavBlinkSourceOpts
--- @field close_tag_on_complete boolean

--- @param opts BladeNavBlinkSourceOpts
function source.new(opts)
  vim.validate("blade-nav.opts.close_tag_on_complete", opts.close_tag_on_complete, "boolean", true)

  opts.close_tag_on_complete = not (opts.close_tag_on_complete ~= false)

  vim.api.nvim_set_hl(0, "BlinkCmpKindBladeNav", { fg = "#f53003" })

  local self = setmetatable({}, { __index = source })
  self.opts = opts
  return self
end

function source:enabled()
  return utils.in_table(vim.bo.filetype, { "blade", "php" })
end

-- (Optional) Non-alphanumeric characters that trigger the source
function source:get_trigger_characters()
  return { ".", "<", "-" }
end

function source:get_completions(ctx, callback)
  -- ctx (context) contains the current keyword, cursor position, bufnr, etc.

  -- You should never filter items based on the keyword, since blink.cmp will
  -- do this for you

  -- Just for a cleaner syntax
  local cursor = {
    row = ctx.cursor[1],
    col = ctx.cursor[2],
  }

  -- blink.cmp does not have an "offset" at the provided context so we'll
  -- manually get the word until previous space
  -- This is to compensate the "offset" from nvim-cmp
  local line_until_cursor = string.sub(ctx.line, 1, cursor.col)

  -- The "or 1" is in case the line does not contain a white space, eg:
  -- |    require('|  <-- works fine
  -- |@extends('|  <-- would give an error
  -- |
  local space_pos = line_until_cursor:sub(1, cursor.col - 1):match(".*()%s") or 1

  local full_input = string.sub(line_until_cursor, space_pos):gsub("%s+", "")
  local input = utils.extract_inner_function(full_input)
  local _, names = utils.get_view_names(input, self.opts.close_tag_on_complete)
  local items = {}

  --- @type lsp.CompletionItem[]
  for _, name in ipairs(names) do
    --- @type lsp.CompletionItem
    local item = {
      label = name.label,
      kind = require("blink.cmp.types").CompletionItemKind.Text,
      filterText = name.filterText,
      textEdit = {
        newText = name.newText,
        range = {
          -- 0-indexed line and character
          start = {
            line = cursor.row - 1,
            character = cursor.col - #input,
          },
          ["end"] = {
            line = cursor.row - 1,
            character = cursor.col,
          },
        },
      },
      insertTextFormat = vim.lsp.protocol.InsertTextFormat.PlainText,
    }
    table.insert(items, item)
  end

  callback({
    items = items,
    is_incomplete_backward = false,
    is_incomplete_forward = false,
  })

  return function() end
end

return source
