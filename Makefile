.PHONY: test debug-test lint

# Version with proper exit code handling
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

# For debug - shows more information
debug-test:
	@echo "Debug mode..."
	@nvim --headless -u tests/minimal_init.lua \
		-c "lua print('Plenary loaded:', pcall(require, 'plenary'))" \
		-c "lua print('Test dir exists:', vim.fn.isdirectory('lua/tests'))" \
		-c "PlenaryBustedDirectory lua/tests/ {minimal_init = 'tests/minimal_init.lua'}" \
		-c "qa!"
