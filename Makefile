.PHONY: test debug-test lint docs

# Version with proper exit code handling
# `-u` loads minimal_init here so :PlenaryBustedDirectory exists; the option forwards the same init to each spawned test instance. Both are required.
test:
	@echo "Running tests..."
	@nvim --headless -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory lua/tests/ {minimal_init = 'tests/minimal_init.lua'}"

# Format check + static analysis
lint:
	@echo "Running stylua --check..."
	@stylua --check lua ftplugin scripts tests
	@echo "Running luacheck..."
	@luacheck lua ftplugin scripts tests

# Regenerate doc/blade-nav.txt from scripts/gen_help.lua
docs:
	@nvim --headless -l scripts/gen_help.lua

# For debug - shows more information
debug-test:
	@echo "Debug mode..."
	@nvim --headless -u tests/minimal_init.lua \
		-c "lua print('Plenary loaded:', pcall(require, 'plenary'))" \
		-c "lua print('Test dir exists:', vim.fn.isdirectory('lua/tests'))" \
		-c "PlenaryBustedDirectory lua/tests/ {minimal_init = 'tests/minimal_init.lua'}" \
		-c "qa!"
