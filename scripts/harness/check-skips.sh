#!/usr/bin/env bash
# A skipped Go test switches a check off, so it must be justified (CLAUDE.md:
# no skipped tests without a FALLOS.md entry; L-003):
#   - every line that uses Skip, SkipNow or Skipf (called or as a value) in a
#     *_test.go file, or in any .go file that imports "testing" (test helpers
#     such as a RequireDocker(t)), cites in the code of that line an F-NNNN
#     recorded in docs/harness/FALLOS.md;
#   - a *_test.go file that the required check never compiles (go test ./...,
#     no tags, on linux/amd64: an unknown or unset tag, a condition never
#     true, another GOOS or GOARCH) cites such an F-NNNN in a comment before
#     its package clause. The build is judged for linux/amd64 on every system,
#     so a test for Linux only is not flagged by a job on macOS.
#   - every //nolint names its linters and cites such an F-NNNN on its line.
# testdata/ holds fixtures of analysed repos, not code of this module.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib-fallos.sh"
root="$(git rev-parse --show-toplevel)"
cd "$root"

known="$(fallos_ids)"
bad=0

# git grep: exit 1 means no match; anything above 1 is an error, never "clean".
grc=0
hits="$(git grep -n -I --untracked -E '\.Skip(Now|f)?([^[:alnum:]_]|$)' -- '*.go' ':(exclude,glob)**/testdata/**')" || grc=$?
if [ "$grc" -gt 1 ]; then
  echo "check-skips: git grep falló (exit $grc)" >&2
  exit 1
fi
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  file="$(cut -d: -f1 <<< "$hit")"
  # Outside test files, only code that imports "testing" can skip a test.
  case "$file" in
    *_test.go) ;;
    *) grep -qE '^[[:space:]]*(import[[:space:]]+)?"testing"' "$file" || continue ;;
  esac
  if ! cites_known_fallo "$(cut -d: -f3- <<< "$hit")" "$known"; then
    echo "check-skips: test saltado sin un F-NNNN de FALLOS.md en esa línea: $(cut -d: -f1,2 <<< "$hit")" >&2
    bad=1
  fi
done <<< "$hits"

# //nolint switches golangci-lint off for a line (L-003). golangci-lint strips
# the slashes and spaces before "nolint" and reads the linter names in any case
# (F-0020), so every such comment is looked at: it has to be written exactly
# //nolint:<linter>[,<linter>...] (lowercase names, never "all"), and cite a
# recorded F-NNNN on that line.
grc=0
hits="$(git grep -n -I -i --untracked -E '//[/[:space:]]*nolint' -- '*.go' ':(exclude,glob)**/testdata/**')" || grc=$?
if [ "$grc" -gt 1 ]; then
  echo "check-skips: git grep falló (exit $grc)" >&2
  exit 1
fi
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  where="$(cut -d: -f1,2 <<< "$hit")"
  text="$(cut -d: -f3- <<< "$hit")"
  problem=""
  if directives="$(grep -oiE '//[/[:space:]]*nolint[^[:space:]]*' <<< "$text")"; then
    while IFS= read -r d; do
      if [[ ! "$d" =~ ^//nolint:[a-z0-9_-]+(,[a-z0-9_-]+)*$ ]]; then
        problem="//nolint mal escrito (golangci-lint lo aplica igual; se escribe //nolint:<linter> // F-NNNN)"
      elif [[ ",${d#//nolint:}," == *",all,"* ]]; then
        problem="//nolint sin nombrar su linter"
      fi
    done <<< "$directives"
  fi
  if [ -z "$problem" ] && ! cites_known_fallo "$text" "$known"; then
    problem="//nolint sin un F-NNNN de FALLOS.md en esa línea"
  fi
  if [ -n "$problem" ]; then
    echo "check-skips: $problem: $where" >&2
    bad=1
  fi
done <<< "$hits"

# Test files the required check (make check in ci.yml, on ubuntu-latest, amd64,
# with a C compiler) never compiles.
if [ -f go.mod ]; then
  ignored="$(GOOS=linux GOARCH=amd64 CGO_ENABLED=1 \
    go list -e -f '{{$d := .Dir}}{{range .IgnoredGoFiles}}{{$d}}/{{.}}{{"\n"}}{{end}}' ./...)"
  while IFS= read -r file; do
    case "$file" in *_test.go) ;; *) continue ;; esac
    header="$(awk '/^package[[:space:]]/ {exit} {print}' "$file")"
    if ! cites_known_fallo "$header" "$known"; then
      echo "check-skips: test que make check nunca compila, sin un F-NNNN de FALLOS.md en su cabecera: ${file#"$root"/}" >&2
      bad=1
    fi
  done <<< "$ignored"
fi
exit "$bad"
