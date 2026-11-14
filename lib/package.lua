-- Pure package/identity contract. No filesystem or command access.
local M = {}

---@class PackageRequest
---@field name string owner/repo/skill-id, without the mise manager prefix
---@field version string|nil Commit SHA, Git tag/branch ref name, or omitted/"latest"

---@class SkillSpec
---@field name string
---@field skill string Canonical CLI lock key and directory basename
---@field source string GitHub owner/repo
---@field url string Canonical HTTPS clone URL
---@field pin string Effective ref: a SHA, a ref name, or "latest" before resolution
---@field kind string "sha", "ref", or "latest"
---@field declared string|nil Original declaration, set when it differs from pin

M.LATEST = "latest"

-- Only a 40-character lowercase SHA-1 hex counts as a commit pin. The SHA-256
-- object format (64 hex) is not a Git default and is intentionally unsupported;
-- this matches the skills CLI's own ref detection (/^[0-9a-f]{40}$/i).
function M.is_pin(value)
  return type(value) == "string" and #value == 40 and value:match("^[0-9a-f]+$") ~= nil
end

function M.is_skill(value)
  return type(value) == "string"
    and value:match("^[a-z0-9][a-z0-9._%-]*$") ~= nil
    and value:match("[a-z0-9_]$") ~= nil
end

-- A conservative subset of git-check-ref-format. The value is embedded in a URL
-- fragment and reaches `git clone --branch`, so reject flag-like, URL-hostile,
-- and ambiguous names. `@` is excluded because the CLI's fragment parser splits
-- ref@skill-filter on it, and leading `-` could travel as a command flag.
function M.is_ref(value)
  if type(value) ~= "string" or value == "" or #value > 255 then
    return false
  end
  if value:match("[^A-Za-z0-9._/+%-]") then
    return false
  end
  if value:match("^[-.]") or value:match("[./]$") then
    return false
  end
  if value:match("%.%.") or value:match("//") then
    return false
  end
  for component in value:gmatch("[^/]+") do
    if component:match("^[.]") or component:match("%.lock$") then
      return false
    end
  end
  return true
end

-- Classify a declared version: "sha", "latest", "ref", or nil when unsupported.
-- mise parses the "latest" config value to an absent version, so an omitted
-- version is the canonical form of "latest"; the literal string is accepted
-- for direct hook callers.
function M.classify(version)
  if version == nil or version == M.LATEST then
    return "latest"
  end
  if M.is_pin(version) then
    return "sha"
  end
  if type(version) ~= "string" then
    return nil
  end
  -- Hex strings of SHA-like length are commit typos, never ref names; only an
  -- exact 40-character lowercase SHA (handled above) is a valid commit pin.
  if #version >= 32 and version:match("^%x+$") then
    return nil
  end
  if M.is_ref(version) then
    return "ref"
  end
  return nil
end

local function version_error(name, version)
  if type(version) == "string" and #version >= 32 and version:match("^%x+$") then
    return "Expected a full 40-character lowercase commit SHA for " .. name
  end
  return "Invalid version for "
    .. name
    .. ": "
    .. tostring(version)
    .. ' (expected a full 40-character lowercase commit SHA, a Git tag or branch ref, or "latest")'
end

---@param request PackageRequest
---@return SkillSpec
function M.parse(request)
  local name = request.name
  local owner, repo, skill
  if type(name) == "string" then
    owner, repo, skill = name:match("^([^/]+)/([^/]+)/([^/]+)$")
    if not owner then
      -- A fourth or later segment means the declaration carried a repository
      -- path (the skills CLI's "add owner/repo/<path>" shorthand) instead of a
      -- canonical skill name. Surface the intended form for a clearer fix.
      local _, _, path_skill = name:match("^([^/]+)/([^/]+)/(.+)$")
      if path_skill and path_skill:find("/") then
        error(
          'Invalid package name "'
            .. name
            .. '": "'
            .. path_skill
            .. '" is a repository path; use the canonical skill name instead.'
        )
      end
    end
  end
  if
    not owner
    or #owner > 39
    or not owner:match("^[A-Za-z0-9][A-Za-z0-9%-]*$")
    or not owner:match("[A-Za-z0-9]$")
    or not repo:match("^[A-Za-z0-9_][A-Za-z0-9_.%-]*$")
    or repo:match("%.git$")
    or not M.is_skill(skill)
  then
    error("Invalid package name (expected owner/repo/canonical-skill-id): " .. tostring(name))
  end
  local kind = M.classify(request.version)
  if not kind then
    error(version_error(name, request.version))
  end
  local source = owner .. "/" .. repo
  return {
    name = name,
    skill = skill,
    source = source,
    url = "https://github.com/" .. source .. ".git",
    pin = request.version or M.LATEST,
    kind = kind,
  }
end

-- Copy a spec with a mutable "latest" declaration replaced by its resolved SHA.
---@param spec SkillSpec
---@param pin string Full 40-character lowercase commit SHA
---@return SkillSpec
function M.resolved(spec, pin)
  if spec.kind ~= "latest" then
    error("Only a 'latest' spec can be resolved: " .. spec.name)
  end
  if not M.is_pin(pin) then
    error("Resolved latest is not a full lowercase commit SHA for " .. spec.name)
  end
  return {
    name = spec.name,
    skill = spec.skill,
    source = spec.source,
    url = spec.url,
    pin = pin,
    kind = "sha",
    declared = spec.pin,
  }
end

---@param requests PackageRequest[]
---@return SkillSpec[]
function M.parse_batch(requests)
  local specs, identities = {}, {}
  for _, request in ipairs(requests) do
    local spec = M.parse(request)
    if identities[spec.skill] then
      error(
        "Conflicting skill identity "
          .. spec.skill
          .. ": "
          .. identities[spec.skill]
          .. " and "
          .. spec.name
      )
    end
    identities[spec.skill] = spec.name
    specs[#specs + 1] = spec
  end
  return specs
end

-- Preserve request order while sharing one fetch for each source/ref pair.
function M.group(specs)
  local groups, by_key = {}, {}
  for _, spec in ipairs(specs) do
    local key = spec.url .. "#" .. spec.pin
    if not by_key[key] then
      by_key[key] = { source = spec.source, url = spec.url, pin = spec.pin, specs = {} }
      groups[#groups + 1] = by_key[key]
    end
    table.insert(by_key[key].specs, spec)
  end
  return groups
end

return M
