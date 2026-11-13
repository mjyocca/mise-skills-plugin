-- PackageInstall hook: install missing or mismatched packages.
-- Called by mise when PackageInstalled indicates a package needs installation.
--
-- Behavior per spec:
-- - Group requests by (url, ref) to minimize clones.
-- - Resolve the CLI via direct binary path (shims fail from hooks).
-- - Run `add` with DISABLE_TELEMETRY=1 GIT_TERMINAL_PROMPT=0,
--   --global --agent codex --copy --yes --json.
-- - Values passed via env, never interpolated into shell code unquoted.
-- - After each call, re-read the lock and verify recorded source/ref/entrypoint.
-- - A false CLI success fails the batch.
-- - Installs are sequential and non-transactional.
--
-- Limitation: mise calls this hook even during --dry-run, and cmd.exec runs normally.
-- The hook cannot honor dry-run. This is a documented mise limitation.

local cmd = require("cmd")
local file = require("file")
local log = require("log")
local shared = require("lib.shared")

-- The pinned CLI version. Must match the mise tool declaration.
local CLI_VERSION = "1.7.6"

function PLUGIN:PackageInstall(ctx)
  local data_dir = os.getenv("MISE_DATA_DIR")
  local cli = shared.resolve_cli(data_dir, CLI_VERSION)

  -- Group by (url, ref) to minimize clones.
  local groups = {}
  local group_order = {}
  for _, pkg in ipairs(ctx.packages) do
    local owner, repo, skill_id = shared.parse_package_name(pkg.name)
    local url = shared.source_url(owner, repo)
    local pin = pkg.version
    local key = url .. "#" .. pin
    if not groups[key] then
      groups[key] = { url = url, ref = pin, skills = {} }
      table.insert(group_order, key)
    end
    table.insert(groups[key].skills, skill_id)
  end

  -- Install each group sequentially.
  for _, key in ipairs(group_order) do
    local group = groups[key]
    for _, skill_id in ipairs(group.skills) do
      log.info("Install globally: " .. skill_id .. " from " .. group.url .. "#" .. group.ref)

      -- Construct the command. Values are passed via env, not shell interpolation.
      local source = group.url .. "#" .. group.ref
      local command = string.format(
        "%q add %q --skill %q --global --agent codex --copy --yes --json",
        cli, source, skill_id
      )

      local ok, stdout = pcall(cmd.exec, command, {
        env = {
          DISABLE_TELEMETRY = "1",
          GIT_TERMINAL_PROMPT = "0",
        },
      })

      if not ok then
        error("CLI invocation failed for " .. skill_id .. ": " .. tostring(stdout))
      end

      -- Verify installation succeeded by re-reading the lock.
      local lock = shared.read_lock()
      if not lock then
        error("CLI did not create the global lock after installing " .. skill_id)
      end

      local entry = lock[skill_id]
      if not entry then
        error("CLI did not record " .. skill_id .. " in the global lock")
      end

      if entry.sourceUrl ~= group.url then
        error("CLI recorded wrong source for " .. skill_id ..
              ": expected " .. group.url .. ", got " .. tostring(entry.sourceUrl))
      end

      if entry.ref ~= group.ref then
        error("CLI recorded wrong ref for " .. skill_id ..
              ": expected " .. group.ref .. ", got " .. tostring(entry.ref))
      end

      -- Verify entrypoint exists.
      local target = shared.target_dir()
      local entrypoint = target .. "/" .. skill_id .. "/SKILL.md"
      if not file.exists(entrypoint) then
        error("CLI did not create the entrypoint for " .. skill_id .. ": " .. entrypoint)
      end
    end
  end
end
