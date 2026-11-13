local support = require("tests.unit.support")

describe("global state adapter", function()
  local f, state
  before_each(function()
    f = support.fixture()
    state = require("lib.state")
  end)
  after_each(function()
    f.restore()
  end)

  it("supports the CLI's XDG and default lock locations", function()
    assert.equals("/fixture/state/skills/.skill-lock.json", state.lock_path())
    f.env.XDG_STATE_HOME = nil
    assert.equals("/fixture/home/.agents/.skill-lock.json", state.lock_path())
  end)

  it("does not require HOME to locate an explicit XDG lock", function()
    f.env.HOME = nil
    assert.equals("/fixture/state/skills/.skill-lock.json", state.lock_path())
  end)

  it("rejects relative and dot-segment base paths", function()
    for _, home in ipairs({ "relative", "/home/../elsewhere", "/home/." }) do
      f.env.HOME = home
      assert.has_error(state.target_dir)
    end
  end)

  it("returns missing without creating files", function()
    assert.is_nil(state.read_lock())
    local entry, present = state.inspect(nil, f.spec)
    assert.is_nil(entry)
    assert.is_false(present)
    assert.same({}, f.nodes)
  end)

  for _, text in ipairs({
    "not json",
    "null",
    "[]",
    '{"version":4,"skills":{}}',
    '{"version":3,"skills":null}',
    '{"version":3,"skills":[]}',
    '{"version":3,"skills":[1]}',
  }) do
    it("rejects unsupported lock data " .. text, function()
      f.write(state.lock_path(), text)
      assert.has_error(state.read_lock)
    end)
  end

  it("rejects symlinked lock files and ancestors", function()
    for _, path in ipairs({ state.lock_path(), "/fixture/state/skills" }) do
      f.nodes[path] = { is_symlink = true }
      assert.has_error(state.read_lock)
      f.nodes[path] = nil
    end
  end)

  it("rejects malformed requested entries but leaves unrelated providers alone", function()
    for _, entry in ipairs({
      1,
      false,
      {},
      { sourceType = "github", sourceUrl = f.spec.url, ref = 1 },
    }) do
      assert.has_error(function()
        state.inspect({ demo = entry }, f.spec)
      end)
    end
    local entry, present = state.inspect({ other = { sourceType = "local" } }, f.spec)
    assert.is_nil(entry)
    assert.is_false(present)
  end)

  it("reports missing files even when the installed ref differs", function()
    f.lock({ demo = { sourceType = "github", sourceUrl = f.spec.url, ref = string.rep("b", 40) } })
    local entry, present = state.inspect(state.read_lock(), f.spec)
    assert.equals(string.rep("b", 40), entry.ref)
    assert.is_false(present)
  end)

  it("rejects foreign source ownership even if files are absent", function()
    f.lock({
      demo = {
        sourceType = "github",
        sourceUrl = "https://github.com/other/repo.git",
        ref = f.spec.pin,
      },
    })
    assert.has_error(function()
      state.inspect(state.read_lock(), f.spec)
    end)
  end)

  it("rejects lock aliases that resolve to the same canonical directory", function()
    f.install(f.spec)
    local lock = state.read_lock()
    lock.Demo = { sourceType = "local" }
    assert.has_error(function()
      state.inspect(lock, f.spec)
    end)
  end)

  it("rejects untracked content", function()
    f.dir(state.target(f.spec))
    assert.has_error(function()
      state.inspect(nil, f.spec)
    end)
  end)

  it("does not follow hidden, nested or broken symlinks", function()
    f.install(f.spec)
    local nested = state.target(f.spec) .. "/.hidden/nested"
    f.dir(nested)
    f.nodes[nested .. "/link"] = { is_symlink = true }
    assert.has_error(function()
      state.inspect(state.read_lock(), f.spec)
    end)
  end)

  it("requires a regular entrypoint", function()
    f.install(f.spec)
    f.nodes[state.target(f.spec) .. "/SKILL.md"] = { is_dir = true }
    assert.has_error(function()
      state.inspect(state.read_lock(), f.spec)
    end)
  end)
end)
