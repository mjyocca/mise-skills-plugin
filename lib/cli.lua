-- The only command boundary. Shell code is fixed; dynamic values travel via env.
local cmd = require("cmd")
local json = require("json")
local state = require("lib.state")

-- JSON reports display names ("Codex"), whereas command flags take IDs ("codex").
local M = { VERSION = "1.7.6", AGENT = "codex", AGENT_LABEL = "Codex" }
local TIMEOUT = 120

local function exec(command, env)
  env = env or {}
  env.DISABLE_TELEMETRY = "1"
  env.GIT_TERMINAL_PROMPT = "0"
  local ok, output = pcall(cmd.exec, command, { env = env, timeout = TIMEOUT })
  if not ok then
    error("Skills CLI invocation failed: " .. tostring(output))
  end
  return output
end

function M.check_version()
  local output = exec("skills --version")
  local version = output:match("^%s*(.-)%s*$")
  if version ~= M.VERSION then
    error("Unsupported skills CLI version " .. version .. "; expected " .. M.VERSION .. " on PATH")
  end
end

---@class AddResult
---@field name string
---@field status string
---@field source string
---@field ref string
---@field path string
---@field scope string
---@field agents string[]
---@field mode string

function M.validate_add(output, group)
  local ok, results = pcall(json.decode, output)
  if not ok or not output:match("^%s*%[") or type(results) ~= "table" then
    error("Invalid skills add JSON; expected a result array")
  end
  local expected, seen = {}, {}
  for _, spec in ipairs(group.specs) do
    expected[spec.skill] = spec
  end
  local count = 0
  for index, result in pairs(results) do
    if type(index) ~= "number" or index < 1 or index % 1 ~= 0 or type(result) ~= "table" then
      error("Invalid skills add JSON result array")
    end
    local spec = type(result.name) == "string" and expected[result.name]
    if not spec or seen[result.name] then
      error("Unexpected or duplicate skills add result: " .. tostring(result.name))
    end
    if
      result.status ~= "installed"
      or result.source ~= spec.source
      or result.ref ~= spec.pin
      or result.path ~= state.target(spec)
      or result.scope ~= "global"
      or result.mode ~= "copy"
      or type(result.agents) ~= "table"
      or #result.agents ~= 1
      or result.agents[1] ~= M.AGENT_LABEL
    then
      error(
        "Skills add result did not confirm requested installation of "
          .. spec.skill
          .. ": "
          .. tostring(result.error or result.reason or result.status)
      )
    end
    seen[result.name] = true
    count = count + 1
  end
  if count ~= #group.specs then
    error("Missing skills add results; expected " .. #group.specs .. ", got " .. count)
  end
end

function M.add(group)
  local env = { SKILLS_SOURCE = group.url .. "#" .. group.pin, SKILLS_AGENT = M.AGENT }
  local arguments = {}
  for i, spec in ipairs(group.specs) do
    local key = "SKILLS_NAME_" .. i
    env[key] = spec.skill
    -- Only the generated integer enters shell code, never a package value.
    arguments[#arguments + 1] = '"$' .. key .. '"'
  end
  local output = exec(
    'skills add "$SKILLS_SOURCE" --skill '
      .. table.concat(arguments, " ")
      .. ' --global --agent "$SKILLS_AGENT" --copy --yes --json',
    env
  )
  M.validate_add(output, group)
end

function M.remove(spec)
  exec('skills remove "$SKILLS_NAME" --global --agent "$SKILLS_AGENT" --yes', {
    SKILLS_NAME = spec.skill,
    SKILLS_AGENT = M.AGENT,
  })
end

return M
