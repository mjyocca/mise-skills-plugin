local actions = require("lib.actions")

function PLUGIN:PackageInstall(ctx)
  actions.install(ctx)
end
