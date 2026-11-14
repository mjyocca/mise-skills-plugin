# Known limitations

- **No content verification or forced reinstall**: Missing targets or entrypoints are repaired by `apply`, but edited file contents are not detected when the pin matches
- **Mutable selectors**: Tags and branches can be moved upstream. The lock records the declared name, so the plugin cannot detect a moved tag without re-fetching it; re-declare a different name (or a SHA) to force the refresh. `latest` tracks the default branch only
- **`latest` refresh requires `upgrade`**: mise treats an installed "any version" declaration as satisfied, so `apply` will not re-resolve it. Also, resolving `latest` needs Git and network access at plan time; offline runs fail resolution instead of guessing
- **Shared-agent removal**: The CLI can retain canonical content used by another agent; prune reports incomplete removal rather than force-deleting it
- **Lock-only leftovers**: The removal hook handles a tracked entry with missing files when supplied, but mise may already consider it missing and not call the hook; review stale entries with the skills CLI
- **Unpinned CLI arguments mean latest**: mise delivers explicit `apply skills:owner/repo/skill` arguments without a version, which this plugin treats as `latest` — even when the configuration declares a SHA or tag. Prefer declarations and `--manager skills` for predictable pins
- **CLI contract compatibility**: Versions at or above 1.7.6 pass the version gate, but breaking changes to command flags, JSON output, or lock schema still require adapter updates
- **GitHub only**: Currently only supports GitHub repositories (no GitLab, Bitbucket, etc.)
- **HTTPS only**: Only supports HTTPS GitHub URLs (no SSH)
