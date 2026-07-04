std = "luajit"

globals = {
  "vim",
}

files["lua/tests/*.lua"] = {
  read_globals = {
    "describe",
    "it",
    "before_each",
    "after_each",
    "assert",
    "stub",
    "pending",
  },
}

exclude_files = {
  "lua/fixtures/**",
}
