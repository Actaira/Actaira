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
# It is a net against switching a check off by accident (L-003, L-013), and it
# reads git's view of the files. What that view could hide is refused outright
# by a white list (F-0021): a .go that is a symbolic link, a path to a .go
# outside [A-Za-z0-9._/-], and any //line directive.
# testdata/ holds fixtures of analysed repos, not code of this module.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib-fallos.sh"
root="$(git rev-parse --show-toplevel)"
cd "$root"

known="$(fallos_ids)"
bad=0

# The white list (F-0021). A symbolic link: git grep reads the link, go and
# golangci-lint read its target. Other characters: git quotes them or they
# break the "path:line:text" of git grep.
while IFS= read -r -d '' file; do
  case "$file" in testdata/* | */testdata/*) continue ;; esac
  if [ -L "$file" ]; then
    echo "check-skips: un .go que es un enlace simbólico: $file" >&2
    bad=1
  fi
  # The letters are spelled out: a range such as A-Z depends on the locale.
  if [[ ! "$file" =~ ^[ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/-]+$ ]]; then
    echo "check-skips: la ruta de un .go tiene caracteres fuera de [A-Za-z0-9._/-]: $file" >&2
    bad=1
  fi
done < <(git ls-files -z --cached --others --exclude-standard -- '*.go')

# A //line directive to a file that is not Go switches linters off on the
# code after it (F-0021); there is no generated code that needs one.
grc=0
hits="$(git grep -n --text --untracked -E '//line[[:space:]]|/\*line[[:space:]]' -- '*.go' ':(exclude,glob)**/testdata/**')" || grc=$?
if [ "$grc" -gt 1 ]; then
  echo "check-skips: git grep falló (exit $grc)" >&2
  exit 1
fi
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  echo "check-skips: directiva //line (apaga linters en el código que la sigue): $(cut -d: -f1,2 <<< "$hit")" >&2
  bad=1
done <<< "$hits"

# git grep: exit 1 means no match; anything above 1 is an error, never "clean".
grc=0
hits="$(git grep -n --text --untracked -E '\.Skip(Now|f)?([^[:alnum:]_]|$)' -- '*.go' ':(exclude,glob)**/testdata/**')" || grc=$?
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
    *)
      # With or without a name for the import (F-0021: import tb "testing").
      irc=0
      grep -qE '^[[:space:]]*(import[[:space:]]+)?([._[:alnum:]]+[[:space:]]+)?"testing"' "$file" || irc=$?
      if [ "$irc" -gt 1 ]; then
        echo "check-skips: no se pudo leer $file" >&2
        exit 1
      fi
      [ "$irc" -eq 0 ] || continue
      ;;
  esac
  if ! cites_known_fallo "$(cut -d: -f3- <<< "$hit")" "$known"; then
    echo "check-skips: test saltado sin un F-NNNN de FALLOS.md en esa línea: $(cut -d: -f1,2 <<< "$hit")" >&2
    bad=1
  fi
done <<< "$hits"

# //nolint switches golangci-lint off for a line (L-003). golangci-lint strips
# the slashes and spaces before "nolint", reads the linter list up to the next
# "//" and the linter names in any case (F-0020). So every comment that, once
# slashes and spaces are stripped, starts with "nolint" followed by ":", a
# space or the end of the line is read the same way: from "nolint" to the next
# "//", it has to be exactly nolint:<linter>[,<linter>...] (lowercase names,
# none starting with "all") and the line cites a recorded F-NNNN. Both greps
# read Go files as text (--text, never -I): a .gitattributes that marks them
# as binary must not hide them.
grc=0
hits="$(git grep -n --text -i --untracked -E '//[/[:space:]]*nolint([:[:space:]]|$)' -- '*.go' ':(exclude,glob)**/testdata/**')" || grc=$?
if [ "$grc" -gt 1 ]; then
  echo "check-skips: git grep falló (exit $grc)" >&2
  exit 1
fi
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  where="$(cut -d: -f1,2 <<< "$hit")"
  text="$(cut -d: -f3- <<< "$hit")"
  problem=""
  rest="$text"
  while :; do
    shopt -s nocasematch
    found=0
    if [[ "$rest" =~ //[/[:space:]]*nolint([:[:space:]]|$) ]]; then
      found=1
      m="${BASH_REMATCH[0]}"
    fi
    shopt -u nocasematch
    [ "$found" -eq 1 ] || break
    after="${rest#*"$m"}"
    directive="$m${after%%//*}"
    if [[ ! "$directive" =~ ^//nolint:[a-z0-9_-]+(,[a-z0-9_-]+)*[[:space:]]*$ ]]; then
      problem="//nolint con una forma no admitida (se escribe //nolint:<linter> // F-NNNN)"
    elif [[ ",${directive#//nolint:}" =~ ,all ]]; then
      problem="//nolint sin nombrar su linter"
    fi
    rest="$after"
  done
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
