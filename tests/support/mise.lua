local lfs = require("lfs")
local assert = require("luassert")
local json = require("dkjson")
local stat = require("posix.sys.stat")
local fs = require("tests.support.fs")
local process = require("tests.support.process")
local M = { PIN = string.rep("a", 40), SOURCE = "https://github.com/example/skills.git" }
local ROOT = lfs.currentdir()
local MISE = assert(process.which("mise"), "mise is required for integration tests")
local LUA = assert(process.which("lua"), "Lua is required for the fake CLI")

function M.decode(text)
  local value, position, err = json.decode(text, 1, json.null)
  assert(not err and not text:sub(position):match("%S"), err or "Trailing JSON content")
  return value
end

local function quote(value)
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

-- Register cleanup before setup so a partial setup failure cannot leak a home.
function M.new(cleanup)
  assert.equals("function", type(cleanup), "Register fixture cleanup before setup")
  local f = { root = process.tempdir() }
  cleanup(function()
    fs.remove(f.root, f.root)
  end)
  f.home = f.root .. "/home $(touch injected)"
  f.project = f.root .. "/project"
  f.bin = f.root .. "/bin with spaces"
  f.target = f.home .. "/.agents/skills/demo"
  f.lock = f.root .. "/state/skills/.skill-lock.json"
  fs.mkdir(f.home)
  fs.mkdir(f.project)
  fs.mkdir(f.bin)
  f.env = {
    PATH = f.bin .. ":" .. os.getenv("PATH"),
    HOME = f.home,
    XDG_CONFIG_HOME = f.root .. "/config",
    XDG_DATA_HOME = f.root .. "/data",
    XDG_STATE_HOME = f.root .. "/state",
    XDG_CACHE_HOME = f.root .. "/cache",
    MISE_CONFIG_DIR = f.root .. "/config/mise",
    MISE_DATA_DIR = f.root .. "/data/mise",
    MISE_STATE_DIR = f.root .. "/state/mise",
    MISE_CACHE_DIR = f.root .. "/cache/mise",
    MISE_TRUSTED_CONFIG_PATHS = f.project,
    MISE_YES = "1",
    MISE_OFFLINE = "1",
  }
  local plugin = f.env.MISE_DATA_DIR .. "/plugins/skills"
  for _, name in ipairs({ "metadata.lua", "version.lua", "mise.plugin.toml", "hooks", "lib" }) do
    fs.copy(ROOT .. "/" .. name, plugin .. "/" .. name)
  end
  local setup = string.format(
    "package.path=%q;package.cpath=%q",
    ROOT .. "/?.lua;" .. package.path,
    package.cpath
  )
  fs.write(
    f.bin .. "/skills",
    "#!/bin/sh\nexec "
      .. quote(LUA)
      .. " -e "
      .. quote(setup)
      .. " "
      .. quote(ROOT .. "/tests/fixtures/skills.lua")
      .. ' "$@"\n'
  )
  assert(stat.chmod(f.bin .. "/skills", 493)) -- 0755

  function f.declare(...)
    local lines = { "[bootstrap.packages]\n" }
    for _, skill in ipairs({ ... }) do
      lines[#lines + 1] = '"skills:example/skills/' .. skill .. '" = "' .. M.PIN .. '"\n'
    end
    fs.write(f.project .. "/mise.toml", table.concat(lines))
  end

  function f.record(changes)
    local entry = { sourceUrl = M.SOURCE, sourceType = "github", ref = M.PIN }
    for key, value in pairs(changes or {}) do
      entry[key] = value
    end
    fs.write(f.lock, json.encode({ version = 3, skills = { demo = entry } }))
  end

  function f.install_files()
    fs.write(f.target .. "/SKILL.md", "fixture\n")
  end

  function f.run(args, expected_error, timeout)
    local argv = { MISE, "bootstrap", "packages" }
    for _, value in ipairs(args) do
      argv[#argv + 1] = value
    end
    local result = process.run(argv, { cwd = f.project, env = f.env, timeout = timeout })
    assert.is_false(result.timed_out, "mise timed out: " .. result.stderr)
    if expected_error then
      assert.is_not.equal(0, result.code, result.stderr)
      assert.is_truthy(result.stderr:find(expected_error, 1, true), result.stderr)
    else
      assert.equals(0, result.code, result.stderr)
    end
    return result
  end

  function f.status(expected_error)
    local result = f.run({ "status", "--json" }, expected_error)
    if not expected_error then
      return M.decode(result.stdout)
    end
  end

  function f.action(...)
    return f.run({ ... })
  end

  function f.calls()
    local calls, path = {}, f.home .. "/calls.jsonl"
    if fs.exists(path) then
      for line in fs.read(path):gmatch("[^\n]+") do
        calls[#calls + 1] = M.decode(line)
      end
    end
    return calls
  end

  f.declare("demo")
  return f
end

return M
