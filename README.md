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
# Any published tag/branch name, or "latest" to track the default branch
"skills:vercel-labs/agent-skills/web-design-guidelines" = "v1.2.3"

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
- **Flexible versioning**: Pin a full commit SHA, install by Git tag, or track `latest`
- **Automatic lifecycle**: Install, upgrade, and remove skills via mise commands
- **Offline status checks**: Query installed skills without network calls
- **Conflict detection**: Checks source ownership, revision, canonical names, and symlinks
- **Safe previews**: Dry runs do not invoke the skills CLI or change skill state
- **Lock file integration**: Reads the Vercel skills CLI's global lock

## Prerequisites

- [mise](https://mise.jdx.dev/) (v2026.10.25 or later)
- Node.js v22.20.0 or later
- The Vercel skills CLI **v1.7.6 or newer**, available on the hook's `PATH`
- Git, for the skills CLI's clone fallback and the plugin's `latest` resolution

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

Declare skills in `[bootstrap.packages]`, then apply them:

```toml
[bootstrap.packages]
# Format: "skills:<owner>/<repo>/<skill-id>" = "<version>"
"skills:vercel-labs/skills/find-skills" = "7a5e920bead4b1039a6d6df5d7e1163b7b09423a"
"skills:vercel-labs/agent-skills/web-design-guidelines" = "v1.2.3"
"skills:vercel-labs/agent-skills/frontend-design" = "latest"
```

Select skills by canonical **name** (their `SKILL.md` `name`), not a repository
path. A skill nested under a plugin root is still declared by name alone:

```toml
"skills:owner/repo/my-skill" = "v1.0.0"  # not "owner/repo/plugins/<product>/skills/my-skill"
```

```bash
mise bootstrap packages apply
mise bootstrap packages status
```

See the [usage guide](docs/usage.md) for the version selectors (commit SHA, tag,
branch, `latest`), Git-ref and skill-name rules, updating, and removal.

## How it works

The plugin implements four mise hooks (`PackageInstalled`, `PackageInstall`,
`PackageUpgrade`, `PackageUninstall`) that read the skills CLI's global lock,
install or upgrade through the CLI, and gate removal on ownership. `latest`
declarations are resolved to an exact SHA with a read-only `git ls-remote`
before installing. See [How it works](docs/how-it-works.md) for details.

## Known limitations

Before relying on the plugin, review the [known limitations](docs/limitations.md).
In particular:

- **GitHub only** and **HTTPS only** — GitLab/Bitbucket and SSH URLs are not supported.
- **No content verification** — edited file contents are not detected when the pin matches.
- **Mutable selectors** — tags and branches can move upstream; re-declare a name (or SHA) to force a refresh.

## Troubleshooting

See [Troubleshooting](docs/troubleshooting.md) for plugin-not-found, CLI-not-found,
and unsupported-version fixes.

## Development

See [Development](docs/development.md) for testing, CI setup, and repository
layout, and [Preparing a release](docs/release.md) for the release process.

## License

MIT

## Contributing

Contributions are welcome! Please open an issue or PR on GitHub.

## Resources

- [Usage guide](docs/usage.md)
- [How it works](docs/how-it-works.md)
- [Known limitations](docs/limitations.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Development](docs/development.md)
- [Preparing a release](docs/release.md)
- [Changelog](CHANGELOG.md)
- [mise documentation](https://mise.jdx.dev/)
- [Vercel skills CLI](https://github.com/vercel-labs/skills)
- [mise package manager plugin development](https://mise.jdx.dev/package-plugin-development.html)
- [mise Lua runtime reference](https://mise.jdx.dev/plugin-lua-modules.html)
