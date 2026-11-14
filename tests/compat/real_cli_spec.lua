local mise = require("tests.support.mise")
local process = require("tests.support.process")
local fs = require("tests.support.fs")
local unistd = require("posix.unistd")
local stdlib = require("posix.stdlib")
local CLI = os.getenv("SKILLS_CLI_TEST_BIN")
-- A skill shipped in the CLI's own immutable v1.7.6 source tree.
local REVISION = "7a5e920bead4b1039a6d6df5d7e1163b7b09423a"
local SOURCE_URL = "https://github.com/vercel-labs/skills.git"

describe("real skills CLI compatibility", function()
  if not CLI or CLI == "" then
    pending("set SKILLS_CLI_TEST_BIN to skills >= 1.7.6 to enable network tests")
    return
  end

  local function fixture()
    assert.equals("/", CLI:sub(1, 1), "SKILLS_CLI_TEST_BIN must be absolute")
    assert.is_truthy(process.which(CLI), "SKILLS_CLI_TEST_BIN is not executable")
    local binary = assert(stdlib.realpath(CLI))
    local f = mise.new(finally)
    assert(os.remove(f.bin .. "/skills"))
    assert(unistd.link(binary, f.bin .. "/skills", true))
    -- Real Git resolves refs here; drop the offline ls-remote shim.
    assert(os.remove(f.bin .. "/git"))
    f.env.MISE_OFFLINE = nil
    f.target = f.home .. "/.agents/skills/find-skills"
    return f
  end

  local function declare(f, version)
    fs.write(
      f.project .. "/mise.toml",
      "[bootstrap.packages]\n" .. '"skills:vercel-labs/skills/find-skills" = "' .. version .. '"\n'
    )
  end

  local function action(f, ...)
    return f.run({ ... }, nil, 240)
  end

  it("supports pinned install, status, upgrade, dry runs and prune", function()
    local f = fixture()
    declare(f, REVISION)
    action(f, "apply", "--dry-run")
    assert.is_false(fs.exists(f.target))
    action(f, "apply")
    assert.equals(REVISION, f.status().skills.packages[1].installed_version)
    assert.is_true(fs.exists(f.target .. "/SKILL.md"))
    local before = fs.read(f.lock)
    action(f, "apply")
    action(f, "upgrade")
    assert.equals(before, fs.read(f.lock))
    f.declare()
    action(f, "prune", "--manager", "skills", "--dry-run")
    assert.is_true(fs.exists(f.target))
    action(f, "prune", "--manager", "skills")
    assert.is_false(fs.exists(f.target))
  end)

  it("installs a release tag and refuses to move it", function()
    local f = fixture()
    declare(f, "v1.7.6")
    action(f, "apply")
    assert.equals("v1.7.6", f.status().skills.packages[1].installed_version)
    assert.is_true(fs.exists(f.target .. "/SKILL.md"))
    local before = fs.read(f.lock)
    action(f, "apply")
    action(f, "upgrade")
    assert.equals(before, fs.read(f.lock))
  end)

  it("resolves latest through real Git and upgrades to the tracked HEAD", function()
    local f = fixture()
    declare(f, "latest")
    action(f, "apply")
    local installed = f.status().skills.packages[1].installed_version
    assert.equals(40, #installed, installed)
    assert.is_truthy(installed:match("^[0-9a-f]+$"), installed)
    assert.is_true(fs.exists(f.target .. "/SKILL.md"))
    local head = process.run({ "git", "ls-remote", SOURCE_URL, "HEAD" }, { timeout = 120 }).stdout
    assert.equals(head:match("^[0-9a-f]+"), installed)
  end)
end)
