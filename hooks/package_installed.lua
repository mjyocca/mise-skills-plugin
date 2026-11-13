-- PackageInstalled hook: check whether each declared package is already installed.
-- Called by mise to determine which packages need installation.
--
-- Behavior per spec:
-- - Return an explicit installed/missing state for every request.
-- - Return the declared pin when lock sourceUrl and ref match AND a real directory
--   with SKILL.md exists at the target path.
-- - Return the installed ref (different from declared) when lock has matching source
--   but different ref, so mise reports a version mismatch and triggers reinstall.
-- - error() on: different source in lock, symlinked/non-directory target, untracked
--   content at target path, authored ID tracked by the CLI.
-- - No network, no side effects.
--
-- Limitation: mise calls this hook even during --dry-run. This is read-only, so
-- that is acceptable.

local file = require("file")
local shared = require("lib.shared")

function PLUGIN:PackageInstalled(ctx)
  local lock = shared.read_lock()
  local target = shared.target_dir()
  local results = {}

  -- Lua 5.1 has no goto; returning from this helper skips a missing package.
  local function installed_version(pkg)
    local owner, repo, skill_id = shared.parse_package_name(pkg.name)
    local url = shared.source_url(owner, repo)
    local pin = pkg.version
    local path = target .. "/" .. skill_id

    -- Check for symlinked or non-directory target.
    local stat = file.stat(path)
    if stat then
      if stat.is_symlink then
        error("Target is a symlink; migrate old mise links first: " .. path)
      end
      if not stat.is_dir then
        error("Target is not a directory; migrate old mise links first: " .. path)
      end
    end

    -- Check for symlinks inside the target directory.
    if stat and stat.is_dir then
      local links = file.glob(path .. "/*")
      for _, link in ipairs(links or {}) do
        local ls = file.stat(link)
        if ls and ls.is_symlink then
          error("Target contains a symlink; migrate old mise links first: " .. link)
        end
      end
    end

    -- Check the lock.
    if not lock then
      -- No lock exists. If files exist at the target, that's untracked content.
      if stat then
        error("Untracked global content at " .. path .. "; not managed by the skills CLI")
      end
      -- Missing: no lock, no files.
      return nil
    end

    local entry = lock[skill_id]
    if not entry then
      -- Not in lock. If files exist, that's untracked.
      if stat then
        error("Untracked global content at " .. path .. "; not tracked in the global lock")
      end
      -- Missing: not in lock, no files.
      return nil
    end

    -- Entry exists in lock. Check source.
    if entry.sourceUrl ~= url then
      error("Different source in global lock for " .. skill_id ..
            ": declared " .. url .. ", installed " .. tostring(entry.sourceUrl))
    end

    -- Check ref.
    if entry.ref ~= pin then
      -- Version mismatch: return the installed ref so mise detects the difference.
      return entry.ref
    end

    -- Source and ref match. Check for SKILL.md entrypoint.
    if not stat then
      -- Lock says installed but files are missing: repair needed.
      -- Return missing so mise reinstalls.
      return nil
    end

    local entrypoint = path .. "/SKILL.md"
    if not file.exists(entrypoint) then
      -- Missing entrypoint: repair needed.
      return nil
    end

    -- Fully installed: return the declared pin.
    return pin
  end

  for _, pkg in ipairs(ctx.packages) do
    local version = installed_version(pkg)
    table.insert(results, {
      name = pkg.name,
      state = version and "installed" or "missing",
      version = version,
    })
  end

  return { packages = results }
end
