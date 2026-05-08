-- lua/blade-nav/inertia-path-extractor.lua
-- Utility functions for path processing

local utils = {
  normalize_path = function(path)
    if not path then
      return nil
    end
    path = path:gsub("^%.?/?", "")
    path = path:gsub("/?$", "")
    path = path:gsub("//+", "/")
    return path
  end,

  validate_path = function(path)
    if not path then
      return false
    end
    if path:match('[<>:"|?*]') then
      return false
    end
    if #path > 255 then
      return false
    end
    return true
  end,

  log = function(msg, level)
    level = level or "info"
    if vim and vim.notify then
      vim.notify(msg, vim.log.levels[level:upper()])
    else
      print(string.format("[%s] %s", level:upper(), msg))
    end
  end,
}

-- Custom error handling
local ErrorTypes = {
  NO_MATCH = "NO_MATCH",
  INVALID_PATH = "INVALID_PATH",
  PARSE_ERROR = "PARSE_ERROR",
}

local function throw_error(error_type, details)
  return {
    type = error_type,
    message = details,
    timestamp = os.time(),
  }
end

-- Function to extract pages path from different Inertia resolver patterns
local function extract_pages_path(file_content, opts)
  opts = opts or {}
  local debug = opts.debug or false
  local strict = opts.strict or false

  if not file_content or type(file_content) ~= "string" then
    return nil, throw_error(ErrorTypes.PARSE_ERROR, "Invalid file content")
  end

  local patterns = {
    {
      pattern = "resolvePageComponent%s*%(%s*[`'\"](.-)/%${name}%.vue[`'\"]",
      process = function(match)
        return utils.normalize_path(match)
      end,
      name = "Laravel 11 resolvePageComponent",
    },
    {
      pattern = "pages%s*=%s*import%.meta%.glob%([`'\"](.-)/[*][*]/[*]%.vue[`'\"]%s*,%s*{%s*eager:%s*true%s*}",
      process = function(match)
        return utils.normalize_path(match)
      end,
      name = "Vite eager glob",
    },
    {
      pattern = "pages%s*=%s*import%.meta%.glob%([`'\"](.-)/[*][*]/[*]%.vue[`'\"]",
      process = function(match)
        return utils.normalize_path(match)
      end,
      name = "Vite standard glob",
    },
    {
      pattern = "[`'\"]%./?(.-?)/%${name}%.vue[`'\"]",
      process = function(match)
        return utils.normalize_path(match)
      end,
      name = "Direct string path",
    },
    {
      pattern = "require%([`'\"]%./(.-)/[^`'\"]+[`'\"]%)",
      process = function(match)
        return utils.normalize_path(match)
      end,
      name = "Webpack require",
    },
    {
      pattern = "import%(([`'\"]%.?/.-)/[^`'\"]+[`'\"]%)",
      process = function(match)
        return utils.normalize_path(match)
      end,
      name = "Dynamic import",
    },
    {
      pattern = "definePages%(%s*[`'\"](.-)/%${name}%.vue[`'\"]",
      process = function(match)
        return utils.normalize_path(match)
      end,
      name = "definePages",
    },
  }

  for _, pattern_config in ipairs(patterns) do
    local success, result = pcall(function()
      local match = file_content:match(pattern_config.pattern)
      if match then
        if debug then
          utils.log(string.format("Match found with pattern: %s", pattern_config.name), "debug")
        end
        return pattern_config.process(match)
      end
      return nil
    end)

    if not success then
      if debug then
        utils.log(string.format("Error processing pattern %s: %s", pattern_config.name, result), "error")
      end
      if strict then
        return nil, throw_error(ErrorTypes.PARSE_ERROR, result)
      end
    elseif result then
      if not utils.validate_path(result) then
        return nil, throw_error(ErrorTypes.INVALID_PATH, "Invalid characters or unsafe path detected")
      end
      return result
    end
  end

  return nil, throw_error(ErrorTypes.NO_MATCH, "No matching pattern found")
end

-- Enhanced test function with more cases and error handling
local function test_extract_pages_path()
  local test_cases = {
    {
      name = "Laravel 11 style",
      content = [[
        resolve: (name) => resolvePageComponent(`./Pages/${name}.vue`, import.meta.glob('./Pages/**/*.vue')),
      ]],
      expected = "Pages",
    },
    {
      name = "Vite eager style",
      content = [[
        const pages = import.meta.glob('./Pages/**/*.vue', { eager: true })
        return pages[`./Pages/${name}.vue`]
      ]],
      expected = "Pages",
    },
    {
      name = "Vite standard style",
      content = [[
        const pages = import.meta.glob('./Pages/**/*.vue')
        return pages[`./Pages/${name}.vue`]
      ]],
      expected = "Pages",
    },
    {
      name = "Simple string style",
      content = [[
        return `./Pages/${name}.vue`
      ]],
      expected = "Pages",
    },
    {
      name = "Webpack style",
      content = [[
        resolve: name => require(`./Pages/${name}`),
      ]],
      expected = "Pages",
    },
    {
      name = "Dynamic import style",
      content = [[
        resolve: name => import(`./Pages/${name}.vue`)
      ]],
      expected = "Pages",
    },
    {
      name = "definePages style",
      content = [[
        resolve: name => definePages(`./Pages/${name}.vue`)
      ]],
      expected = "Pages",
    },
    {
      name = "Invalid path (../)",
      content = [[
        resolve: name => definePages(`../Pages/${name}.vue`)
      ]],
      expected_error = ErrorTypes.INVALID_PATH,
    },
    {
      name = "Invalid characters",
      content = [[
        resolve: name => definePages(`./Pages<invalid>/${name}.vue`)
      ]],
      expected_error = ErrorTypes.INVALID_PATH,
    },
  }

  local results = {
    passed = 0,
    failed = 0,
    total = #test_cases,
  }

  for _, test_case in ipairs(test_cases) do
    local result, error = extract_pages_path(test_case.content, { debug = true })

    local passed = false
    if test_case.expected_error then
      passed = error and error.type == test_case.expected_error
    else
      passed = result == test_case.expected
    end

    if passed then
      results.passed = results.passed + 1
      utils.log(string.format("✓ %s: passed", test_case.name), "info")
    else
      results.failed = results.failed + 1
      utils.log(
        string.format(
          "✗ %s: failed (expected: %s, got: %s)",
          test_case.name,
          test_case.expected or test_case.expected_error,
          result or (error and error.type) or "nil"
        ),
        "error"
      )
    end
  end

  utils.log(
    string.format("\nTest Results: %d/%d passed (%d failed)", results.passed, results.total, results.failed),
    "info"
  )
end

return {
  extract_pages_path = extract_pages_path,
  test_extract_pages_path = test_extract_pages_path,
  ErrorTypes = ErrorTypes,
}
