.PHONY: test debug-test simple-test

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

# Version more simple without treesitter
simple-test:
	@nvim --headless --noplugin -u NONE \
		-c "set rtp+=." \
		-c "set rtp+=~/.local/share/nvim/site/pack/vendor/start/plenary.nvim" \
		-c "runtime plugin/plenary.vim" \
		-c "PlenaryBustedDirectory lua/tests/" \
		-c "qa!"
