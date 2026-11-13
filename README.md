# mise-skills-plugin

A [mise](https://mise.jdx.dev/) package manager plugin for declarative external skill management via the [Vercel skills CLI](https://github.com/vercel-labs/skills).

## What it does

This plugin enables you to declare external agent skills in your mise configuration and have mise automatically install, update, and remove them using the Vercel skills CLI.

**Before** (manual management):
```bash
# Manually run CLI commands
skills add "https://github.com/owner/repo.git#abc123" \
  --skill my-skill \
  --global --agent codex --copy --yes
```

**After** (declarative):
```toml
# .config/mise/config.toml
[bootstrap.plugins]
skills = "https://github.com/your-username/mise-skills-plugin"

[bootstrap.packages]
"skills:owner/repo/my-skill" = "abc123def456..."

[tools]
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
- **Conflict detection**: Validates source, revision, and file integrity
- **Lock file integration**: Reads the Vercel skills CLI's global lock

## Prerequisites

- [mise](https://mise.jdx.dev/) (v2026.10.25 or later)
- Node.js (for the Vercel skills CLI)
- The Vercel skills CLI (installed via mise)

## Installation

### 1. Add the plugin to your mise configuration

```toml
# .config/mise/config.toml
[bootstrap.plugins]
skills = "https://github.com/your-username/mise-skills-plugin"
```

Or use a specific version:
```toml
[bootstrap.plugins]
skills = "https://github.com/your-username/mise-skills-plugin#v1.0.0"
```

### 2. Install the Vercel skills CLI

```toml
[tools]
"npm:skills" = "1.7.6"
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
"skills:mattpocock/skills/grilling" = "4ae2317ddb22b046e26455e4f9c9b3aaaf62212d"
"skills:mattpocock/skills/teach" = "4ae2317ddb22b046e26455e4f9c9b3aaaf62212d"
```

The package name format is:
- `skills:` - Plugin prefix (required)
- `<owner>/<repo>` - GitHub repository
- `<skill-id>` - Skill name within the repository
- `<commit-sha>` - Full 40-character Git commit SHA

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
"skills:mattpocock/skills/grilling" = "new-sha-here..."
```

Then apply:

```bash
mise bootstrap packages apply
```

The plugin detects the version change and reinstalls the skill.

### Remove a skill

Remove the declaration from your configuration, then:

```bash
mise bootstrap packages prune
```

This removes skills that are no longer declared.

## How it works

The plugin implements four mise hooks:

1. **PackageInstalled** - Checks if a skill is already installed by reading the Vercel skills CLI's global lock file
2. **PackageInstall** - Installs missing or outdated skills via the skills CLI
3. **PackageUpgrade** - Handles version changes when you update a commit SHA
4. **PackageUninstall** - Removes skills when they're pruned

### CLI invocation

The plugin invokes the Vercel skills CLI directly at:
```
$MISE_DATA_DIR/installs/npm-skills/1.7.6/node_modules/.bin/skills
```

This bypasses mise shims (which don't work from hooks) and ensures the exact pinned version is used.

### Lock file location

The plugin reads the Vercel skills CLI's global lock file from:
- `$XDG_STATE_HOME/skills/.skill-lock.json` (if set), or
- `~/.agents/.skill-lock.json` (default)

This is the same location the skills CLI uses, ensuring compatibility.

## Known limitations

- **Dry-run doesn't prevent side effects**: mise calls hooks even during `--dry-run`, so skills may be installed when you only want to preview
- **No forced reinstall**: `mise bootstrap packages apply` won't reinstall a skill if the commit SHA matches, even if files are corrupted
- **Direct invocation only**: The plugin must invoke the skills CLI directly; mise shims don't work from hooks
- **GitHub only**: Currently only supports GitHub repositories (no GitLab, Bitbucket, etc.)
- **HTTPS only**: Only supports HTTPS GitHub URLs (no SSH)

## Development

### Testing

The plugin requires a git repository to work with mise. To test locally:

```bash
git init
git add .
git commit -m "Initial commit"
```

Then reference it in your mise config:
```toml
[bootstrap.plugins]
skills = "/path/to/mise-skills-plugin"
```

### Plugin structure

```
mise-skills-plugin/
├── metadata.lua              # Plugin metadata
├── mise.plugin.toml          # Plugin configuration
├── hooks/
│   ├── package_installed.lua   # Status check hook
│   ├── package_install.lua     # Installation hook
│   ├── package_upgrade.lua     # Upgrade hook
│   └── package_uninstall.lua   # Removal hook
└── lib/
    └── shared.lua              # Shared utilities
```

## Troubleshooting

### Plugin not found

Make sure the plugin directory is a git repository:
```bash
cd /path/to/mise-skills-plugin
git init
git add .
git commit -m "Initial commit"
```

### Skills CLI not found

Ensure you've installed the Vercel skills CLI via mise:
```toml
[tools]
"npm:skills" = "1.7.6"
```

Then run:
```bash
mise install
```

### Permission denied

The plugin needs to execute the skills CLI binary. Ensure it's executable:
```bash
chmod +x $MISE_DATA_DIR/installs/npm-skills/1.7.6/node_modules/.bin/skills
```

## License

MIT

## Contributing

Contributions are welcome! Please open an issue or PR on GitHub.

## Resources

- [mise documentation](https://mise.jdx.dev/)
- [Vercel skills CLI](https://github.com/vercel-labs/skills)
- [mise package manager plugins](https://mise.jdx.dev/package-plugins.html)
