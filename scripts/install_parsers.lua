-- scripts/install_parsers.lua
-- Add nvim-treesitter to runtime path
local ts_path = vim.fn.stdpath("data") .. "/site/pack/vendor/start/nvim-treesitter"
vim.opt.runtimepath:prepend(ts_path)

-- Load nvim-treesitter
vim.cmd("runtime! plugin/nvim-treesitter.lua")

-- Install parsers by directly calling the command handler
local parsers = { "blade", "php", "html", "vue" }

print("Installing treesitter parsers...")

-- Get the install commands module
local ok, ts_install = pcall(require, "nvim-treesitter.install")
if not ok then
  print("ERROR: Could not load nvim-treesitter.install")
  vim.cmd("cquit 1")
  return
end

-- Get the commands
local ok_cmd, commands = pcall(require, "nvim-treesitter.commands")
if ok_cmd and commands then
  -- Use the command API if available
  for _, parser in ipairs(parsers) do
    print("\n=== Installing: " .. parser .. " ===")
    local success, err = pcall(function()
      commands.commands.TSInstall["run!"](parser)
    end)

    if not success then
      print("ERROR: " .. tostring(err))
    end
  end
else
  -- Fallback: use shell command with nvim-treesitter's CLI
  print("Using fallback installation method...")
  for _, parser in ipairs(parsers) do
    print("\n=== Installing: " .. parser .. " ===")
    local result =
      vim.fn.system(string.format("nvim --headless -c 'set rtp+=%s' -c 'TSInstallSync! %s' -c 'qa'", ts_path, parser))
    print(result)
  end
end

-- Wait for compilation
vim.wait(5000)

-- Final verification
print("\n=== Verifying installed parsers ===")
local parser_dir = vim.fn.stdpath("data") .. "/site/parser"
local all_ok = true

for _, parser in ipairs(parsers) do
  local parser_file = parser_dir .. "/" .. parser .. ".so"
  local exists = vim.fn.filereadable(parser_file) == 1
  local status = exists and "✓" or "✗"
  print(status .. " " .. parser)
  if not exists then
    all_ok = false
  end
end

if not all_ok then
  print("\nWARNING: Some parsers may not have installed correctly")
  print("Checking parser directory:")
  os.execute("ls -la " .. parser_dir)
  vim.cmd("cquit 1")
else
  print("\n✓ All parsers installed successfully!")
  vim.cmd("qa!")
end
