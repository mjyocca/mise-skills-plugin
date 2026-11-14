local contract = require("lib.package")
local pin = string.rep("a", 40)

describe("package contract", function()
  it("maps one identity to its source, CLI name and directory basename", function()
    local spec = contract.parse({ name = "example/skills/demo", version = pin })
    assert.same({
      name = "example/skills/demo",
      source = "example/skills",
      url = "https://github.com/example/skills.git",
      skill = "demo",
      pin = pin,
      kind = "sha",
    }, spec)
  end)

  for _, name in ipairs({
    "../repo/demo",
    "owner/../demo",
    "owner/repo/../escape",
    "owner/repo/*",
    "owner/repo/--all",
    "owner/repo/Demo",
    "owner/repo/.hidden",
    "owner/repo/demo-",
    "owner/repo/demo.",
    "owner/repo/$(touch injected)",
    "owner/repo.git/demo",
    "owner/repo/demo/extra",
  }) do
    it("rejects unsafe or noncanonical name " .. name, function()
      assert.has_error(function()
        contract.parse({ name = name, version = pin })
      end)
    end)
  end

  it("points a repository-path declaration at the canonical name", function()
    local ok, message = pcall(contract.parse, {
      name = "hashicorp/agent-skills/plugins/terraform/skills/terraform-style-guide",
      version = pin,
    })
    assert.is_false(ok)
    assert.truthy(tostring(message):find("is a repository path", 1, true))
    assert.truthy(tostring(message):find("canonical skill name", 1, true))
  end)

  it('accepts "latest" as a mutable selector', function()
    local spec = contract.parse({ name = "owner/repo/demo", version = "latest" })
    assert.equals("latest", spec.kind)
    assert.equals("latest", spec.pin)
  end)

  for _, version in ipairs({
    "v1.2.3",
    "release/2024.01",
    "v1.0.0+build",
    "main",
    "UPPER_Case-1.0",
    "abc1234",
  }) do
    it("accepts Git ref " .. version, function()
      local spec = contract.parse({ name = "owner/repo/demo", version = version })
      assert.equals("ref", spec.kind)
      assert.equals(version, spec.pin)
    end)
  end

  for _, version in ipairs({
    string.rep("A", 40),
    string.rep("a", 32),
    string.rep("a", 39),
    string.rep("a", 41),
    "$(touch injected)",
    "-v1.2.3",
    "v1..2",
    ".hidden",
    "ends.",
    "ends.lock",
    "a.lock/b",
    "has space",
    "has~tilde",
    "has^caret",
    "has:colon",
    "has?question",
    "has*star",
    "has[bracket",
    "back\\slash",
    "at@{brace",
    "v1@2",
    "lead//slash",
    "trail/",
    "semi;colon",
    "percent%20encoded",
    "@",
    "",
    true,
    string.rep("v", 256),
  }) do
    it("rejects unsupported revision " .. tostring(version), function()
      assert.has_error(function()
        contract.parse({ name = "owner/repo/demo", version = version })
      end)
    end)
  end

  it("reports SHA-shaped typos with the commit-specific message", function()
    local ok, message = pcall(contract.parse, {
      name = "owner/repo/demo",
      version = string.rep("A", 40),
    })
    assert.is_false(ok)
    assert.truthy(
      tostring(message):find("Expected a full 40-character lowercase commit SHA", 1, true)
    )
  end)

  it("reports other invalid versions with the selector contract", function()
    local ok, message = pcall(contract.parse, { name = "owner/repo/demo", version = "-v1" })
    assert.is_false(ok)
    assert.truthy(tostring(message):find("Invalid version for owner/repo/demo", 1, true))
  end)

  it("treats an omitted version as latest", function()
    local spec = contract.parse({ name = "owner/repo/demo" })
    assert.equals("latest", spec.kind)
    assert.equals("latest", spec.pin)
  end)

  it("resolves a mutable spec into a pinned copy", function()
    local spec = contract.parse({ name = "owner/repo/demo", version = "latest" })
    local resolved = contract.resolved(spec, pin)
    assert.same({
      name = "owner/repo/demo",
      source = "owner/repo",
      url = "https://github.com/owner/repo.git",
      skill = "demo",
      pin = pin,
      kind = "sha",
      declared = "latest",
    }, resolved)
    assert.equals("latest", spec.pin)
  end)

  it("rejects a malformed resolved pin", function()
    local spec = contract.parse({ name = "owner/repo/demo", version = "latest" })
    assert.has_error(function()
      contract.resolved(spec, "main")
    end)
  end)

  it("refuses to resolve a spec that is not latest", function()
    local spec = contract.parse({ name = "owner/repo/demo", version = pin })
    assert.has_error(function()
      contract.resolved(spec, pin)
    end)
  end)

  it("rejects collisions before returning a batch", function()
    assert.has_error(function()
      contract.parse_batch({
        { name = "one/repo/demo", version = pin },
        { name = "two/repo/demo", version = pin },
      })
    end)
  end)

  it("groups only identical source/ref pairs and preserves order", function()
    local specs = contract.parse_batch({
      { name = "one/repo/demo", version = pin },
      { name = "two/repo/other", version = pin },
      { name = "one/repo/third", version = pin },
      { name = "one/repo/fourth", version = string.rep("b", 40) },
      { name = "two/repo/fifth", version = "v1.2.3" },
    })
    local groups = contract.group(specs)
    assert.equals(4, #groups)
    assert.same({ specs[1], specs[3] }, groups[1].specs)
    assert.same({ specs[2] }, groups[2].specs)
    assert.same({ specs[4] }, groups[3].specs)
    assert.same({ specs[5] }, groups[4].specs)
  end)
end)
