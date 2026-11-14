-- Read-only adapter for skills 1.7.6's global v3 lock and canonical files.
local file = require("file")
local json = require("json")

local M = {}
local NULL = json.decode("null")

---@class SkillLockEntry
---@field sourceUrl string
---@field sourceType string
---@field ref string

local function absolute(value, label)
  if
    not value
    or value:sub(1, 1) ~= "/"
    or value:match("/%.[%.]?/")
    or value:match("/%.[%.]?$")
  then
    error(label .. " must be an absolute path without dot segments")
  end
  return value:gsub("/+$", "")
end

function M.target_dir()
  return absolute(os.getenv("HOME"), "HOME") .. "/.agents/skills"
end

function M.target(spec)
  return M.target_dir() .. "/" .. spec.skill
end

function M.lock_path()
  local xdg = os.getenv("XDG_STATE_HOME")
  if xdg and xdg ~= "" then
    return absolute(xdg, "XDG_STATE_HOME") .. "/skills/.skill-lock.json"
  end
  return absolute(os.getenv("HOME"), "HOME") .. "/.agents/.skill-lock.json"
end

local function check_ancestors(path, label)
  local dir = path:match("^(.*)/")
  while dir and dir ~= "" do
    local stat = file.stat(dir)
    if stat and stat.is_symlink then
      error(label .. " ancestor is a symlink; preserve it and review: " .. dir)
    end
    if stat and not stat.is_dir then
      error(label .. " ancestor is not a directory: " .. dir)
    end
    dir = dir:match("^(.*)/")
  end
end

function M.read_lock()
  local path = M.lock_path()
  check_ancestors(path, "Lock")
  local stat = file.stat(path)
  if not stat then
    return nil
  end
  if stat.is_symlink then
    error("Global lock is a symlink; preserve it and review: " .. path)
  end
  if not stat.is_file then
    error("Global lock is not a regular file: " .. path)
  end
  local content = file.read(path)
  local ok, data = pcall(json.decode, content)
  if not ok then
    error("Global lock is not valid JSON: " .. path)
  end
  if
    not content:match("^%s*{")
    or type(data) ~= "table"
    or data.version ~= 3
    or type(data.skills) ~= "table"
    or data.skills == NULL
    or not json.encode(data.skills):match("^%s*{")
  then
    error("Unsupported global skills lock version or shape; preserve it and review the CLI version")
  end
  for key in pairs(data.skills) do
    if type(key) ~= "string" then
      error("Invalid global skills lock map; preserve it and review")
    end
  end
  return data.skills
end

-- Validate only the requested entry: unrelated skills can use other providers.
function M.entry(lock, spec)
  -- The CLI sanitizes lock keys when resolving removals. Do not let an alias
  -- select a different lock entry that shares our canonical directory.
  for key in pairs(lock or {}) do
    local disk_name = key:lower():gsub("[^a-z0-9._]+", "-"):gsub("^[.%-]+", ""):gsub("[.%-]+$", "")
    if key ~= spec.skill and disk_name == spec.skill then
      error("Conflicting skill identity in global lock: " .. key .. " aliases " .. spec.skill)
    end
  end
  local entry = lock and lock[spec.skill]
  if entry == nil then
    return nil
  end
  if
    type(entry) ~= "table"
    or type(entry.sourceUrl) ~= "string"
    or entry.sourceUrl == ""
    or type(entry.ref) ~= "string"
    or entry.ref == ""
    or entry.sourceType ~= "github"
  then
    error(
      "Invalid global lock entry for "
        .. spec.skill
        .. "; expected GitHub sourceUrl, sourceType and ref"
    )
  end
  if entry.sourceUrl ~= spec.url then
    error(
      "Different source in global lock for "
        .. spec.skill
        .. ": declared "
        .. spec.url
        .. ", installed "
        .. entry.sourceUrl
    )
  end
  return entry
end

local function check_tree(path)
  for _, child in ipairs(file.list(path)) do
    local stat = file.stat(child)
    if not stat then
      error("Target changed during inspection: " .. child)
    elseif stat.is_symlink then
      error("Target contains a symlink; preserve it and review: " .. child)
    elseif stat.is_dir then
      check_tree(child)
    elseif not stat.is_file then
      error("Target contains a non-regular file: " .. child)
    end
  end
end

-- Presence is not a content hash. Do not claim verification of file contents.
---@return SkillLockEntry|nil, boolean
function M.inspect(lock, spec)
  local path = M.target(spec)
  check_ancestors(path, "Target")
  local stat = file.stat(path)
  if stat then
    if stat.is_symlink then
      error("Target is a symlink; preserve it and review: " .. path)
    elseif not stat.is_dir then
      error("Target is not a directory: " .. path)
    end
    check_tree(path)
  end
  local entry = M.entry(lock, spec)
  if not entry then
    if stat then
      error("Untracked global content at " .. path .. "; not tracked in the global lock")
    end
    return nil, false
  end
  local entrypoint = file.stat(path .. "/SKILL.md")
  if entrypoint and not entrypoint.is_file then
    error("Entrypoint is not a regular file: " .. path .. "/SKILL.md")
  end
  return entry, stat ~= nil and entrypoint ~= nil
end

return M
