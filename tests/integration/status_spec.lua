local mise = require("tests.support.mise")
local fs = require("tests.support.fs")
local unistd = require("posix.unistd")
local json = require("dkjson")

describe("package status in the actual mise runtime", function()
  local f, cleanup
  before_each(function()
    f = mise.new(function(fn)
      cleanup = fn
    end)
  end)
  after_each(function()
    if cleanup then
      cleanup()
      cleanup = nil
    end
  end)

  it("reports missing without a lock", function()
    assert.equals("missing", f.status().skills.packages[1].state)
  end)

  it("reports installed without modifying the lock", function()
    f.record()
    f.install_files()
    local before = fs.read(f.lock)
    local package = f.status().skills.packages[1]
    assert.equals("installed", package.state)
    assert.equals(mise.PIN, package.installed_version)
    assert.equals(before, fs.read(f.lock))
  end)

  it("reports a missing lock entry", function()
    f.record()
    f.declare("other")
    assert.equals("missing", f.status().skills.packages[1].state)
  end)

  it("reports missing files", function()
    f.record()
    assert.equals("missing", f.status().skills.packages[1].state)
  end)

  it("reports a missing entrypoint", function()
    f.record()
    fs.mkdir(f.target)
    assert.equals("missing", f.status().skills.packages[1].state)
  end)

  it("reports the installed mismatched pin", function()
    f.record({ ref = string.rep("b", 40) })
    f.install_files()
    assert.equals(string.rep("b", 40), f.status().skills.packages[1].installed_version)
  end)

  it("handles mixed batches", function()
    f.record()
    f.install_files()
    f.declare("absent", "demo", "other")
    local states = {}
    for _, package in ipairs(f.status().skills.packages) do
      states[package.package:match("([^/]+)$")] = package.state
    end
    assert.same({ absent = "missing", demo = "installed", other = "missing" }, states)
  end)

  it("rejects a foreign source", function()
    f.record({ sourceUrl = "https://github.com/foreign/skills.git" })
    f.install_files()
    f.status("Different source in global lock")
  end)

  it("rejects untracked files without a lock", function()
    f.install_files()
    f.status("Untracked global content")
  end)

  it("rejects untracked files without an entry", function()
    f.record()
    f.install_files()
    assert(os.rename(f.target, f.home .. "/.agents/skills/other"))
    f.declare("other")
    f.status("Untracked global content")
  end)

  it("rejects a symlinked target", function()
    f.record()
    fs.mkdir(f.home .. "/.agents/skills")
    assert(unistd.link(f.project, f.target, true))
    f.status("Target is a symlink")
  end)

  it("rejects symlinked content", function()
    f.record()
    f.install_files()
    assert(unistd.link(f.project, f.target .. "/linked", true))
    f.status("Target contains a symlink")
  end)

  it("rejects invalid lock JSON", function()
    f.record()
    fs.write(f.lock, "not json")
    f.status("Global lock is not valid JSON")
  end)

  it("rejects hidden nested symlinks", function()
    f.record()
    f.install_files()
    fs.mkdir(f.target .. "/.hidden/nested")
    assert(unistd.link(f.project, f.target .. "/.hidden/nested/link", true))
    f.status("Target contains a symlink")
  end)

  it("rejects symlinked target parents", function()
    f.record()
    fs.mkdir(f.home .. "/.agents")
    assert(unistd.link(f.project, f.home .. "/.agents/skills", true))
    f.status("Target ancestor is a symlink")
  end)

  it("rejects a directory entrypoint", function()
    f.record()
    fs.mkdir(f.target .. "/SKILL.md")
    f.status("Entrypoint is not a regular file")
  end)

  it("rejects a malformed entry", function()
    f.record({ ref = 123 })
    f.status("Invalid global lock entry")
  end)

  it("rejects an array instead of a lock map", function()
    f.record()
    fs.write(f.lock, '{"version":3,"skills":[]}')
    f.status("Unsupported global skills lock version or shape")
  end)

  it("supports empty configuration without creating a lock", function()
    f.declare()
    f.status()
    assert.is_false(fs.exists(f.lock))
  end)

  it("rejects colliding skill names", function()
    fs.write(
      f.project .. "/mise.toml",
      "[bootstrap.packages]\n"
        .. '"skills:example/skills/demo" = "'
        .. mise.PIN
        .. '"\n'
        .. '"skills:other/skills/demo" = "'
        .. mise.PIN
        .. '"\n'
    )
    f.status("Conflicting skill identity")
  end)

  it("rejects colliding lock aliases", function()
    f.record()
    local data = mise.decode(fs.read(f.lock))
    data.skills.Demo = { sourceType = "local" }
    fs.write(f.lock, json.encode(data))
    f.status("Conflicting skill identity in global lock")
  end)

  for _, skill in ipairs({ "../escape", "*", "--all", "MixedCase", "nested/skill" }) do
    it("rejects unsafe package name " .. skill, function()
      f.declare(skill)
      f.status("Invalid package name")
    end)
  end

  it("rejects an invalid version selector", function()
    f.declare_version("demo", "v1..2")
    f.status("Invalid version for")
    assert.same({}, f.git_calls())
  end)

  it("rejects a SHA-shaped typo", function()
    f.declare_version("demo", string.rep("a", 39))
    f.status("Expected a full 40-character lowercase commit SHA")
  end)

  it("reports a latest-declared skill from the lock without resolving", function()
    f.declare_version("demo", "latest")
    f.record({ ref = mise.HEAD })
    f.install_files()
    local package = f.status().skills.packages[1]
    assert.equals("installed", package.state)
    assert.equals(mise.HEAD, package.installed_version)
    assert.same({}, f.git_calls())
  end)

  it("reports a missing latest declaration without network access", function()
    f.declare_version("demo", "latest")
    assert.equals("missing", f.status().skills.packages[1].state)
    assert.same({}, f.git_calls())
  end)

  it("reports a tag-declared skill from the lock", function()
    f.declare_version("demo", "v1.2.3")
    f.record({ ref = "v1.2.3" })
    f.install_files()
    local package = f.status().skills.packages[1]
    assert.equals("installed", package.state)
    assert.equals("v1.2.3", package.installed_version)
  end)
end)
