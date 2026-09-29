#!/usr/bin/env bash
# Squash-merges a PR only after checking what enters main without passing
# through CI (F-0009): the squash commit message and the PR title and body must
# carry no Claude attribution and no secret (gitleaks), the checks must be
# green, and the merged head must be the one that was checked; afterwards, the
# commit GitHub wrote into main is checked too.
# Usage: scripts/harness/merge-pr.sh [--sin-ci] <pr> <subject> <body-file>
#   --sin-ci  only before the CI exists (E0 steps 0.1 to 0.3): skips the checks.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

sin_ci=0
if [ "${1:-}" = "--sin-ci" ]; then
  sin_ci=1
  shift
fi
if [ "$#" -ne 3 ] || [ ! -f "$3" ]; then
  echo "uso: $0 [--sin-ci] <pr> <asunto> <fichero con el cuerpo>" >&2
  exit 2
fi
pr="$1"; subject="$2"; body="$3"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# The squash commit message, exactly as it will enter main.
{ printf '%s\n\n' "$subject"; cat "$body"; } > "$work/squash-msg"
"$here/check-attribution.sh" --message "$work/squash-msg"

# The PR itself.
gh pr view "$pr" --json title,body,headRefOid > "$work/pr.json"
jq -r '.title + "\n\n" + .body' "$work/pr.json" > "$work/pr-msg"
"$here/check-attribution.sh" --message "$work/pr-msg"
head="$(jq -r .headRefOid "$work/pr.json")"

# Secrets in what enters main without CI, the squash message, and in the PR
# text (E0 closing review): the pinned gitleaks of `make tools`, with the
# repo's own .gitleaks.toml if there is one. Without gitleaks, no merge.
root="$(git rev-parse --show-toplevel 2>/dev/null)" || root="$PWD"
version="$(sed -n 's/^GITLEAKS_VERSION[[:space:]]*:=[[:space:]]*//p' "$root/Makefile" 2>/dev/null)" || version=""
gl="${GITLEAKS:-.tools/gitleaks-$version}"
case "$gl" in /*) ;; *) gl="$root/$gl" ;; esac
if [ ! -x "$gl" ]; then
  echo "merge-pr: falta el gitleaks fijado ($gl); ejecuta make tools" >&2
  exit 1
fi
mkdir "$work/texts"
cp "$work/squash-msg" "$work/pr-msg" "$work/texts/"
gl_args=(dir --no-banner --redact --log-level warn)
if [ -f "$root/.gitleaks.toml" ]; then gl_args+=(--config "$root/.gitleaks.toml"); fi
# The environment must not replace the config (F-0005, as in secrets-scan.sh).
if ! (cd "$work/texts" && unset GITLEAKS_CONFIG GITLEAKS_CONFIG_TOML && "$gl" "${gl_args[@]}" .); then
  echo "merge-pr: el mensaje del squash o el texto del PR contienen un secreto; no se fusiona" >&2
  exit 1
fi
# Nothing personal either (CLAUDE.md, rule 4; F-0015): main cannot be rewritten.
if ! "$here/check-personal.sh" --files "$work/squash-msg" "$work/pr-msg"; then
  echo "merge-pr: el mensaje del squash o el texto del PR llevan datos personales; no se fusiona" >&2
  exit 1
fi

if [ "$sin_ci" -eq 0 ]; then
  gh pr checks "$pr" --watch --fail-fast
fi
# GitHub signs a merge with the account's primary e-mail unless it is told
# otherwise; main is public and cannot be rewritten (F-0015).
author_email="$(gh api user --jq '"\(.id)+\(.login)@users.noreply.github.com"')"
gh pr merge "$pr" --squash --delete-branch --match-head-commit "$head" --subject "$subject" --body-file "$body" \
  --author-email "$author_email"

# What actually entered main, as GitHub wrote it: it cannot be undone without
# rewriting main, but it must never go unnoticed.
merged="$(gh pr view "$pr" --json mergeCommit --jq .mergeCommit.oid)"
gh api "repos/{owner}/{repo}/commits/$merged" --jq .commit.message > "$work/merged-msg"
if ! "$here/check-attribution.sh" --message "$work/merged-msg"; then
  echo "merge-pr: el commit $merged que entró en main lleva atribución de Claude; avisa a Marcos" >&2
  exit 1
fi
merged_email="$(gh api "repos/{owner}/{repo}/commits/$merged" --jq .commit.author.email)"
if [ "$merged_email" != "$author_email" ]; then
  echo "merge-pr: el commit $merged entró en main con el correo de autor $merged_email, no con $author_email; avisa a Marcos" >&2
  exit 1
fi
