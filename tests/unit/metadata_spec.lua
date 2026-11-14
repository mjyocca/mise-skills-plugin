local function load_metadata(require_module)
  local env = { require = require_module or require }
  local chunk = assert(loadfile("metadata.lua"))
  setfenv(chunk, env)()
  return env.PLUGIN
end

describe("plugin release version", function()
  it("declares a canonical stable version without a tag prefix", function()
    local version = require("version")
    assert.is_string(version)
    local major, minor, patch = version:match("^(%d+)%.(%d+)%.(%d+)$")
    assert.is_not_nil(major, "version.lua must return an x.y.z release version")
    for _, part in ipairs({ major, minor, patch }) do
      assert.equals(
        tostring(tonumber(part)),
        part,
        "Version components must not have leading zeros"
      )
    end
  end)

  it("loads the declared version into metadata", function()
    assert.equals(require("version"), load_metadata().version)
  end)

  it("uses the version module rather than a duplicated literal", function()
    local metadata = load_metadata(function(name)
      assert.equals("version", name)
      return "9.8.7"
    end)
    assert.equals("9.8.7", metadata.version)
  end)

  it("does not hide a missing or broken version module", function()
    assert.has_error(function()
      load_metadata(function()
        error("version module unavailable", 0)
      end)
    end, "version module unavailable")
  end)
end)
