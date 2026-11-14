local support = require("tests.unit.support")

describe("git transport", function()
  local f, git
  local url = "https://github.com/example/skills.git"
  local head = string.rep("c", 40)
  before_each(function()
    f = support.fixture()
    git = require("lib.git")
  end)
  after_each(function()
    f.restore()
  end)

  it("resolves HEAD through fixed shell code and env", function()
    f.exec = function()
      return head .. "\tHEAD\n"
    end
    assert.equals(head, git.resolve_head(url))
    local call = f.commands[1]
    assert.equals('git ls-remote "$GIT_REMOTE_URL" HEAD', call.command)
    assert.equals(url, call.options.env.GIT_REMOTE_URL)
    assert.equals("0", call.options.env.GIT_TERMINAL_PROMPT)
    assert.equals(60, call.options.timeout)
  end)

  it("ignores non-HEAD lines", function()
    f.exec = function()
      return head .. "\tHEAD\n" .. string.rep("d", 40) .. "\trefs/heads/main\n"
    end
    assert.equals(head, git.resolve_head(url))
  end)

  for _, output in ipairs({
    "",
    "\n",
    head .. "\trefs/heads/main\n",
    "xyz\tHEAD\n",
    head:sub(1, 39) .. "\tHEAD\n",
    head .. "\tHEAD\n" .. string.rep("d", 40) .. "\tHEAD\n",
    head .. " HEAD extra\n",
    "1.7.6\n",
  }) do
    it("rejects malformed output " .. string.format("%q", output), function()
      f.exec = function()
        return output
      end
      assert.has_error(function()
        git.resolve_head(url)
      end)
    end)
  end

  it("reports transport failures with the URL", function()
    f.exec = function()
      error("network unreachable")
    end
    local ok, message = pcall(git.resolve_head, url)
    assert.is_false(ok)
    assert.truthy(tostring(message):find(url, 1, true))
  end)
end)
