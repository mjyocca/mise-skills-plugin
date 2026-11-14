-- Independent fake for transport tests, not proof of upstream compatibility.
local json = require("dkjson")
local fs = require("tests.support.fs")
local function decode(text)
  local value, _, err = json.decode(text)
  assert(not err, err)
  return value
end
local function object(value)
  return setmetatable(value or {}, { __jsontype = "object" })
end
local function array(value)
  return setmetatable(value or {}, { __jsontype = "array" })
end
local function expect_tail(start, expected)
  assert(#arg == start + #expected - 1, "Unexpected argument count")
  for i, value in ipairs(expected) do
    assert(arg[start + i - 1] == value, "Unexpected flag: " .. tostring(arg[start + i - 1]))
  end
end

if #arg == 1 and arg[1] == "--version" then
  print(os.getenv("SKILLS_TEST_VERSION") or "1.7.6")
  os.exit(0)
end

local home = assert(os.getenv("HOME"))
local arguments = array()
for i = 1, #arg do
  arguments[i] = arg[i]
end
fs.write(home .. "/calls.jsonl", json.encode(arguments) .. "\n", "ab")
assert(os.getenv("DISABLE_TELEMETRY") == "1")
if os.getenv("SKILLS_TEST_FAIL") then
  io.stderr:write("fixture action failed\n")
  os.exit(1)
end

local lock = assert(os.getenv("XDG_STATE_HOME")) .. "/skills/.skill-lock.json"
local data = fs.exists(lock) and decode(fs.read(lock)) or { version = 3, skills = object() }
local results = array()
if arg[1] == "add" then
  assert(os.getenv("GIT_TERMINAL_PROMPT") == "0")
  assert(arg[3] == "--skill")
  local last = 4
  while arg[last] and arg[last] ~= "--global" do
    last = last + 1
  end
  expect_tail(last, { "--global", "--agent", "codex", "--copy", "--yes", "--json" })
  local url, ref = arg[2]:match("^(.*)#([^#]+)$")
  assert(url and ref)
  for i = 4, last - 1 do
    local skill = arg[i]
    local target = home .. "/.agents/skills/" .. skill
    fs.write(target .. "/SKILL.md", "fixture\n")
    data.skills[skill] = { sourceUrl = url, ref = ref, sourceType = "github" }
    results[#results + 1] = {
      name = skill,
      status = "installed",
      source = url:gsub("^https://github.com/", ""):gsub("%.git$", ""),
      ref = ref,
      path = target,
      scope = "global",
      agents = { "Codex" },
      mode = "copy",
    }
  end
elseif arg[1] == "remove" then
  local skill = assert(arg[2])
  expect_tail(3, { "--global", "--agent", "codex", "--yes" })
  if not os.getenv("SKILLS_TEST_RETAIN") then
    fs.remove(home .. "/.agents/skills/" .. skill, home)
    data.skills[skill] = nil
  end
else
  error("Unexpected action: " .. tostring(arg[1]))
end

fs.write(lock, json.encode(data))
if arg[1] == "add" then
  local mode = os.getenv("SKILLS_TEST_RESULT")
  if mode == "invalid" then
    print("not json")
    os.exit(0)
  elseif mode == "missing" then
    results = array()
  elseif mode == "extra" then
    local extra = {}
    for key, value in pairs(results[1]) do
      extra[key] = value
    end
    extra.name = "unexpected"
    results[#results + 1] = extra
  elseif mode == "duplicate" then
    results[#results + 1] = results[1]
  elseif mode then
    for key, value in pairs(decode(mode)) do
      results[1][key] = value
    end
  end
  print(json.encode(results))
end
