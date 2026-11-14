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

  for _, version in ipairs({
    "latest",
    "main",
    string.rep("A", 40),
    string.rep("a", 39),
    "$(touch injected)",
  }) do
    it("rejects unsupported revision " .. version, function()
      assert.has_error(function()
        contract.parse({ name = "owner/repo/demo", version = version })
      end)
    end)
  end

  it("rejects an omitted pin", function()
    assert.has_error(function()
      contract.parse({ name = "owner/repo/demo" })
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
    })
    local groups = contract.group(specs)
    assert.equals(3, #groups)
    assert.same({ specs[1], specs[3] }, groups[1].specs)
    assert.same({ specs[2] }, groups[2].specs)
    assert.same({ specs[4] }, groups[3].specs)
  end)
end)
