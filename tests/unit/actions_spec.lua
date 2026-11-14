local support = require("tests.unit.support")

describe("lifecycle actions", function()
  local f, actions, calls, ctx, resolves
  local head = string.rep("c", 40)
  local second = "https://github.com/second/repo.git"
  before_each(function()
    f = support.fixture()
    calls = {}
    resolves = {}
    head = string.rep("c", 40)
    package.loaded["lib.git"] = {
      resolve_head = function(url)
        resolves[#resolves + 1] = url
        return head
      end,
    }
    package.loaded["lib.cli"] = {
      check_version = function()
        calls[#calls + 1] = "version"
      end,
      add = function(group)
        calls[#calls + 1] = group
        for _, spec in ipairs(group.specs) do
          f.install(spec)
        end
      end,
      remove = function(spec)
        calls[#calls + 1] = spec.skill
        f.nodes["/fixture/home/.agents/skills/" .. spec.skill .. "/SKILL.md"] = nil
        f.nodes["/fixture/home/.agents/skills/" .. spec.skill] = nil
        f.lock()
      end,
    }
    actions = require("lib.actions")
    ctx = { packages = { { name = f.spec.name, version = f.spec.pin } } }
  end)
  after_each(function()
    f.restore()
  end)

  it("dry-run never even probes the CLI", function()
    ctx.dry_run = true
    actions.install(ctx)
    assert.same({}, calls)
    assert.same({}, f.nodes)
  end)

  it("current pins are no-ops even with update", function()
    f.install(f.spec)
    ctx.update = true
    actions.install(ctx)
    assert.same({}, calls)
  end)

  it("operates on only the requested subset", function()
    actions.install(ctx)
    assert.equals("version", calls[1])
    assert.equals(1, #calls[2].specs)
    assert.equals("demo", calls[2].specs[1].skill)
  end)

  it("preflights the whole install batch before mutations", function()
    ctx.packages[2] = { name = "example/skills/*", version = f.spec.pin }
    assert.has_error(function()
      actions.install(ctx)
    end)
    assert.same({}, calls)
    assert.same({}, resolves)
  end)

  it("rejects false CLI success without matching postconditions", function()
    package.loaded["lib.cli"].add = function() end
    assert.has_error(function()
      actions.install(ctx)
    end)
  end)

  it("can remove an owned lock-only entry when mise supplies it", function()
    f.install(f.spec)
    f.nodes["/fixture/home/.agents/skills/demo/SKILL.md"] = nil
    f.nodes["/fixture/home/.agents/skills/demo"] = nil
    actions.remove(ctx)
    assert.same({ "version", "demo" }, calls)
  end)

  it("defensively honors dry-run on removal", function()
    f.install(f.spec)
    ctx.dry_run = true
    actions.remove(ctx)
    assert.same({}, calls)
  end)

  it("does not remove changed ownership", function()
    f.install(f.spec)
    ctx.packages[1].version = string.rep("b", 40)
    assert.has_error(function()
      actions.remove(ctx)
    end)
    assert.same({}, calls)
  end)

  it("does not force-delete retained content", function()
    f.install(f.spec)
    package.loaded["lib.cli"].remove = function() end
    assert.has_error(function()
      actions.remove(ctx)
    end)
    assert.is_not_nil(f.nodes["/fixture/home/.agents/skills/demo/SKILL.md"])
  end)

  it("passes Git refs through without resolving them", function()
    ctx.packages = {
      { name = "example/skills/demo", version = "v1.2.3" },
      { name = "example/skills/other", version = "v1.2.3" },
    }
    actions.install(ctx)
    assert.same({}, resolves)
    assert.equals("version", calls[1])
    assert.equals(2, #calls)
    assert.equals("v1.2.3", calls[2].pin)
    assert.equals(2, #calls[2].specs)
  end)

  it("skips a current tag and reinstalls a changed tag", function()
    ctx.packages = { { name = f.spec.name, version = "v1.2.3" } }
    f.install({ skill = "demo", url = f.spec.url, pin = "v1.2.3" })
    actions.install(ctx)
    assert.same({}, calls)
    ctx.packages[1].version = "v1.2.4"
    actions.install(ctx)
    assert.equals("version", calls[1])
    assert.equals("v1.2.4", calls[2].pin)
  end)

  it("resolves latest once per source and installs the resolved SHA", function()
    ctx.packages = {
      { name = "example/skills/demo", version = "latest" },
      { name = "example/skills/other", version = "latest" },
      { name = "second/repo/third", version = "latest" },
    }
    actions.install(ctx)
    assert.same({ f.spec.url, second }, resolves)
    assert.equals("version", calls[1])
    assert.equals(2, #calls[2].specs)
    assert.equals(head, calls[2].pin)
    assert.equals(1, #calls[3].specs)
    assert.equals(head, calls[3].pin)
    local lock = require("lib.state").read_lock()
    assert.equals(head, lock.demo.ref)
    assert.equals(second, lock.third.sourceUrl)
  end)

  it("treats an omitted request version as latest", function()
    ctx.packages = { { name = f.spec.name } }
    actions.install(ctx)
    assert.same({ f.spec.url }, resolves)
    assert.equals(head, calls[2].pin)
    assert.equals(head, require("lib.state").read_lock().demo.ref)
  end)

  it("skips a current latest and refreshes a moved HEAD", function()
    ctx.packages = { { name = f.spec.name, version = "latest" } }
    f.install({ skill = "demo", url = f.spec.url, pin = head })
    actions.install(ctx)
    assert.same({}, calls)
    head = string.rep("d", 40)
    actions.install(ctx)
    assert.equals("version", calls[1])
    assert.equals(head, calls[2].pin)
    assert.equals(head, require("lib.state").read_lock().demo.ref)
  end)

  it("resolves latest during a dry run without touching the CLI", function()
    ctx.packages = { { name = f.spec.name, version = "latest" } }
    ctx.dry_run = true
    actions.install(ctx)
    assert.same({ f.spec.url }, resolves)
    assert.same({}, calls)
    assert.same({}, f.nodes)
  end)

  it("surfaces resolution failures before probing the CLI", function()
    package.loaded["lib.git"].resolve_head = function()
      error("Could not resolve latest for " .. f.spec.url)
    end
    ctx.packages = { { name = f.spec.name, version = "latest" } }
    assert.has_error(function()
      actions.install(ctx)
    end)
    assert.same({}, calls)
  end)

  it("removes a latest-declared skill holding a resolved SHA", function()
    f.install({ skill = "demo", url = f.spec.url, pin = head })
    ctx.packages = { { name = f.spec.name, version = "latest" } }
    actions.remove(ctx)
    assert.same({ "version", "demo" }, calls)
    assert.same({}, resolves)
  end)

  it("does not remove a latest declaration over a ref-shaped entry", function()
    f.install({ skill = "demo", url = f.spec.url, pin = "v1.2.3" })
    ctx.packages = { { name = f.spec.name, version = "latest" } }
    assert.has_error(function()
      actions.remove(ctx)
    end)
    assert.same({}, calls)
  end)
end)
