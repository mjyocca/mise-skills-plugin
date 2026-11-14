#!/usr/bin/env bash
set -euo pipefail

# Resolve and validate every executable before starting background test suites.
jq -e 'type == "object" and length > 0 and all(.[]; type == "string")' \
  <<< "${SKILLS_CLI_BINS:?Setup must provide the CLI paths}" > /dev/null
versions=()
binaries=()
while IFS= read -r version; do
  [[ "$version" =~ ^[A-Za-z0-9][A-Za-z0-9.+-]*$ ]] || {
    printf 'Invalid version label: %s\n' "$version" >&2
    exit 1
  }
  binary="$(jq -er --arg version "$version" '.[$version]' <<< "$SKILLS_CLI_BINS")"
  [[ "$binary" == /* && -x "$binary" ]] || {
    printf 'Missing executable for skills %s: %s\n' "$version" "$binary" >&2
    exit 1
  }
  versions+=("$version")
  binaries+=("$binary")
done < <(jq -r 'keys[]' <<< "$SKILLS_CLI_BINS")

log_dir="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/skills-compat.XXXXXX")"
pids=()
for i in "${!versions[@]}"; do
  SKILLS_CLI_TEST_BIN="${binaries[$i]}" mise run test:compat > "$log_dir/$i.log" 2>&1 &
  pids+=("$!")
done

summary="$log_dir/summary.md"
printf '## Skills CLI compatibility\n\n| Version | Result |\n| --- | --- |\n' > "$summary"
failed=0
for i in "${!versions[@]}"; do
  status=0
  wait "${pids[$i]}" || status=$?
  printf '::group::skills %s (exit %s)\n' "${versions[$i]}" "$status"
  cat "$log_dir/$i.log"
  printf '::endgroup::\n'
  if [[ "$status" -eq 0 ]]; then
    result=passed
  else
    result="failed (exit $status)"
    failed=1
  fi
  printf '| %s | %s |\n' "${versions[$i]}" "$result" >> "$summary"
done

cat "$summary"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  cat "$summary" >> "$GITHUB_STEP_SUMMARY"
fi
exit "$failed"
