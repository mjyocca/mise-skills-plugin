-- Shared utilities for the skills plugin hooks.
-- Loaded by each hook via require("lib.name").

local file = require("file")
local json = require("json")

local M = {}

-- Resolve the skills CLI binary path from the mise data directory and declared version.
-- Mise need not export MISE_DATA_DIR; mirror its Linux/macOS directory defaults.
-- Mise shims do not work from hooks (S1); invoke the binary directly.
function M.resolve_cli(data_dir, version)
  if not data_dir or data_dir == "" then
    local xdg = os.getenv("XDG_DATA_HOME")
    if xdg and xdg ~= "" then
      data_dir = xdg .. "/mise"
    else
      local home = os.getenv("HOME")
      if not home or home == "" then
        error("HOME is not set; cannot resolve the default mise data directory")
      end
      data_dir = home .. "/.local/share/mise"
    end
  end
  if not version or version == "" then
    error("CLI version is not declared")
  end
  local bin = data_dir .. "/installs/npm-skills/" .. version .. "/node_modules/.bin/skills"
  local stat = file.stat(bin)
  if not stat then
    error("Skills CLI binary not found at " .. bin .. "; run mise bootstrap first")
  end
  return bin
end

-- Resolve the global lock file path.
-- $XDG_STATE_HOME/skills/.skill-lock.json when XDG_STATE_HOME is set,
-- otherwise $HOME/.agents/.skill-lock.json.
function M.lock_path()
  local xdg = os.getenv("XDG_STATE_HOME")
  local home = os.getenv("HOME")
  if not home or home == "" then
    error("HOME is not set")
  end
  if xdg and xdg ~= "" then
    return xdg .. "/skills/.skill-lock.json"
  end
  return home .. "/.agents/.skill-lock.json"
end

-- Read and parse the global lock file, failing closed on any anomaly.
-- Returns the skills table (may be empty) or nil if the lock does not exist.
function M.read_lock()
  local path = M.lock_path()
  -- Reject symlinked locks and ancestors.
  if file.stat(path) and file.stat(path).is_symlink then
    error("Global lock is a symlink; preserve it and review: " .. path)
  end
  -- Check ancestors for symlinks.
  local dir = path:match("^(.*)/")
  while dir and dir ~= "" and dir ~= "/" do
    local s = file.stat(dir)
    if s and s.is_symlink then
      error("Lock ancestor is a symlink; preserve it and review: " .. dir)
    end
    dir = dir:match("^(.*)/")
  end
  if not file.exists(path) then
    return nil
  end
  local content = file.read(path)
  if not content then
    error("Cannot read global lock: " .. path)
  end
  local ok, data = pcall(json.decode, content)
  if not ok then
    error("Global lock is not valid JSON: " .. path)
  end
  if type(data) ~= "table" or data.version ~= 3 or type(data.skills) ~= "table" then
    error("Unsupported global skills lock version; preserve it and review the CLI version")
  end
  return data.skills
end

-- Parse a package name into owner, repo, and skill-id.
-- Package names arrive as "owner/repo/skill-id" (the "skills:" manager prefix is stripped by mise).
function M.parse_package_name(name)
  local owner, repo, skill_id = name:match("^([^/]+)/([^/]+)/(.+)$")
  if not owner then
    error("Invalid package name (expected owner/repo/skill-id): " .. tostring(name))
  end
  return owner, repo, skill_id
end

-- Build the GitHub HTTPS .git URL from owner/repo.
-- Initially restricted to GitHub owner/repo shorthand.
function M.source_url(owner, repo)
  return "https://github.com/" .. owner .. "/" .. repo .. ".git"
end

-- Get the target directory for a skill.
function M.target_dir()
  local home = os.getenv("HOME")
  if not home or home == "" then
    error("HOME is not set")
  end
  return home .. "/.agents/skills"
end

return M
