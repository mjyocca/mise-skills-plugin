local mise = require("tests.support.mise")
local process = require("tests.support.process")
local fs = require("tests.support.fs")
local unistd = require("posix.unistd")
local stdlib = require("posix.stdlib")
local CLI = os.getenv("SKILLS_CLI_TEST_BIN")
-- A skill shipped in the CLI's own immutable v1.7.6 source tree.
local REVISION = "7a5e920bead4b1039a6d6df5d7e1163b7b09423a"

describe("real skills CLI compatibility", function()
  if not CLI or CLI == "" then
    pending("set SKILLS_CLI_TEST_BIN to skills >= 1.7.6 to enable network tests")
    return
  end

  it("supports pinned install, status, upgrade, dry runs and prune", function()
    assert.equals("/", CLI:sub(1, 1), "SKILLS_CLI_TEST_BIN must be absolute")
    assert.is_truthy(process.which(CLI), "SKILLS_CLI_TEST_BIN is not executable")
    local binary = assert(stdlib.realpath(CLI))
    local f = mise.new(finally)
    assert(os.remove(f.bin .. "/skills"))
    assert(unistd.link(binary, f.bin .. "/skills", true))
    f.env.MISE_OFFLINE = nil
    f.target = f.home .. "/.agents/skills/find-skills"
    fs.write(
      f.project .. "/mise.toml",
      "[bootstrap.packages]\n" .. '"skills:vercel-labs/skills/find-skills" = "' .. REVISION .. '"\n'
    )
    local function action(...)
      f.run({ ... }, nil, 240)
    end
    action("apply", "--dry-run")
    assert.is_false(fs.exists(f.target))
    action("apply")
    assert.equals(REVISION, f.status().skills.packages[1].installed_version)
    assert.is_true(fs.exists(f.target .. "/SKILL.md"))
    local before = fs.read(f.lock)
    action("apply")
    action("upgrade")
    assert.equals(before, fs.read(f.lock))
    f.declare()
    action("prune", "--manager", "skills", "--dry-run")
    assert.is_true(fs.exists(f.target))
    action("prune", "--manager", "skills")
    assert.is_false(fs.exists(f.target))
  end)
end)
