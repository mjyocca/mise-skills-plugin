# mise-skills-plugin

A [mise](https://mise.jdx.dev/) package manager plugin for declarative external skill management via the [Vercel skills CLI](https://github.com/vercel-labs/skills).

## What it does

This plugin enables you to declare external agent skills in your mise configuration and have mise automatically install, update, and remove them using the Vercel skills CLI.

**Before** (manual management):
```bash
# Manually run CLI commands
skills add "https://github.com/vercel-labs/skills.git#7a5e920bead4b1039a6d6df5d7e1163b7b09423a" \
  --skill find-skills \
  --global --agent codex --copy --yes
```

**After** (declarative):
```toml
# .config/mise/config.toml
[bootstrap.plugins]
skills = "https://github.com/mjyocca/mise-skills-plugin"

[bootstrap.packages]
"skills:vercel-labs/skills/find-skills" = "7a5e920bead4b1039a6d6df5d7e1163b7b09423a"

[tools]
node = "22.20.0"
"npm:skills" = "1.7.6"
```

Then run:
```bash
mise bootstrap
# or
mise bootstrap packages apply
```

## Features

- **Declarative**: Define skills in TOML configuration
- **Version-pinned**: Use full commit SHAs for reproducible installs
- **Automatic lifecycle**: Install, upgrade, and remove skills via mise commands
- **Offline status checks**: Query installed skills without network calls
- **Conflict detection**: Checks source ownership, revision, canonical names, and symlinks
- **Safe previews**: Dry runs do not invoke the skills CLI or change skill state
- **Lock file integration**: Reads the Vercel skills CLI's global lock

## Prerequisites

- [mise](https://mise.jdx.dev/) (v2026.10.25 or later)
- Node.js v22.20.0 or later
- The Vercel skills CLI **v1.7.6 or newer**, available on the hook's `PATH`
- Git, for the skills CLI's clone fallback

Skills are installed globally as copies in `~/.agents/skills`, using the CLI's
`codex` agent scope. This scope is fixed; the plugin does not install separate
copies into every agent's native directory.

## Installation

### 1. Add the plugin to your mise configuration

```toml
# .config/mise/config.toml
[bootstrap.plugins]
skills = "https://github.com/mjyocca/mise-skills-plugin"
```

For a reproducible plugin installation, append `#<git-ref>` to the repository
URL, replacing the placeholder with a published tag or full commit SHA.

### 2. Install the Vercel skills CLI

```toml
[tools]
node = "22.20.0"
"npm:skills" = "1.7.6"
```

Install the tools before applying packages:

```bash
mise install
```

### 3. Install the plugin

```bash
mise bootstrap plugins apply
```

## Usage

### Declare a skill

Add skills to your `[bootstrap.packages]` section:

```toml
[bootstrap.packages]
# Format: "skills:<owner>/<repo>/<skill-id>" = "<commit-sha>"
"skills:vercel-labs/skills/find-skills" = "7a5e920bead4b1039a6d6df5d7e1163b7b09423a"
```

The package name format is:
- `skills:` - Plugin prefix (required)
- `<owner>/<repo>` - GitHub repository
- `<skill-id>` - Exact canonical skill name, not its path in the repository
- `<commit-sha>` - Full 40-character lowercase hexadecimal Git commit SHA

Skill IDs must start with a lowercase letter or digit, contain only lowercase
letters, digits, `.`, `_`, and `-`, and not end in a dot or hyphen. They must
already match the CLI's lock key and directory name: aliases, mixed-case names,
plugin-qualified names, wildcard selectors, and nested paths are unsupported.
Two repositories cannot declare the same skill ID because the CLI shares one
global lock key and directory for that ID. Omitted pins, branches, tags, and
`"latest"` are rejected.

### Install declared skills

```bash
mise bootstrap packages apply
```

This installs any missing or outdated skills.

### Check status

```bash
mise bootstrap packages status
```

Shows installed skills, their declared pins, and any mismatches.

### Update a skill

Change the commit SHA in your configuration:

```toml
[bootstrap.packages]
# Replace the value with the new full lowercase commit SHA.
"skills:vercel-labs/skills/find-skills" = "<new-40-character-commit-sha>"
```

Then apply:

```bash
mise bootstrap packages apply
```

The plugin detects the version change and reinstalls the skill.

`mise bootstrap packages upgrade --manager skills` also installs changed pins,
but skips already-current ones. Neither `upgrade` nor `apply --update` is a
force-reinstall operation; this manager has no metadata cache to refresh.

Preview changes with `mise bootstrap packages apply --dry-run` or
`mise bootstrap packages upgrade --dry-run`.

### Remove a skill

Remove the declaration from your configuration, then:

```bash
mise bootstrap packages prune --manager skills
```

This removes no-longer-declared skills that **mise installed itself**, subject to
mise's ownership tracking across trusted configurations. Pre-existing skills
are not adopted for pruning. Use `--dry-run` to preview removals.

## How it works

The plugin implements four mise hooks:

1. **PackageInstalled** - Checks if a skill is already installed by reading the Vercel skills CLI's global lock file
2. **PackageInstall** - Installs missing or outdated skills via the skills CLI
3. **PackageUpgrade** - Receives installed requests and applies changed pins, skipping current ones
4. **PackageUninstall** - Rechecks ownership before removing only the packages mise supplies

### CLI invocation

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

### Lock file location

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

## Known limitations

- **No content verification or forced reinstall**: Missing targets or entrypoints are repaired by `apply`, but edited file contents are not detected when the pin matches
- **Shared-agent removal**: The CLI can retain canonical content used by another agent; prune reports incomplete removal rather than force-deleting it
- **Lock-only leftovers**: The removal hook handles a tracked entry with missing files when supplied, but mise may already consider it missing and not call the hook; review stale entries with the skills CLI
- **Pinned declarations only**: On mise v2026.10.25, explicit `apply skills:owner/repo/skill` arguments arrive without a version; use declarations and `--manager skills` instead
- **CLI contract compatibility**: Versions at or above 1.7.6 pass the version gate, but breaking changes to command flags, JSON output, or lock schema still require adapter updates
- **GitHub only**: Currently only supports GitHub repositories (no GitLab, Bitbucket, etc.)
- **HTTPS only**: Only supports HTTPS GitHub URLs (no SSH)

## Development

### Testing

On Debian/Ubuntu, first install `build-essential`, `pkg-config`,
`libreadline-dev`, and `libncurses-dev`; mise builds Lua 5.1 from source.

Install the pinned development tools, then the project-local Lua test tools:

```bash
mise trust
mise install
mise run deps:lua
mise run check
```

`check` runs StyLua, Luacheck, and three Lua 5.1/Busted suites: unit tests,
test-harness checks, and offline integration tests. The integration suite launches
the actual mise executable in isolated HOME/XDG directories; it does not mock
mise's embedded runtime. The Lua fake CLI records arguments and supports failure
injection, but does not establish upstream compatibility. Python is not required.

The test harness uses LuaPosix for argv-based subprocesses and LuaSystem for
monotonic timeouts. These are development-only dependencies installed by
`deps:lua`; building them requires a C compiler and make. Subprocesses have clean
environments and separate output capture, and timeouts terminate their process
groups. Fixture cleanup unlinks symlinks without following them.

Run suites individually with `mise run test:unit`, `mise run test:harness`, or
`mise run test:integration`. Run these commands from the repository root.

The optional real-CLI test needs Node and skills >= 1.7.6 installed. It fetches a
skill from the CLI's immutable source revision and exercises install, status,
upgrade, dry runs, and prune in a disposable home:

```bash
SKILLS_CLI_TEST_BIN="$(mise exec npm:skills@1.7.6 -- which skills)" mise run test:compat
```

`test:compat` skips when `SKILLS_CLI_TEST_BIN` is unset or empty. When set, it must
be an absolute path to an executable; an invalid path fails the test.
Offline CI runs once per pull request update on `ubuntu-slim` with the latest
mise release. Branch pushes do not trigger CI. The separate **Compatibility**
workflow uses the same runner and mise release. One job installs Node and both
skills versions, **1.7.6** (the minimum) and **latest**, in a single setup. It then
runs two test processes concurrently with isolated HOME/XDG directories. Both
results must pass; latest is not an allowed-to-fail canary. Per-version logs and
a job summary report both results, even if one suite fails.

Both workflows call `.github/actions/setup`, a composite action that installs
the system build packages, mise, and Lua test tools in the current job. Its
optional `skills-versions` input accepts a space-separated list, installs Node
and the requested CLIs, exposes Node on `PATH`, and returns a JSON map of CLI
paths as `skills-cli-bins`. Checkout and approval gating stay in the workflows;
a separate setup job would not share its installed tools with other runners.

`ubuntu-slim` is a single-CPU hosted container, not a full VM. Jobs have a
12-minute timeout, below the runner's 15-minute limit. External actions are
pinned to commit SHAs, and mise manages tool caching. Cold-cache setup and native
Lua builds must fit within the timeout.

- Owner-authored PRs run compatibility tests automatically on opening, reopening,
  and new commits. These runs test the event's merge commit.
- For contributor PRs, the repository owner submits an **Approve** PR review to
  start compatibility tests. The review must cover the PR's current head commit;
  tests check out that exact SHA. Comments and other reviewers' approvals do not
  start the compatibility job. New commits require another approving review.
- As a fallback, the owner can manually run **Compatibility** and supply its
  `pr_number`. This tests the PR's current merge ref. Leaving the input blank
  tests the selected branch's event SHA instead.

To configure GitHub:

1. Merge the workflow files into the default branch so manual runs are available.
2. Under **Settings → Actions → General**, consider **Require approval for all
   external contributors**. This repository-level policy gates entire fork
   workflows, including offline tests; approving a PR review does not replace
   GitHub's separate **Approve and run** action when that approval is required.
3. In the default branch's ruleset or branch protection, require the offline
   **CI** check named `check`. Replace any old OS/mise matrix check requirements
   with this single check. Leave compatibility checks optional unless you also
   design a required-check gate that handles their intentionally skipped runs.
4. Optionally enable **Dismiss stale pull request approvals when new commits are
   pushed** to keep merge approval aligned with reviewed code.

The workflow's owner conditions control normal CI execution, not protection
against a PR rewriting its workflow. Use GitHub's fork approval policy for that
additional gate. Both workflows use read-only tokens and do not persist checkout
credentials; no environment or deployment approval setup is needed.

To try a working copy manually, link it in a disposable mise environment with
`mise plugins link skills /absolute/path/to/mise-skills-plugin`. Use throwaway
`HOME` and XDG directories and check `status` and `apply --dry-run` first;
applying packages in your normal environment changes your global skills.

### Preparing a release

See the [release guide](docs/release.md) for version bumps, Actions-driven draft
preparation, and publishing through GitHub Releases.

### Plugin structure

```
mise-skills-plugin/
├── metadata.lua              # Plugin metadata
├── version.lua               # Single source for the plugin release version
├── mise.plugin.toml          # Plugin configuration
├── hooks/
│   ├── package_installed.lua   # Status check hook
│   ├── package_install.lua     # Installation hook
│   ├── package_upgrade.lua     # Upgrade hook
│   └── package_uninstall.lua   # Removal hook
├── lib/
│   ├── package.lua             # Pure package validation and batch planning
│   ├── state.lua               # Read-only lock and filesystem adapter
│   ├── cli.lua                 # Versioned CLI transport and JSON contract
│   └── actions.lua             # Shared lifecycle operations
├── tests/
│   ├── unit/                   # Lua 5.1/Busted tests
│   ├── harness/                # Subprocess and safe-cleanup regression tests
│   ├── integration/            # Status and lifecycle tests against real mise
│   ├── compat/                 # Opt-in real CLI test
│   ├── fixtures/               # Independent Lua fake skills CLI
│   └── support/                # Shared isolated fixture and subprocess helpers
└── mise.toml                   # Development tools and tasks
```

## Troubleshooting

### Plugin not found

Apply the plugin declaration and check its installation:
```bash
mise bootstrap plugins apply
mise bootstrap plugins status
```

### Skills CLI not found

Ensure you've installed the Vercel skills CLI via mise:
```toml
[tools]
node = "22.20.0"
"npm:skills" = "1.7.6"
```

Then run:
```bash
mise install
```

### Unsupported CLI version or permission denied

Check which command your configuration selects and reinstall the declared tool
if its executable is damaged. Do not repair paths guessed from mise's data layout.

```bash
mise exec -- skills --version
mise which skills
```

The expected version is a stable `x.y.z` release at or above `1.7.6`. If an older
or prerelease executable shadows it on `PATH`, correct the tool configuration or
shell environment before applying. A newer version that fails JSON or lock
validation needs a contract review; pin a previously verified release while
investigating.

## License

MIT

## Contributing

Contributions are welcome! Please open an issue or PR on GitHub.

## Resources

- [mise documentation](https://mise.jdx.dev/)
- [Vercel skills CLI](https://github.com/vercel-labs/skills)
- [mise package manager plugin development](https://mise.jdx.dev/package-plugin-development.html)
- [mise Lua runtime reference](https://mise.jdx.dev/plugin-lua-modules.html)
