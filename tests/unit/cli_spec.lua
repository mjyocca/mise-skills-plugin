local json = require("dkjson")
local support = require("tests.unit.support")

describe("skills CLI adapter", function()
  local f, cli, group, result
  before_each(function()
    f = support.fixture()
    cli = require("lib.cli")
    group = require("lib.package").group({ f.spec })[1]
    result = {
      name = "demo",
      status = "installed",
      source = f.spec.source,
      ref = f.spec.pin,
      path = require("lib.state").target(f.spec),
      scope = "global",
      agents = { "Codex" },
      mode = "copy",
    }
  end)
  after_each(function()
    f.restore()
  end)

  it("checks exactly the supported version", function()
    cli.check_version()
    assert.equals("skills --version", f.commands[1].command)
    f.exec = function()
      return "9.0.0\n"
    end
    assert.has_error(cli.check_version)
  end)

  it("passes values through env and bounds commands with a timeout", function()
    f.exec = function()
      return json.encode({ result })
    end
    cli.add(group)
    local call = f.commands[1]
    assert.equals(
      'skills add "$SKILLS_SOURCE" --skill "$SKILLS_NAME_1"'
        .. ' --global --agent "$SKILLS_AGENT" --copy --yes --json',
      call.command
    )
    assert.equals(f.spec.url .. "#" .. f.spec.pin, call.options.env.SKILLS_SOURCE)
    assert.equals("demo", call.options.env.SKILLS_NAME_1)
    assert.equals("1", call.options.env.DISABLE_TELEMETRY)
    assert.equals("0", call.options.env.GIT_TERMINAL_PROMPT)
    assert.equals(120, call.options.timeout)
  end)

  it("reports transport failures", function()
    f.exec = function()
      error("fixture transport failure")
    end
    assert.has_error(cli.check_version)
  end)

  for _, text in ipairs({ "garbage", "null", "{}", "[]" }) do
    it("rejects invalid or empty responses " .. text, function()
      assert.has_error(function()
        cli.validate_add(text, group)
      end)
    end)
  end

  for field, value in pairs({
    name = "unexpected",
    status = "skipped",
    source = "other/repo",
    ref = "main",
    path = "/outside",
    scope = "project",
    agents = { "opencode" },
    mode = "symlink",
  }) do
    it("checks result " .. field, function()
      result[field] = value
      assert.has_error(function()
        cli.validate_add(json.encode({ result }), group)
      end)
    end)
  end

  it("rejects duplicate and unexpected results", function()
    assert.has_error(function()
      cli.validate_add(json.encode({ result, result }), group)
    end)
    cli.validate_add(json.encode({ result }), group)
  end)

  it("removes only an explicit name through the same scope", function()
    cli.remove(f.spec)
    assert.equals(
      'skills remove "$SKILLS_NAME" --global --agent "$SKILLS_AGENT" --yes',
      f.commands[1].command
    )
    assert.equals("demo", f.commands[1].options.env.SKILLS_NAME)
    assert.equals("codex", f.commands[1].options.env.SKILLS_AGENT)
  end)
end)
