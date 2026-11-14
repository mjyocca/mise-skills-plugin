local process = require("tests.support.process")
local fs = require("tests.support.fs")

describe("subprocess test helper", function()
  it("passes literal argv without shell expansion", function()
    local literal = "spaces 'quotes' $(touch injected); *"
    local result = process.run({ "/bin/echo", literal })
    assert.equals(0, result.code)
    assert.equals(literal .. "\n", result.stdout)
    assert.equals("", result.stderr)
  end)

  it("replaces rather than merges the environment and honors cwd", function()
    local root = process.tempdir()
    finally(function()
      fs.remove(root, root)
    end)
    local result = process.run({ "/bin/sh", "-c", 'printf "%s\\n%s" "$HOME" "$PWD"' }, {
      cwd = root,
      env = { PATH = "/usr/bin:/bin", HOME = "isolated home" },
    })
    assert.equals(0, result.code)
    assert.equals("isolated home\n" .. root, result.stdout)
    result = process.run({ "/usr/bin/env" }, { env = { ONLY_THIS = "present" } })
    assert.equals(0, result.code)
    assert.equals("ONLY_THIS=present\n", result.stdout)
  end)

  it("captures stdout and stderr separately without pipe-buffer deadlocks", function()
    local result = process.run({
      "/bin/sh",
      "-c",
      'i=0; while [ "$i" -lt 5000 ]; do printf "stdout line\\n"; '
        .. 'printf "stderr line\\n" >&2; i=$((i + 1)); done; exit 7',
    })
    assert.equals(7, result.code)
    assert.equals(string.rep("stdout line\n", 5000), result.stdout)
    assert.equals(string.rep("stderr line\n", 5000), result.stderr)
  end)

  it("reports executable lookup failures", function()
    local result = process.run({ "/nonexistent/mise-skills-test-command" })
    assert.equals(127, result.code)
    assert.is_not.equal("", result.stderr)
    assert.is_false(result.timed_out)
  end)

  it("reports invalid working directories", function()
    local result = process.run({ "/bin/echo", "unreachable" }, {
      cwd = "/nonexistent/mise-skills-test-directory",
    })
    assert.equals(127, result.code)
    assert.equals("", result.stdout)
    assert.is_not.equal("", result.stderr)
  end)

  it("kills timed-out process groups including their children", function()
    local root = process.tempdir()
    finally(function()
      fs.remove(root, root)
    end)
    local marker = root .. "/child survived"
    local result = process.run({
      "/bin/sh",
      "-c",
      '(sleep 0.4; printf leaked > "$1") & wait',
      "sh",
      marker,
    }, { timeout = 0.1 })
    assert.is_true(result.timed_out)
    assert.is_not.equal(0, result.code)
    assert.equals(0, process.run({ "/bin/sleep", "0.6" }).code)
    assert.is_false(fs.exists(marker))
  end)
end)
