-- lua/tests/test_textnode_php_spec.lua
-- Test suite for Laravel PHP function extraction
-- Tests 4 positions per line: col0, first_non_blank (^), last_non_blank ($), and random
--
local textnode = require("blade-nav.core.textnode")
local ts = vim.treesitter

local php_fixture = [[
<?php

Config::get('services.stripe.key');
Config::set('app.timezone', 'America/New_York');
config('app.debug');
function first()
{
    env('API_TOKEN');
    route('users.show', ['id' => 1]);
    to_route('profile.edit');
    view('welcome', ['name' => 'Laravel']);
    View::make('admin.dashboard', ['stats' => $data]);
    Inertia::render('Dashboard/Index', ['user' => auth()->user()]);
    inertia('Posts/Show', ['post' => $post]);
    markdown('# Hello World');
}


// Edge cases and variations
Config::get('database.connections.mysql.host');
config('cache.default', 'redis');
env('APP_ENV', 'production');

// Multiple on same line
config('app.name');
env('APP_KEY');
function second()
{
    // Nested function calls
    view('emails.welcome', ['url' => route('verify.email')]);

    // Static routes
    Route::view('/welcome', 'welcome');
    Route::view('/about', 'pages.about', ['title' => 'About Us']);
    Config::set('session.lifetime', 120);
    to_route('dashboard');
}
]]

-- col0_expected: true means the function starts at col0 (like Blade directives)
-- col0_expected: nil means line has no meaningful function to extract
local expected_map = {
  [1] = { fname = nil, first_arg = nil, col0_expected = nil },
  [2] = { fname = nil, first_arg = nil, col0_expected = nil },
  [3] = { fname = "Config::get", first_arg = "services.stripe.key", col0_expected = true },
  [4] = { fname = "Config::set", first_arg = "app.timezone", col0_expected = true },
  [5] = { fname = "config", first_arg = "app.debug", col0_expected = true },
  [6] = { fname = nil, first_arg = nil, col0_expected = nil },
  [7] = { fname = nil, first_arg = nil, col0_expected = nil },
  [8] = { fname = "env", first_arg = "API_TOKEN", col0_expected = nil },
  [9] = { fname = "route", first_arg = "users.show", col0_expected = nil },
  [10] = { fname = "to_route", first_arg = "profile.edit", col0_expected = nil },
  [11] = { fname = "view", first_arg = "welcome", col0_expected = nil },
  [12] = { fname = "View::make", first_arg = "admin.dashboard", col0_expected = nil },
  [13] = { fname = "Inertia::render", first_arg = "Dashboard/Index", col0_expected = nil },
  [14] = { fname = "inertia", first_arg = "Posts/Show", col0_expected = nil },
  [15] = { fname = "markdown", first_arg = "# Hello World", col0_expected = nil },
  [16] = { fname = nil, first_arg = nil, col0_expected = nil },
  [17] = { fname = nil, first_arg = nil, col0_expected = nil },
  [18] = { fname = nil, first_arg = nil, col0_expected = nil },
  [19] = { fname = nil, first_arg = nil, col0_expected = nil },
  [20] = { fname = "Config::get", first_arg = "database.connections.mysql.host", col0_expected = true },
  [21] = { fname = "config", first_arg = "cache.default", col0_expected = true },
  [22] = { fname = "env", first_arg = "APP_ENV", col0_expected = true },
  [23] = { fname = nil, first_arg = nil, col0_expected = nil },
  [24] = { fname = nil, first_arg = nil, col0_expected = nil },
  [25] = { fname = "config", first_arg = "app.name", col0_expected = true },
  [26] = { fname = "env", first_arg = "APP_KEY", col0_expected = true },
  [27] = { fname = nil, first_arg = nil, col0_expected = nil },
  [28] = { fname = nil, first_arg = nil, col0_expected = nil },
  [29] = { fname = nil, first_arg = nil, col0_expected = nil },
  [30] = { fname = "view", first_arg = "emails.welcome", col0_expected = nil },
  [31] = { fname = nil, first_arg = nil, col0_expected = nil },
  [32] = { fname = nil, first_arg = nil, col0_expected = nil },
  [33] = { fname = "Route::view", first_arg = "welcome", col0_expected = nil },
  [34] = { fname = "Route::view", first_arg = "pages.about", col0_expected = nil },
  [35] = { fname = "Config::set", first_arg = "session.lifetime", col0_expected = nil },
  [36] = { fname = "to_route", first_arg = "dashboard", col0_expected = nil },
  [37] = { fname = nil, first_arg = nil, col0_expected = nil },
}

local function prepare_buffer(ft, text)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(text, "\n"))
  vim.bo[bufnr].filetype = ft
  vim.api.nvim_buf_set_option(bufnr, "filetype", ft)
  vim.api.nvim_set_current_buf(bufnr)
  local ok, parser = pcall(ts.get_parser, bufnr, ft)
  if ok and parser then
    pcall(function()
      parser:parse()
    end)
  end
  return bufnr
end

local function last_non_blank_index(line)
  for i = #line, 1, -1 do
    local char = line:sub(i, i)
    if char:match("%S") then
      -- In PHP, statements end with ';', move one char before it
      if char == ";" and i > 1 then
        return i - 2 -- -1 for 0-based index, -1 more to skip the semicolon
      end
      return i - 1
    end
  end
  return 0
end

local function same(a, b)
  return vim.inspect(a) == vim.inspect(b)
end

describe("textnode PHP Laravel function extraction - full scan (4 positions)", function()
  local bufnr = prepare_buffer("php", php_fixture)

  for lnum, expected in pairs(expected_map) do
    it("validates " .. (expected.fname or "(empty)") .. " at line " .. lnum, function()
      local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ""

      local col0 = 0
      local first_non_blank = math.max(0, (line:find("%S") or 1) - 1)
      local last_index = last_non_blank_index(line)
      local rand_index
      if last_index - first_non_blank >= 2 then
        math.randomseed(lnum)
        rand_index = math.random(first_non_blank + 1, last_index - 1)
      else
        rand_index = first_non_blank
      end

      local positions = {
        { name = "col0", col = col0 },
        { name = "^", col = first_non_blank },
        { name = "$", col = last_index },
        { name = "rand", col = rand_index },
      }

      local col0_expected = nil
      if expected.col0_expected ~= nil then
        if expected.col0_expected == true then
          col0_expected = { fname = expected.fname, first_arg = expected.first_arg }
        else
          col0_expected = expected.col0_expected
        end
      end

      local function probe(row, col)
        vim.api.nvim_win_set_cursor(0, { row, col })
        local ok, parser = pcall(ts.get_parser, bufnr, vim.api.nvim_buf_get_option(bufnr, "filetype"))
        if ok and parser then
          pcall(function()
            parser:parse()
          end)
        end
        local full, fname, first_arg = textnode.get_text_node()
        return { full = full, fname = fname, first_arg = first_arg }
      end

      -- Test col0 position
      local res0 = probe(lnum, positions[1].col)
      if col0_expected == nil then
        assert.is_nil(
          res0.fname,
          string.format("line %d col0: expected nil fname but got %s", lnum, vim.inspect(res0.fname))
        )
        assert.is_nil(
          res0.first_arg,
          string.format("line %d col0: expected nil first_arg but got %s", lnum, vim.inspect(res0.first_arg))
        )
      else
        assert.is_true(
          same(res0.fname, col0_expected.fname),
          string.format(
            "line %d col0: fname mismatch (expected %s) got %s",
            lnum,
            vim.inspect(col0_expected.fname),
            vim.inspect(res0.fname)
          )
        )
        assert.is_true(
          same(res0.first_arg, col0_expected.first_arg),
          string.format(
            "line %d col0: first_arg mismatch (expected %s) got %s",
            lnum,
            vim.inspect(col0_expected.first_arg),
            vim.inspect(res0.first_arg)
          )
        )
      end

      -- Test remaining positions (^, $, rand)
      for i = 2, 4 do
        local pos = positions[i]
        local res = probe(lnum, pos.col)
        local ok_fname = same(res.fname, expected.fname)
        local ok_first = same(res.first_arg, expected.first_arg)
        if not (ok_fname and ok_first) then
          local msg = {
            string.format("Line %d failed at position %s (col=%d)", lnum, pos.name, pos.col),
            string.format(
              "  expected fname=%s first_arg=%s",
              vim.inspect(expected.fname),
              vim.inspect(expected.first_arg)
            ),
            string.format(
              "  got      fname=%s first_arg=%s full=%s",
              vim.inspect(res.fname),
              vim.inspect(res.first_arg),
              vim.inspect(res.full)
            ),
            string.format("  line text: %s", vim.inspect(line)),
            string.format("  positions: %s", vim.inspect(positions)),
          }
          pcall(function()
            textnode.debug_nodes_at_cursor()
          end)
          assert.is_true(false, table.concat(msg, "\n"))
        end
      end
    end)
  end

  pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
end)
