--- @module 'blink.cmp"
--- @class blink.cmp.Source
local source = {}

local utils = require("blade-nav.utils")

-- `opts` table comes from `sources.providers.your_provider.opts`
-- You may also accept a second argument `config`, to get the full
-- `sources.providers.your_provider` table
function source.new(opts)
  vim.validate("blade-nav.opts.close_tag_on_complete", opts.close_tag_on_complete, "boolean", true)

  local self = setmetatable({}, { __index = source })
  self.opts = opts
  return self
end

-- (Optional) Enable the source in specific contexts only
function source:enabled()
  return vim.bo.filetype == "blade" or vim.bo.filetype == "php"
end

-- (Optional) Non-alphanumeric characters that trigger the source
function source:get_trigger_characters()
  return { ".", "<", "-" }
end

function source:get_completions(ctx, callback)
  -- ctx (context) contains the current keyword, cursor position, bufnr, etc.

  -- You should never filter items based on the keyword, since blink.cmp will
  -- do this for you

  -- blink.cmp does not have a "offset" so manually get the word until previous space

  local cursor = {
    row = ctx.cursor[1],
    col = ctx.cursor[2],
  }

  local line_until_cursor = string.sub(ctx.line, 1, cursor.col)
  local space_pos = line_until_cursor:sub(1, cursor.col - 1):match(".*()%s")

  local full_input = string.sub(line_until_cursor, space_pos):gsub("%s+", "")
  local input = utils.extract_inner_function(full_input)
  local _, names = utils.get_view_names(input, source.opts.close_tag_on_complete)
  local items = {}

  --- @type lsp.CompletionItem[]
  for _, name in ipairs(names) do
    --- @type lsp.CompletionItem
    local item = {
      -- Label of the item in the UI
      label = name.label,

      -- (Optional) Item kind, where `Function` and `Method` will receive
      -- auto brackets automatically
      kind = require("blink.cmp.types").CompletionItemKind.File,

      -- (Optional) Text to fuzzy match against
      filterText = name.filterText,

      -- (Optional) Text to use for sorting. You may use a layout like
      -- "aaaa', 'aaab', 'aaac', ... to control the order of the items
      -- sortText = "baz",

      -- Text to be inserted when accepting the item using ONE of:
      --
      -- (Recommended) Control the exact range of text that will be replaced
      textEdit = {
        newText = name.newText,
        range = {
          -- 0-indexed line and character
          start = {
            line = cursor.row - 1,
            character = cursor.col - 1 - #input,
          },
          ["end"] = {
            line = cursor.row - 1,
            character = cursor.col - 1,
          },
        },
      },
      -- Or get blink.cmp to guess the range to replace for you. Use this only
      -- when inserting *exclusively* alphanumeric characters. Any symbols will
      -- trigger complicated guessing logic in blink.cmp that may not give the
      -- result you're expecting
      -- Note that blink.cmp will use `label` when omitting both `insertText` and `textEdit`
      -- insertText = "foo",

      -- May be Snippet or PlainText
      insertTextFormat = vim.lsp.protocol.InsertTextFormat.PlainText,

      -- There are some other fields you may want to explore which are blink.cmp
      -- specific, such as `score_offset` (blink.cmp.CompletionItem)
    }
    table.insert(items, item)
  end

  vim.notify(vim.inspect(items))

  -- The callback _MUST_ be called at least once. The first time it's called,
  -- blink.cmp will show the results in the completion menu. Subsequent calls
  -- will append the results to the menu to support streaming results.
  callback({
    items = items,
    -- Whether blink.cmp should request items when deleting characters
    -- from the keyword (i.e. "foo|" -> "fo|")
    -- Note that any non-alphanumeric characters will always request
    -- new items (excluding `-` and `_`)
    is_incomplete_backward = false,
    -- Whether blink.cmp should request items when adding characters
    -- to the keyword (i.e. "fo|" -> "foo|")
    -- Note that any non-alphanumeric characters will always request
    -- new items (excluding `-` and `_`)
    is_incomplete_forward = false,
  })

  -- (Optional) Return a function which cancels the request
  -- If you have long running requests, it's essential you support cancellation
  return function() end
end

-- (Optional) Before accepting the item or showing documentation, blink.cmp will call this function
-- so you may avoid calculating expensive fields (i.e. documentation) for only when they're actually needed
function source:resolve(item, callback)
  item = vim.deepcopy(item)

  -- Shown in the documentation window (<C-space> when menu open by default)
  item.documentation = {
    kind = "markdown",
    value = "# Foo\n\nBar",
  }

  -- Additional edits to make to the document, such as for auto-imports
  item.additionalTextEdits = {
    {
      newText = "markdown-foo",
      range = {
        start = { line = 0, character = 0 },
        ["end"] = { line = 0, character = 0 },
      },
    },
  }

  callback(item)
end

-- Called immediately after applying the item's textEdit/insertText
function source:execute(ctx, item, callback, default_implementation)
  -- By default, your source must handle the execution of the item itself,
  -- but you may use the default implementation at any time
  default_implementation()

  -- The callback _MUST_ be called once
  callback()
end

return source
