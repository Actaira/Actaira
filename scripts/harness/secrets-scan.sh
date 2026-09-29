#!/usr/bin/env bash
# Secret scan for `make check`, with the pinned gitleaks binary.
# Usage: scripts/harness/secrets-scan.sh [--config <file>] <gitleaks>
# Run from inside the repo. It scans:
#   1. the git history HEAD reaches (the branch and the main it contains, not
#      every ref) and its commit messages;
#   2. the index (what `git commit` would record right now);
#   3. the working tree: tracked files plus untracked files that are not ignored.
# Ignored files (.env, .tools/, .harness/, worktrees) are local by design and
# are never scanned: `gitleaks dir` alone does not honour .gitignore (F-0002).
#
# Config: --config if given (tests); otherwise gitleaks finds the repo's own
# .gitleaks.toml in the scanned directory, or uses its default rules.
# GITLEAKS_CONFIG and GITLEAKS_CONFIG_TOML outrank that file in gitleaks, so
# they are removed from the environment (F-0005).
#
# Exceptions switch findings off, so each one must be reviewable (F-0006):
#   - .gitleaks.toml and .gitleaksignore must be tracked by git;
#   - .gitleaks.toml must extend the default rules (useDefault = true);
#   - every .gitleaksignore entry has, on the line above, a comment citing an
#     F-NNNN recorded in docs/harness/FALLOS.md;
#   - every line with gitleaks' inline allow marker cites such an F-NNNN.
# Findings are always redacted, with repo-relative paths.
set -euo pipefail
unset GITLEAKS_CONFIG GITLEAKS_CONFIG_TOML
source "$(dirname "${BASH_SOURCE[0]}")/lib-fallos.sh"

usage() {
  echo "uso: $0 [--config <fichero>] <ruta al binario gitleaks fijado>" >&2
  exit 2
}
config=""
if [ "${1:-}" = "--config" ]; then
  [ "$#" -ge 2 ] || usage
  config="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
  shift 2
fi
[ "$#" -eq 1 ] && [ -x "$1" ] || usage
gl="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
root="$(git rev-parse --show-toplevel)"
cd "$root"

# Built in two parts so this script does not contain the marker itself.
allow_marker="gitleaks"":allow"

known_ids="$(fallos_ids)"
bad=0
for f in .gitleaks.toml .gitleaksignore; do
  if [ -e "$f" ] && ! git ls-files --error-unmatch -- "$f" >/dev/null 2>&1; then
    echo "secrets-scan: $f existe pero no está en git; commitéalo para que se revise en el PR, o bórralo" >&2
    bad=1
  fi
done
if [ -f .gitleaks.toml ] && ! grep -Eq '^[[:space:]]*useDefault[[:space:]]*=[[:space:]]*true' .gitleaks.toml; then
  echo "secrets-scan: .gitleaks.toml debe extender las reglas por defecto ([extend] useDefault = true)" >&2
  bad=1
fi
if [ -f .gitleaksignore ]; then
  prev=""
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "" | "#"*) ;;
      *)
        if ! cites_known_fallo "$prev" "$known_ids"; then
          echo "secrets-scan: .gitleaksignore: '$line' no tiene encima un comentario con un F-NNNN de FALLOS.md" >&2
          bad=1
        fi ;;
    esac
    prev="$line"
  done < .gitleaksignore
fi
# Inline allow markers in any file git would commit (tracked or untracked, not ignored).
# git grep: exit 1 means no match; anything above 1 is an error, never "clean".
grc=0
allow_hits="$(git grep -n -I --untracked -F -e "$allow_marker")" || grc=$?
if [ "$grc" -gt 1 ]; then
  echo "secrets-scan: git grep falló (exit $grc) buscando comentarios allow" >&2
  exit 1
fi
while IFS= read -r hit; do
  # The citation must be in the line itself, not in the path of the file.
  if [ -n "$hit" ] && ! cites_known_fallo "$(cut -d: -f3- <<< "$hit")" "$known_ids"; then
    echo "secrets-scan: comentario allow de gitleaks sin un F-NNNN de FALLOS.md en la misma línea: ${hit%%:*}:$(cut -d: -f2 <<< "$hit")" >&2
    bad=1
  fi
done <<< "$allow_hits"
if [ "$bad" -ne 0 ]; then exit 1; fi

flags=(--no-banner --redact --verbose --log-level warn --gitleaks-ignore-path "$root")
if [ -n "$config" ]; then flags+=(--config "$config"); fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/messages" "$tmp/tree"

# History HEAD reaches (this branch and the main it contains), not every ref:
# a finding on an abandoned branch must not turn every later check red. Commit
# messages too: a token in one would enter main, where it cannot be rewritten
# (E0 closing review).
if git rev-parse -q --verify HEAD >/dev/null; then
  "$gl" git "${flags[@]}" --log-opts=HEAD .
  # Oldest first: a finding keeps its line, so its fingerprint stays stable.
  git log --reverse --format='commit %H%n%B' HEAD > "$tmp/messages/commit-messages.txt"
  # Scanned outside the repo, so the repo's own config is passed explicitly.
  msg_flags=("${flags[@]}")
  if [ -z "$config" ] && [ -f .gitleaks.toml ]; then msg_flags+=(--config "$root/.gitleaks.toml"); fi
  (cd "$tmp/messages" && "$gl" dir "${msg_flags[@]}" .)
fi
"$gl" git --staged "${flags[@]}" .

git ls-files -z --cached --others --exclude-standard |
  while IFS= read -r -d '' f; do
    # Only files and symlinks: nested repos and submodules are listed as
    # directories and belong to another repo; deleted files have nothing left.
    if [ -f "$f" ] || [ -L "$f" ]; then printf '%s\0' "$f"; fi
  done |
  tar --null --no-recursion -T - -cf - |
  tar -xf - -C "$tmp/tree"
(cd "$tmp/tree" && "$gl" dir "${flags[@]}" .)
