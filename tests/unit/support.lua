-- Minimal unit adapters; integration tests exercise the actual mise runtime.
local json = require("dkjson")
local stub = require("luassert.stub")
local M = {}

function M.fixture()
  for _, name in ipairs({ "package", "state", "cli", "actions" }) do
    package.loaded["lib." .. name] = nil
  end
  local f = {
    nodes = {},
    commands = {},
    env = { HOME = "/fixture/home", XDG_STATE_HOME = "/fixture/state" },
  }
  local getenv = stub(os, "getenv", function(key)
    return f.env[key]
  end)
  f.restore = function()
    getenv:revert()
  end
  function f.dir(path)
    if path == "" then
      return
    end
    f.nodes[path] = { is_dir = true }
    f.dir(path:match("^(.*)/") or "")
  end
  function f.write(path, content)
    f.dir(path:match("^(.*)/"))
    f.nodes[path] = { is_file = true, content = content }
  end
  function f.lock(skills)
    skills = setmetatable(skills or {}, { __jsontype = "object" })
    f.write("/fixture/state/skills/.skill-lock.json", json.encode({ version = 3, skills = skills }))
  end
  function f.install(spec)
    f.lock({ [spec.skill] = { sourceUrl = spec.url, sourceType = "github", ref = spec.pin } })
    f.write("/fixture/home/.agents/skills/" .. spec.skill .. "/SKILL.md", "fixture")
  end
  package.loaded.file = {
    stat = function(path)
      return f.nodes[path]
    end,
    read = function(path)
      return assert(f.nodes[path]).content
    end,
    list = function(path)
      local entries = {}
      for key in pairs(f.nodes) do
        if key:match("^(.*)/") == path then
          entries[#entries + 1] = key
        end
      end
      table.sort(entries)
      return entries
    end,
  }
  package.loaded.json = {
    encode = json.encode,
    decode = function(text)
      local value, position, err = json.decode(text, 1, json.null)
      if err or text:sub(position):match("%S") then
        error(err or "trailing JSON content")
      end
      return value
    end,
  }
  package.loaded.cmd = {
    exec = function(command, options)
      f.commands[#f.commands + 1] = { command = command, options = options }
      if f.exec then
        return f.exec(command, options)
      end
      return "1.7.6\n"
    end,
  }
  package.loaded.log = { info = function() end }
  f.spec =
    require("lib.package").parse({ name = "example/skills/demo", version = string.rep("a", 40) })
  return f
end

return M
