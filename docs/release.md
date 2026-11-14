# Preparing a release

`version.lua` is the single source for the plugin's release version.
`metadata.lua` loads it with `require("version")`; no generation step or Git
command is needed when mise loads the plugin. This version is separate from
the skills CLI version and the commit SHAs of managed skills.

Merge normal changes into `main` without bumping the version. Between releases,
`main` reports the last declared version; the Git ref identifies the exact
plugin revision.

The **Prepare release** action validates a commit, creates its version tag, and
opens a draft GitHub release. You review the notes and publish the draft yourself.

**The tag becomes public as soon as the action creates it.** Users can install
that tag before you publish the release, but only after all validation passes.

## Before you start

- Merge `.github/workflows/release.yml` and its shared setup and test files into
  `main` so the workflow is available in the Actions UI.
- Sign in as the repository owner. The workflow accepts runs and reruns only
  from the owner, with `main` selected.
- Ensure repository or organization policy allows the final job to use
  `contents: write` and create release tags. Validation runs with read-only
  permissions. The workflow uses `GITHUB_TOKEN`; it does not need a personal
  access token or an environment approval.

## Prepare and validate

1. Update the string in `version.lua`, for example from `0.1.0` to `0.2.0`,
   and add a matching entry to `CHANGELOG.md`. Use a stable `x.y.z` version
   without leading zeros or the `v` tag prefix.
2. Run `mise run check`, open a release-preparation PR, and merge it into `main`.
3. Open **Actions → Prepare release → Run workflow**. Select **main**, then
   click **Run workflow**. There is no version input: the action reads
   `version.lua` from the selected commit.
4. Wait for both jobs to succeed. Open the **prepare** job's summary and follow
   **Review and publish the draft**.

The **validate** job checks the version format and looks for an existing tag or
release. It then runs the offline checks and the minimum/latest skills CLI
tests, using one shared setup. Both compatibility suites must pass.

Only after validation succeeds does **prepare** receive write permission. It
checks again for matching tags and releases, including drafts. If none exist,
it creates `v<version>` at the exact validated SHA and creates a draft with
generated release notes. It does not check out or execute repository code with
the write token. If `main` advances while tests run, the workflow still uses
the original commit.

Only one preparation run executes at a time. A run from another branch or
account is skipped. Existing tags and releases are never overwritten.

## Review and publish

1. In the draft, confirm the tag and review the generated release notes.
2. Edit the title and notes as needed. Do not change the validated tag or target.
3. Click **Publish release** when you are ready to announce it.

Use the draft created by the action rather than **Releases → Create a new
release**. Publishing is the final human step; the action never publishes for
you. It does not bump `version.lua` or create a release-preparation PR.

## If preparation fails

- **Validation or tests failed:** no tag or draft is created by that run. Fix
  the problem through a PR and start a new run from the updated `main`.
- **A tag or release already exists:** inspect it under **Releases** and **Tags**.
  If it is the intended draft from a successful run, review that draft rather
  than rerunning preparation. For a new release, choose a new version.
- **The tag was created but draft creation failed:** the tag is already public
  and is not deleted automatically. Check the run's validated SHA against the
  tag. If they match and all validation passed, use **Releases → Create a new
  release**, select that existing tag, and **Save draft**. Review and publish it
  as above. Do not create a replacement tag or move the existing one.

GitHub policy or tag rules can reject the write job even after validation
succeeds. Inspect the error before retrying; do not broaden the validation
job's token permissions. Changes to workflow files on `main` during a run may
also cause GitHub to reject releasing the older commit with `GITHUB_TOKEN`.
In that case, inspect any existing tag before starting a new run from the
updated `main`.

## Manual CLI alternative

This bypasses the action's validation and concurrency guard. Use it only when
you deliberately need a manual release. From a clean checkout of the intended
release commit, run `mise run check` and the
[real-CLI compatibility tests](../README.md#testing) with both skills 1.7.6 and
latest. Then create the tag and draft. These commands require push access and
an authenticated GitHub CLI account with permission to create releases. Stop
if any command fails.

```bash
version="$(mise exec -- lua -e 'io.write(require("version"))')"
git tag -a "v$version" -m "Release v$version"
git push origin "v$version"
gh release create "v$version" --draft --verify-tag --generate-notes
```

Review and publish the draft in GitHub. The tag must match the checked-out
commit's `version.lua`; do not move existing release tags.
