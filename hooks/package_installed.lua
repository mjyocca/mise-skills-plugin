local package_contract = require("lib.package")
local state = require("lib.state")

function PLUGIN:PackageInstalled(ctx)
  local specs = package_contract.parse_batch(ctx.packages)
  local lock = state.read_lock()
  local results = {}
  for _, spec in ipairs(specs) do
    local entry, present = state.inspect(lock, spec)
    results[#results + 1] = {
      name = spec.name,
      state = present and "installed" or "missing",
      version = present and entry.ref or nil,
    }
  end
  return { packages = results }
end
