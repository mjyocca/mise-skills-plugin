# Preparing a release

`version.lua` is the single source for the plugin's release version.
`metadata.lua` loads it with `require("version")`; no generation step or Git
command is needed when mise loads the plugin. This version is separate from
the skills CLI version and the commit SHAs of managed skills.

Merge normal changes into `main` without bumping the version. Between releases,
`main` reports the last declared version; the Git ref identifies the exact
plugin revision. Tag creation and GitHub release publication are manual.

## Prepare the release commit

1. Update the string in `version.lua`, for example from `0.1.0` to `0.2.0`.
   Use a stable `x.y.z` version without the `v` tag prefix.
2. Run `mise run check`, open a release-preparation PR, and merge it into `main`.
3. From the repository root, check out the updated `main`:

   ```bash
   git switch main
   git pull --ff-only
   ```

If other changes have landed since the release-preparation PR, check out its
exact merged commit before continuing. Tag the commit you intend to release,
not a newer `main` tip.

## Tag and publish

With the release commit checked out, verify it and derive the tag from its
version file:

```bash
mise run check
version="$(mise exec -- lua -e 'io.write(require("version"))')"
git tag -a "v$version" -m "Release v$version"
git push origin "v$version"
gh release create "v$version" --verify-tag --generate-notes
```

The tag must match that commit's `version.lua`. Do not move existing release
tags. These commands require push access to the repository and an authenticated
GitHub CLI account with permission to publish releases.
