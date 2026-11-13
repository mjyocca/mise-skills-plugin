-- PackageUninstall hook: remove packages when pruned.
-- Called by mise when packages are pruned (removed from declarations).
--
-- Behavior per spec:
-- - Re-verify lock ownership (declared source/ref, real files, not a symlink)
--   before invoking skills remove.
-- - Report incomplete removal (shared canonical content) instead of deleting
--   beyond the CLI's scope.
-- - Only ever touches the packages in ctx.packages.

local shared = require("lib.shared")

local CLI_VERSION = "1.7.6"

function PLUGIN:PackageUninstall(ctx)
  local data_dir = os.getenv("MISE_DATA_DIR")
  local cli = shared.resolve_cli(data_dir, CLI_VERSION)
  local lock = shared.read_lock()
  local target = shared.target_dir()

  for _, pkg in ipairs(ctx.packages) do
    local owner, repo, skill_id = shared.parse_package_name(pkg.name)
    local url = shared.source_url(owner, repo)
    local pin = pkg.version
    local path = target .. "/" .. skill_id

    -- Re-verify ownership before removal.
    local stat = file.stat(path)
    if not stat then
      -- Already gone; nothing to do.
      log.info("Already removed: " .. skill_id)
    else
      if stat.is_symlink then
        error("Target is a symlink; not removing: " .. path)
      end
      if not stat.is_dir then
        error("Target is not a directory; not removing: " .. path)
      end

      -- Check lock ownership.
      if not lock then
        error("No global lock; cannot verify ownership of " .. skill_id)
      end

      local entry = lock[skill_id]
      if not entry then
        error("Not tracked in global lock; not removing: " .. skill_id)
      end

      if entry.sourceUrl ~= url then
        error("Different source in global lock for " .. skill_id ..
              ": declared " .. url .. ", installed " .. tostring(entry.sourceUrl))
      end

      if entry.ref ~= pin then
        error("Different ref in global lock for " .. skill_id ..
              ": declared " .. pin .. ", installed " .. tostring(entry.ref))
      end

      -- Invoke the CLI for removal.
      log.info("Remove globally: " .. skill_id)

      local cmd = string.format(
        "%q remove %q --global --agent codex --yes",
        cli, skill_id
      )

      local ok, stdout = pcall(cmd.exec, cmd, {
        env = {
          DISABLE_TELEMETRY = "1",
        },
      })

      if not ok then
        error("CLI invocation failed for remove " .. skill_id .. ": " .. tostring(stdout))
      end

      -- Verify removal. Re-read the lock.
      lock = shared.read_lock()
      if lock and lock[skill_id] then
        -- The CLI may retain content if another agent still uses it.
        -- Report rather than force-delete.
        error("CLI did not fully remove " .. skill_id ..
              "; inspect remaining agent usage before retrying")
      end

      -- Check that files are gone.
      if file.exists(path) then
        error("CLI did not remove files for " .. skill_id ..
              "; inspect remaining content before retrying")
      end
    end
  end
end
