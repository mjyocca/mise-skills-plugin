local actions = require("lib.actions")

-- mise passes all installed requests, including already-current pins.
function PLUGIN:PackageUpgrade(ctx)
  actions.install(ctx)
end
