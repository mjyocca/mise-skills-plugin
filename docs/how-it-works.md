# How it works

The plugin implements four mise hooks:

1. **PackageInstalled** - Checks if a skill is already installed by reading the Vercel skills CLI's global lock file
2. **PackageInstall** - Installs missing or outdated skills via the skills CLI
3. **PackageUpgrade** - Receives present requests, applies changed pins, and refreshes `latest` declarations
4. **PackageUninstall** - Rechecks ownership before removing only the packages mise supplies

## Version resolution

Commit SHAs and tag/branch names travel to the CLI unchanged inside the
source URL fragment (`<url>#<ref>`); the CLI clones that ref and the lock
records the declared value verbatim.

`latest` declarations arrive from mise without a version. The plugin resolves
them itself with one read-only `git ls-remote <url> HEAD` per repository per
operation (including dry runs), then installs and verifies the exact resolved
SHA. The lock and `status` therefore show a real commit SHA for `latest`
skills. Resolution is bounded by a 60-second timeout and disables Git terminal
prompts. Status checks and removal never resolve, so they stay offline.

## CLI invocation

The plugin invokes `skills` through the hook's `PATH`. Package-manager hooks
retain mise's shims and global tool paths; the plugin does not depend on mise's
internal npm installation layout. It checks `skills --version` before the first
mutation and requires a stable `x.y.z` release at or above 1.7.6. Prerelease,
build-suffixed, and malformed version strings are rejected. Status and dry runs
do not probe the CLI version. The examples pin the minimum version for
reproducibility; newer releases still have to satisfy the JSON, lock, and
filesystem contracts below.

Requests sharing a source and pin use one `skills add` call with multiple
`--skill` names. Commands use quoted environment variables, disable telemetry
and Git terminal prompts, and have a 120-second timeout. The plugin validates
the CLI's JSON results and then independently rereads the lock and checks files.
Operations are sequential and non-transactional: a failed batch can leave
earlier skills installed, and the plugin never rolls back by deleting content.

## Lock file location

The plugin reads the Vercel skills CLI's global lock file from:
- `$XDG_STATE_HOME/skills/.skill-lock.json` (if set), or
- `~/.agents/.skill-lock.json` (default)

The adapter accepts global lock schema version 3 and validates the requested
entry's GitHub source URL, provider type, and ref. It never writes the CLI's lock.
`skills list --json` is not used for pin checks because its output omits refs.

The target must be a real directory containing a regular `SKILL.md`. The plugin
rejects symlinked locks, symlinked ancestors, and symlinks anywhere inside a
requested target, including hidden directories. Use absolute, non-symlinked
`HOME` and `XDG_STATE_HOME` paths. These are safety checks, not content hashes
or protection against another process changing files after inspection.
