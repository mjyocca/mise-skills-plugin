-- Read-only Git transport for "latest" resolution. Shell code is fixed; the
-- dynamic URL travels via env, matching the skills CLI boundary in lib/cli.lua.
local cmd = require("cmd")

local M = {}
local TIMEOUT = 60

-- Resolve a repository's default-branch tip (remote HEAD) to a commit SHA.
-- `git ls-remote <url> HEAD` prints exactly one "<sha>\tHEAD" line on success.
function M.resolve_head(url)
  local ok, output = pcall(cmd.exec, 'git ls-remote "$GIT_REMOTE_URL" HEAD', {
    env = { GIT_REMOTE_URL = url, GIT_TERMINAL_PROMPT = "0" },
    timeout = TIMEOUT,
  })
  if not ok then
    error("Could not resolve latest for " .. url .. ": " .. tostring(output))
  end
  local found
  for line in tostring(output or ""):gmatch("[^\n]+") do
    local sha, ref = line:match("^%s*(%S+)%s+(%S+)%s*$")
    if ref == "HEAD" then
      if found or not sha:match("^[0-9a-f]+$") or #sha ~= 40 then
        error("Unexpected git ls-remote output for " .. url)
      end
      found = sha
    end
  end
  if not found then
    error("Could not resolve latest for " .. url .. "; git ls-remote reported no HEAD")
  end
  return found
end

return M
