-- Pure package/identity contract. No filesystem or command access.
local M = {}

---@class PackageRequest
---@field name string owner/repo/skill-id, without the mise manager prefix
---@field version string Full lowercase Git commit SHA

---@class SkillSpec
---@field name string
---@field skill string Canonical CLI lock key and directory basename
---@field source string GitHub owner/repo
---@field url string Canonical HTTPS clone URL
---@field pin string

function M.is_pin(value)
  return type(value) == "string" and #value == 40 and value:match("^[0-9a-f]+$") ~= nil
end

function M.is_skill(value)
  return type(value) == "string"
    and value:match("^[a-z0-9][a-z0-9._%-]*$") ~= nil
    and value:match("[a-z0-9_]$") ~= nil
end

---@param request PackageRequest
---@return SkillSpec
function M.parse(request)
  local name = request.name
  local owner, repo, skill
  if type(name) == "string" then
    owner, repo, skill = name:match("^([^/]+)/([^/]+)/([^/]+)$")
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
  if not M.is_pin(request.version) then
    error("Expected a full 40-character lowercase commit SHA for " .. name)
  end
  local source = owner .. "/" .. repo
  return {
    name = name,
    skill = skill,
    source = source,
    url = "https://github.com/" .. source .. ".git",
    pin = request.version,
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
