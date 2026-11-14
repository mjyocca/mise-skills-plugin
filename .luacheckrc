std = "lua51"
globals = { "PLUGIN" }
self = false -- mise requires colon-method hooks, even when self is unused.
max_line_length = 100
exclude_files = { ".mise/**" }

files["tests/**"] = {
  std = "lua51+busted",
}
