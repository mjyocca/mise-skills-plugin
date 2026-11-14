# Usage

## Declare a skill

Add skills to your `[bootstrap.packages]` section:

```toml
[bootstrap.packages]
# Format: "skills:<owner>/<repo>/<skill-id>" = "<version>"
# Reproducible: full commit SHA
"skills:vercel-labs/skills/find-skills" = "7a5e920bead4b1039a6d6df5d7e1163b7b09423a"
# Semi-stable: a published Git tag (or branch) name
"skills:vercel-labs/agent-skills/web-design-guidelines" = "v1.2.3"
# Moving: the repository's default-branch tip
"skills:vercel-labs/agent-skills/frontend-design" = "latest"
```

The package name format is:
- `skills:` - Plugin prefix (required)
- `<owner>/<repo>` - GitHub repository
- `<skill-id>` - Exact canonical skill name, not its path in the repository

The version selector is one of:

| Selector | Behavior | Recorded lock ref |
| --- | --- | --- |
| Full 40-character lowercase commit SHA | Installs that exact immutable commit | The SHA |
| Git tag or branch name | Installs whatever the remote holds under that name | The name you declared |
| `"latest"` | Installs the default-branch tip resolved at apply time | The resolved commit SHA |

mise parses a declared `"latest"` to an absent version, so omitted selectors and
explicit CLI arguments such as `apply skills:owner/repo/skill` also behave as
`latest`. Ref names must satisfy the plugin's conservative Git ref rules: only
letters, digits, `.`, `_`, `-`, `+`, and `/`; no leading `-` or `.`; no `..`,
`//`, `@`, path components starting with `.`, or components ending in `.lock`;
at most 255 characters. Hex strings of SHA-like length (32 or more characters)
must be exactly 40 lowercase characters, so truncated or uppercase commit SHAs
are rejected rather than mistaken for ref names.

Skill IDs must start with a lowercase letter or digit, contain only lowercase
letters, digits, `.`, `_`, and `-`, and not end in a dot or hyphen. They must
already match the CLI's lock key and directory name: aliases, mixed-case names,
plugin-qualified names, wildcard selectors, and nested paths are unsupported.
Two repositories cannot declare the same skill ID because the CLI shares one
global lock key and directory for that ID.

## Install declared skills

```bash
mise bootstrap packages apply
```

This installs any missing or outdated skills.

## Check status

```bash
mise bootstrap packages status
```

Shows installed skills, the refs recorded in the lock (resolved SHAs for
`latest` declarations), and any mismatches.

## Update a skill

How an update happens depends on the selector:

- **Commit SHA**: Replace the value with the new full lowercase SHA, then run
  `mise bootstrap packages apply`. The plugin detects the pin change and
  reinstalls the skill.
- **Git tag or branch**: Change the declared name (for example `v1.2.3` to
  `v1.3.0`) and run `apply`. Re-declaring the same name does not re-fetch it:
  if someone moves the tag upstream, the plugin and the lock keep the name, so
  the installed content stays put until you declare a different SHA, tag, or
  branch.
- **`latest`**: Run `mise bootstrap packages upgrade --manager skills`. The
  plugin resolves the repository's current default-branch HEAD and reinstalls
  only when it differs from the recorded SHA. `apply` treats an already
  installed `latest` skill as satisfied and never re-resolves it; mise's
  "latest" declarations intentionally mean "any version".

`mise bootstrap packages upgrade --manager skills` also installs changed pins
for SHA and tag declarations, skipping already-current ones. Neither `upgrade`
nor `apply --update` is a force-reinstall operation; this manager has no
metadata cache to refresh.

Preview changes with `mise bootstrap packages apply --dry-run` or
`mise bootstrap packages upgrade --dry-run`. Previews of `latest` declarations
resolve the remote HEAD read-only so the prediction is accurate; they still
never invoke the skills CLI.

## Remove a skill

Remove the declaration from your configuration, then:

```bash
mise bootstrap packages prune --manager skills
```

This removes no-longer-declared skills that **mise installed itself**, subject to
mise's ownership tracking across trusted configurations. Pre-existing skills
are not adopted for pruning. Use `--dry-run` to preview removals.
