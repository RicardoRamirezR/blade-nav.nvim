-- lua/blade-nav/utils/init.lua
-- Main utils module that re-exports submodules

local M = {}

-- Re-export submodules for easier access
M.cache = require("blade-nav.utils.cache")
M.fs = require("blade-nav.utils.fs")
M.cmd = require("blade-nav.utils.cmd")
M.log = require("blade-nav.utils.log")
M.string = require("blade-nav.utils.string")
-- Add others as they are created (e.g., laravel)
-- M.laravel = require("blade-nav.utils.laravel")

-- Optionally re-export specific functions directly if frequently used
-- M.read_file = M.fs.read_file
-- M.execute_silent = M.cmd.execute_silent
-- M.in_table = function(tbl, value) ... end -- Implement or move to table.lua

return M
