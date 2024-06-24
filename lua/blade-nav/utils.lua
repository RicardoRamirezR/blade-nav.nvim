local M = {}

M.get_blade_files = function()
  local handle = io.popen('find resources/views -type f -name "*.blade.php" | sort')
  local result = handle:read("*a")
  handle:close()

  local files = {}
  for file in result:gmatch("[^\r\n]+") do
    local view_name = file:match("resources/views/(.*)%.blade%.php$")
    if view_name then
      view_name = view_name:gsub("/", ".")
      table.insert(files, view_name)
    end
  end

  return files
end

return M
