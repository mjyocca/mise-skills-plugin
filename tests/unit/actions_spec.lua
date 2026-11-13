local support = require("tests.unit.support")

describe("lifecycle actions", function()
  local f, actions, calls, ctx
  before_each(function()
    f = support.fixture()
    calls = {}
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
end)
