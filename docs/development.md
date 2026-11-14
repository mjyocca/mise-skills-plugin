# Development

See [Preparing a release](release.md) for the release process.

## Testing

On Debian/Ubuntu, Lua 5.1 is compiled from source, so Linux build machines
need `build-essential`, `git`, `pkg-config`, `libreadline-dev`, and
`libncurses-dev`. These are declared once in this repository's
`[bootstrap.packages]`, but mise never installs them implicitly: `mise install`
only prints a one-time hint. Install them yourself, or let mise apply them from
the declaration:

```bash
# Explicit and opt-in; runs sudo apt-get install for you (skipped on macOS).
mise bootstrap packages apply
```

The offline suite fakes `git ls-remote` behind a shim that forwards to the
real executable, so `git` must be on `PATH`.

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
injection, but does not establish upstream compatibility. A PATH shim also fakes
only `git ls-remote ... HEAD` for `latest` resolution and forwards other Git
subcommands to the real executable. Python is not required.

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
mise and then runs `mise bootstrap --only packages,tools --update --yes` to apply
the system build packages from `[bootstrap.packages]` before installing `[tools]`.
It installs the Lua test tools next. Its optional `skills-versions` input accepts
a space-separated list, installs Node and the requested CLIs, exposes Node on
`PATH`, and returns a JSON map of CLI paths as `skills-cli-bins`. Checkout and
approval gating stay in the workflows; a separate setup job would not share its
installed tools with other runners.

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

## Plugin structure

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
│   ├── git.lua                 # Read-only remote HEAD resolution for latest
│   └── actions.lua             # Shared lifecycle operations
├── tests/
│   ├── unit/                   # Lua 5.1/Busted tests
│   ├── harness/                # Subprocess and safe-cleanup regression tests
│   ├── integration/            # Status and lifecycle tests against real mise
│   ├── compat/                 # Opt-in real CLI test
│   ├── fixtures/               # Lua fake skills CLI and git ls-remote shim
│   └── support/                # Shared isolated fixture and subprocess helpers
└── mise.toml                   # Development tools and tasks
```
