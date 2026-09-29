#!/usr/bin/env bash
# Compares the live branch protection of main on GitHub with the one the repo
# asks for (docs/estado/branch-protection.json, or the file given). That
# protection is the security boundary of main (ADR 0000, L-005), so it is
# checked in step 0.4 of E0 and at every epic closing. Needs gh with read
# access to the repo administration, which the GITHUB_TOKEN of the CI lacks.
# The repo is the GitHub repo of the origin remote of the current directory
# (the one a push goes to), or the one given with --repo.
# API: https://docs.github.com/en/rest/branches/branch-protection#get-branch-protection
# Usage: scripts/harness/check-protection.sh [--repo owner/name] [expected-json]
set -euo pipefail
repo=""
if [ "${1:-}" = "--repo" ]; then
  repo="${2:?falta owner/name tras --repo}"
  shift 2
fi
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
expected_file="${1:-$repo_dir/docs/estado/branch-protection.json}"
if [ ! -f "$expected_file" ]; then
  echo "check-protection: no existe $expected_file" >&2
  exit 1
fi
if [ -z "$repo" ]; then
  url="$(git remote get-url origin 2>/dev/null)" || url=""
  if [[ "$url" =~ github\.com[:/]([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)$ ]]; then
    repo="${BASH_REMATCH[1]}/${BASH_REMATCH[2]%.git}"
  else
    echo "check-protection: origin (${url:-sin remoto}) no es un repo de GitHub; usa --repo owner/name" >&2
    exit 1
  fi
fi

# One shape for both sides: the PUT body gives booleans where the GET answers
# {"enabled": bool} ($live). The check must come from its app (app_id), and
# nobody may skip the pull request (bypass allowances).
normalize='def flag(f): if $live then (f | .enabled) else f end;
{
  required_checks: ([.required_status_checks.checks[]? | {context, app_id}] | sort_by(.context)),
  strict: .required_status_checks.strict,
  enforce_admins: flag(.enforce_admins),
  pull_request_reviews: (.required_pull_request_reviews | if . == null then null else {approvals: .required_approving_review_count, dismiss_stale_reviews, require_code_owner_reviews} end),
  pull_request_bypass: ((.required_pull_request_reviews.bypass_pull_request_allowances // {}) | [.users[]?, .teams[]?, .apps[]?] | length),
  allow_force_pushes: flag(.allow_force_pushes),
  allow_deletions: flag(.allow_deletions),
  restrictions: .restrictions
}'
expected="$(jq -S --argjson live false "$normalize" "$expected_file")"

if ! raw="$(gh api "repos/$repo/branches/main/protection")"; then
  echo "check-protection: main de $repo no está protegida o no se puede leer su protección" >&2
  exit 1
fi
live="$(jq -S --argjson live true "$normalize" <<< "$raw")"

if [ "$live" = "$expected" ]; then
  echo "protección de main en $repo: OK $(jq -c . <<< "$live")"
  exit 0
fi
echo "check-protection: la protección de main en $repo no es la de $expected_file:" >&2
jq -rn --argjson e "$expected" --argjson l "$live" \
  '$e | keys[] as $k | select($e[$k] != $l[$k]) |
   "  \($k): esperado \($e[$k] | tojson), en GitHub \($l[$k] | tojson)"' >&2
exit 1
