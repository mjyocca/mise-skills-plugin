-- PackageUpgrade hook: reinstall packages when the pin changes.
-- Called by mise only when PackageInstalled returns a different version than declared.
--
-- Behavior per spec:
-- - Called only on pin changes (not on apply --update with matching pins).
-- - ctx.update does not exist; apply --update does NOT force reinstall.
-- - Forced repair is not achievable via mise's native commands.
-- - Reinstall at the new pin using the same logic as PackageInstall.

local shared = require("lib.shared")

local CLI_VERSION = "1.7.6"

function PLUGIN:PackageUpgrade(ctx)
  local data_dir = os.getenv("MISE_DATA_DIR")
  local cli = shared.resolve_cli(data_dir, CLI_VERSION)

  for _, pkg in ipairs(ctx.packages) do
    local owner, repo, skill_id = shared.parse_package_name(pkg.name)
    local url = shared.source_url(owner, repo)
    local pin = pkg.version
    local source = url .. "#" .. pin

    log.info("Upgrade globally: " .. skill_id .. " to " .. url .. "#" .. pin)

    local cmd = string.format(
      "%q add %q --skill %q --global --agent codex --copy --yes --json",
      cli, source, skill_id
    )

    local ok, stdout = pcall(cmd.exec, cmd, {
      env = {
        DISABLE_TELEMETRY = "1",
        GIT_TERMINAL_PROMPT = "0",
      },
    })

    if not ok then
      error("CLI invocation failed for " .. skill_id .. ": " .. tostring(stdout))
    end

    -- Verify upgrade succeeded.
    local lock = shared.read_lock()
    if not lock then
      error("CLI did not create the global lock after upgrading " .. skill_id)
    end

    local entry = lock[skill_id]
    if not entry then
      error("CLI did not record " .. skill_id .. " in the global lock after upgrade")
    end

    if entry.sourceUrl ~= url then
      error("CLI recorded wrong source for " .. skill_id ..
            ": expected " .. url .. ", got " .. tostring(entry.sourceUrl))
    end

    if entry.ref ~= pin then
      error("CLI recorded wrong ref for " .. skill_id ..
            ": expected " .. pin .. ", got " .. tostring(entry.ref))
    end

    local target = shared.target_dir()
    local entrypoint = target .. "/" .. skill_id .. "/SKILL.md"
    if not file.exists(entrypoint) then
      error("CLI did not create the entrypoint for " .. skill_id .. ": " .. entrypoint)
    end
  end
end
