local mise = require("tests.support.mise")
local fs = require("tests.support.fs")
local json = require("dkjson")

describe("package actions in the actual mise runtime", function()
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

  local function installed()
    assert.equals(mise.PIN, f.status().skills.packages[1].installed_version)
  end

  it("applies missing skills then skips matching pins", function()
    f.action("apply")
    installed()
    assert.equals(1, #f.calls())
    assert.is_false(fs.exists(f.project .. "/injected"))
    f.action("apply")
    assert.equals(1, #f.calls())
  end)

  it("applies a changed pin", function()
    f.record({ ref = string.rep("b", 40) })
    f.install_files()
    f.action("apply")
    installed()
  end)

  it("uses XDG without MISE_DATA_DIR", function()
    f.env.MISE_DATA_DIR = nil
    f.action("apply")
    installed()
  end)

  it("uses HOME without data overrides", function()
    local original = f.env.MISE_DATA_DIR
    f.env.MISE_DATA_DIR = nil
    f.env.XDG_DATA_HOME = nil
    fs.mkdir(f.home .. "/.local/share")
    assert(os.rename(original, f.home .. "/.local/share/mise"))
    f.action("apply")
    installed()
  end)

  it("honors explicit MISE_DATA_DIR precedence", function()
    local override = f.root .. "/custom-mise-data"
    assert(os.rename(f.env.MISE_DATA_DIR, override))
    f.env.MISE_DATA_DIR = override
    f.action("apply")
    installed()
  end)

  it("restores a deleted directory with an existing lock", function()
    f.action("apply")
    fs.remove(f.target, f.root)
    assert.is_not_nil(mise.decode(fs.read(f.lock)).skills.demo)
    f.action("apply")
    assert.is_true(fs.exists(f.target .. "/SKILL.md"))
    assert.equals(2, #f.calls())
  end)

  it("upgrades a changed pin", function()
    f.record({ ref = string.rep("b", 40) })
    f.install_files()
    f.action("upgrade")
    installed()
  end)

  it("prunes a mise-installed fixture", function()
    f.action("apply")
    f.declare()
    f.action("prune", "--manager", "skills")
    assert.is_false(fs.exists(f.target))
    assert.is_nil(mise.decode(fs.read(f.lock)).skills.demo)
    local calls = f.calls()
    assert.equals("remove", calls[#calls][1])
  end)

  it("does not invoke the CLI during apply dry-run", function()
    f.action("apply", "--dry-run")
    assert.same({}, f.calls())
    assert.is_false(fs.exists(f.target))
    assert.is_false(fs.exists(f.lock))
  end)

  it("does not invoke the CLI during upgrade dry-run", function()
    f.record({ ref = string.rep("b", 40) })
    f.install_files()
    local before = fs.read(f.lock)
    f.action("upgrade", "--dry-run")
    assert.same({}, f.calls())
    assert.equals(before, fs.read(f.lock))
  end)

  it("does not upgrade a current pin", function()
    f.record()
    f.install_files()
    f.action("upgrade")
    assert.same({}, f.calls())
  end)

  it("reports action failure", function()
    f.env.SKILLS_TEST_FAIL = "1"
    f.run({ "apply" }, "fixture action failed")
  end)

  it("rejects incompatible CLI versions before mutation", function()
    f.env.SKILLS_TEST_VERSION = "1.7.5"
    f.run({ "apply" }, "Unsupported skills CLI version")
    assert.same({}, f.calls())
  end)

  for _, version in ipairs({ "1.7.6", "1.8.1", "1.10.0", "2.0.0" }) do
    it("accepts a compatible CLI at or above the minimum: " .. version, function()
      f.env.SKILLS_TEST_VERSION = version
      f.action("apply")
      installed()
      assert.equals(1, #f.calls())
    end)
  end

  local modes = {
    { "invalid", "Invalid skills add JSON" },
    { "missing", "Missing skills add results" },
    { "extra", "Unexpected or duplicate" },
    { "duplicate", "Unexpected or duplicate" },
  }
  for _, change in ipairs({
    { status = "skipped" },
    { source = "foreign/repo" },
    { ref = "main" },
    { scope = "project" },
    { mode = "symlink" },
    { agents = { "codex" } },
    { path = "/outside" },
  }) do
    modes[#modes + 1] = { json.encode(change), "Skills add result did not confirm" }
  end
  for _, mode in ipairs(modes) do
    it("validates JSON result: " .. mode[1], function()
      f.env.SKILLS_TEST_RESULT = mode[1]
      f.run({ "apply" }, mode[2])
    end)
  end

  it("rejects shell substitution in pins", function()
    fs.write(
      f.project .. "/mise.toml",
      '[bootstrap.packages]\n"skills:example/skills/demo" = "$(touch injected)"\n'
    )
    f.run({ "apply" }, "Invalid version for")
    assert.is_false(fs.exists(f.project .. "/injected"))
    assert.same({}, f.calls())
  end)

  it("batches requests for the same source", function()
    f.declare("demo", "other")
    f.action("apply")
    local calls = f.calls()
    assert.equals(1, #calls)
    local names = { calls[1][4], calls[1][5] }
    table.sort(names)
    assert.same({ "demo", "other" }, names)
  end)

  it("installs latest for an explicit unpinned selector", function()
    f.declare("demo", "other")
    f.action("apply", "skills:example/skills/demo")
    assert.equals(mise.HEAD, f.status().skills.packages[1].installed_version)
    local calls = f.calls()
    assert.equals(1, #calls)
    assert.equals(mise.SOURCE .. "#" .. mise.HEAD, calls[1][2])
    assert.is_false(fs.exists(f.home .. "/.agents/skills/other"))
  end)

  it("does not invoke remove during prune dry-run", function()
    f.action("apply")
    f.declare()
    local before = fs.read(f.lock)
    f.action("prune", "--manager", "skills", "--dry-run")
    assert.equals(1, #f.calls())
    assert.equals(before, fs.read(f.lock))
  end)

  it("does not force-delete shared content", function()
    f.action("apply")
    f.declare()
    f.env.SKILLS_TEST_RETAIN = "1"
    f.run({ "prune", "--manager", "skills" }, "CLI did not fully remove")
    assert.is_true(fs.exists(f.target))
  end)

  it("installs a declared tag and records it in the lock", function()
    f.declare_version("demo", "v1.2.3")
    f.action("apply")
    assert.equals("v1.2.3", f.status().skills.packages[1].installed_version)
    local calls = f.calls()
    assert.equals(1, #calls)
    assert.equals(mise.SOURCE .. "#v1.2.3", calls[1][2])
    assert.same({}, f.git_calls())
    f.action("apply")
    assert.equals(1, #f.calls())
  end)

  it("applies a changed tag", function()
    f.declare_version("demo", "v1.2.3")
    f.action("apply")
    f.declare_version("demo", "v1.2.4")
    f.action("apply")
    assert.equals(2, #f.calls())
    assert.equals("v1.2.4", f.status().skills.packages[1].installed_version)
  end)

  it("resolves latest to the remote HEAD and installs that SHA", function()
    f.declare_version("demo", "latest")
    f.action("apply")
    local git_calls = f.git_calls()
    assert.equals(1, #git_calls)
    assert.same({ "ls-remote", mise.SOURCE, "HEAD" }, git_calls[1])
    local calls = f.calls()
    assert.equals(1, #calls)
    assert.equals(mise.SOURCE .. "#" .. mise.HEAD, calls[1][2])
    assert.equals(mise.HEAD, f.status().skills.packages[1].installed_version)
    -- The status check above stayed offline: still exactly one resolution.
    assert.equals(1, #f.git_calls())
  end)

  it("treats an installed latest as satisfied for apply and refreshes via upgrade", function()
    f.declare_version("demo", "latest")
    f.action("apply")
    f.action("apply")
    assert.equals(1, #f.calls())
    -- upgrade re-queries: unchanged HEAD resolves without reinstalling.
    f.action("upgrade")
    assert.equals(1, #f.calls())
    assert.equals(2, #f.git_calls())
    f.env.SKILLS_TEST_HEAD = string.rep("d", 40)
    f.action("upgrade")
    assert.equals(2, #f.calls())
    assert.equals(string.rep("d", 40), f.status().skills.packages[1].installed_version)
  end)

  it("upgrades a stale latest", function()
    f.declare_version("demo", "latest")
    f.action("apply")
    f.env.SKILLS_TEST_HEAD = string.rep("d", 40)
    f.action("upgrade")
    assert.equals(2, #f.calls())
    assert.equals(string.rep("d", 40), f.status().skills.packages[1].installed_version)
  end)

  it("resolves latest during dry-run without installing", function()
    f.declare_version("demo", "latest")
    f.action("apply", "--dry-run")
    assert.same({}, f.calls())
    assert.equals(1, #f.git_calls())
    assert.is_false(fs.exists(f.target))
    assert.is_false(fs.exists(f.lock))
  end)

  it("reports resolution failures without invoking the CLI", function()
    f.declare_version("demo", "latest")
    f.env.SKILLS_TEST_GIT_FAIL = "1"
    f.run({ "apply" }, "Could not resolve latest")
    assert.same({}, f.calls())
    assert.is_false(fs.exists(f.target))
  end)

  it("prunes a latest-installed skill", function()
    f.declare_version("demo", "latest")
    f.action("apply")
    f.declare()
    f.action("prune", "--manager", "skills")
    assert.is_false(fs.exists(f.target))
    assert.is_nil(mise.decode(fs.read(f.lock)).skills.demo)
  end)

  it("batches latest skills from one source behind a single resolution", function()
    fs.write(
      f.project .. "/mise.toml",
      "[bootstrap.packages]\n"
        .. '"skills:example/skills/demo" = "latest"\n'
        .. '"skills:example/skills/other" = "latest"\n'
    )
    f.action("apply")
    assert.equals(1, #f.git_calls())
    local calls = f.calls()
    assert.equals(1, #calls)
    assert.equals(mise.SOURCE .. "#" .. mise.HEAD, calls[1][2])
  end)
end)
