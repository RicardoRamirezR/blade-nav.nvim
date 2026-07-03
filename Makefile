.PHONY: test debug-test

# Version with proper exit code handling
test:
	@echo "Running tests..."
	@nvim --headless -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory lua/tests/ {minimal_init = 'tests/minimal_init.lua'}"

# For debug - shows more information
debug-test:
	@echo "Debug mode..."
	@nvim --headless -u tests/minimal_init.lua \
		-c "lua print('Plenary loaded:', pcall(require, 'plenary'))" \
		-c "lua print('Test dir exists:', vim.fn.isdirectory('lua/tests'))" \
		-c "PlenaryBustedDirectory lua/tests/ {minimal_init = 'tests/minimal_init.lua'}" \
		-c "qa!"
