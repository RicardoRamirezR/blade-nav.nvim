-- scripts/gen_help.lua
-- Generate doc/blade-nav.txt from README.md

local infile = "README.md"
local outfile = "doc/blade-nav.txt"

--- read readme
local readme_lines = {}
for l in io.lines(infile) do
  l = l:gsub("^#%s+", ""):gsub("^##%s+", "")
  table.insert(readme_lines, l)
end

local generated = {}
table.insert(generated, "*blade-nav.txt*\tBladeNav.nvim Documentation\n")
for _, l in ipairs(readme_lines) do
  table.insert(generated, l)
end
table.insert(generated, "\nvim:tw=78:ts=8:ft=help:norl:\n")

--- join
local generated_text = table.concat(generated, "\n")

--- read existing file if present
local existing_text = nil
do
  local f = io.open(outfile, "r")
  if f then
    existing_text = f:read("*a")
    f:close()
  end
end

--- compare
if existing_text ~= generated_text then
  local f = io.open(outfile, "w")
  f:write(generated_text)
  f:close()
  io.stderr:write("doc/blade-nav.txt was outdated. Regenerated.\n")
  os.exit(1)
else
  print("doc/blade-nav.txt is up to date.")
end
