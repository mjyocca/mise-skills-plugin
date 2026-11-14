local actions = require("lib.actions")

-- mise supplies only packages it owns; never infer removals from omissions.
function PLUGIN:PackageUninstall(ctx)
  actions.remove(ctx)
end
