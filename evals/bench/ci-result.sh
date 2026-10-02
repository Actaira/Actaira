#!/usr/bin/env bash
# Writes, as JSON, the result of the CI for one commit: every check run (the
# jobs of ci.yml and platforms.yml) with its conclusion and URL. ADR 0003 cites
# it for whether the code compiles and passes its tests on Linux and on macOS.
# Needs gh with read access to the repository of origin.
# Usage: bash evals/bench/ci-result.sh <commit> > evals/results/<date>-ci-<commit>.json
set -euo pipefail
commit="${1:?falta el commit}"
repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
runs="$(gh api "repos/$repo/commits/$commit/check-runs" \
  --jq '[.check_runs[] | {job: .name, status, conclusion, url: .html_url}] | sort_by(.job)')"
jq -n --arg date "$(date -u +%FT%TZ)" --arg repo "$repo" --arg commit "$commit" --argjson runs "$runs" \
  '{date: $date, repo: $repo, commit: $commit, command: "bash evals/bench/ci-result.sh <commit>", runs: $runs}'
