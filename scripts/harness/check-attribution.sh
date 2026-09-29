#!/usr/bin/env bash
# No commit carries Claude co-authorship or attribution (Marcos, 2026-09-28).
# Usage:
#   scripts/harness/check-attribution.sh                 the commits of this branch
#   scripts/harness/check-attribution.sh --message <f>   one message (squash message,
#                                                        PR title and body)
# Only what can still be fixed is checked: the commits not yet in origin/main
# (all of HEAD when there is no origin/main). The squash message, which enters
# main without passing through CI, is checked by scripts/harness/merge-pr.sh
# before merging (F-0009).
set -euo pipefail

# The real attribution forms, in any letter case, also quoted or commented
# (#, >, *, -): a Co-authored-by trailer for Claude the model (plain "Claude"
# or with a model name) or any Anthropic address, any trailer with Anthropic's
# noreply address, and Claude Code's "Generated with [Claude Code]" footer.
# Text that only mentions Claude is fine: Actaira analyses Claude
# configurations. The same pattern is in scripts/harness/commit-msg; a test
# keeps them equal.
pattern='^[[:space:]#>*-]*co-authored-by:[[:space:]]*(claude([[:space:]]+(code|opus|sonnet|haiku|fable|[0-9.]+)[^<]*)?[[:space:]]*<|.*anthropic)|^[[:space:]#>*-]*[a-z-]+:.*noreply@anthropic\.com|generated with \[claude code\]'

usage() {
  echo "uso: $0 [--message <fichero con el mensaje>]" >&2
  exit 2
}

if [ "${1:-}" = "--message" ]; then
  [ "$#" -eq 2 ] && [ -f "$2" ] || usage
  # Every line counts: git keeps lines starting with # when the message comes from -m or -F.
  if grep -qiE -- "$pattern" "$2"; then
    echo "check-attribution: el mensaje lleva atribución de Claude (coautoría o 'Generated with'); quítala" >&2
    exit 1
  fi
  exit 0
fi
[ "$#" -eq 0 ] || usage

if [ "$(git rev-parse --is-shallow-repository)" = true ]; then
  echo "check-attribution: clon superficial; hace falta la historia completa (en la CI, fetch-depth: 0)" >&2
  exit 1
fi
# A repo without commits has nothing to check.
if ! git rev-parse --verify -q HEAD >/dev/null; then exit 0; fi
range=HEAD
if git rev-parse --verify -q refs/remotes/origin/main >/dev/null; then range=refs/remotes/origin/main..HEAD; fi

bad=0
hits="$(git log -i -E --grep="$pattern" --format='%h %s' "$range")"
if [ -n "$hits" ]; then
  echo "check-attribution: commits con atribución de Claude en el mensaje (coautoría o 'Generated with'):" >&2
  sed 's/^/  /' <<< "$hits" >&2
  bad=1
fi
# Commits whose author or committer is Claude itself, not a person called Claude.
ids="$(git log --format='%h%x09%an%x09%ae%x09%cn%x09%ce' "$range" | awk -F'\t' '
  function claude(n) { n = tolower(n); return n ~ /^claude( (code|opus|sonnet|haiku|fable|[0-9.]+).*)?$/ }
  function anthropic(m) { return tolower(m) ~ /@anthropic\.com$/ }
  claude($2) || anthropic($3) || claude($4) || anthropic($5) { print $1 " " $2 " <" $3 ">" }')"
if [ -n "$ids" ]; then
  echo "check-attribution: commits con Claude como autor o committer:" >&2
  sed 's/^/  /' <<< "$ids" >&2
  bad=1
fi
exit "$bad"
