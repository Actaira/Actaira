#!/usr/bin/env bash
# Every failure recorded in docs/harness/FALLOS.md must have a permanent guard
# that exists AND runs, so the same failure cannot come back silently.
# Accepted guard formats (one per line, "- guardia: ..."):
#   - guardia: test:<path>::<TestName>   Go tests and harness shell tests (*_test.sh) are
#                                        executed and must PASS (not skip).
#                                        Other languages: the test name must exist in the file.
#   - guardia: lint:scripts/harness/<x>  must exist and be referenced by the Makefile
#   - guardia: hook:scripts/harness/<x>  must exist and be referenced by .claude/settings.json
#   - guardia: regla:.claude/rules/<x>.md must exist
set -uo pipefail
f="docs/harness/FALLOS.md"
[ -f "$f" ] || { echo "falta $f"; exit 1; }

status=0
# show_tail <output>: the last lines of a failing guard, so the reason is visible.
show_tail() { tail -n 20 <<< "$1" | sed 's/^/    | /'; }

# Only entries after "## Entradas", ignoring fenced code blocks (the format example).
body="$(awk '/^## Entradas/{p=1; next} p' "$f" | awk '/^```/{c=!c; next} !c')"
all_ids="$(printf '%s\n' "$body" | grep -E '^## F-[0-9]{4}' | awk '{print $2}')"
ids="$(printf '%s\n' "$all_ids" | sed '/^$/d' | sort -u)"
dups="$(printf '%s\n' "$all_ids" | sed '/^$/d' | sort | uniq -d)"
if [ -n "$dups" ]; then echo "ids repetidos: $dups"; status=1; fi

for id in $ids; do
  block="$(printf '%s\n' "$body" | awk -v id="$id" '$0 ~ "^## "id"( |$)" {p=1; next} /^## F-/ {p=0} p')"
  guards="$(printf '%s\n' "$block" | grep -E '^- guardia: ' | sed 's/^- guardia: //')"
  if [ -z "$guards" ]; then
    echo "$id: sin guardia"; status=1; continue
  fi
  while IFS= read -r g; do
    kind="${g%%:*}"; rest="${g#*:}"
    case "$kind" in
      test)
        path="${rest%%::*}"; name="${rest##*::}"
        if [ ! -f "$path" ]; then echo "$id: no existe $path"; status=1; continue; fi
        case "$path" in
          *.go)
            # Capture first and grep a here-string: with pipefail, grep -q closing
            # a pipe early would fail the pipeline (L-000e).
            grc=0
            gout="$(go test -count=1 -run "^${name}\$" "./$(dirname "$path")" -v 2>&1)" || grc=$?
            if [ "$grc" -ne 0 ] || ! grep -qF -- "--- PASS: ${name} " <<< "$gout"; then
              echo "$id: $name no existe, no pasa o está saltado"; show_tail "$gout"; status=1
            fi ;;
          *_test.sh)
            if [[ ! "$name" =~ ^test_[A-Za-z0-9_]+$ ]]; then
              echo "$id: $name no es un test (los tests de shell se llaman test_*)"; status=1; continue
            fi
            src=0
            sout="$(bash "$path" "$name" 2>&1)" || src=$?
            if [ "$src" -ne 0 ] || ! grep -qxF -- "--- PASS: ${name}" <<< "$sout"; then
              echo "$id: $name no existe o no pasa"; show_tail "$sout"; status=1
            fi ;;
          *)
            grep -Eq "(def|function|test\(['\"]|it\(['\"])[[:space:]]*${name}" "$path" \
              || { echo "$id: no existe el test $name en $path"; status=1; } ;;
        esac ;;
      lint)
        case "$rest" in
          scripts/harness/*)
            [ -f "$rest" ] || { echo "$id: no existe $rest"; status=1; continue; }
            grep -q "$rest" Makefile || { echo "$id: $rest no está en el Makefile"; status=1; } ;;
          *) echo "$id: lint fuera de scripts/harness"; status=1 ;;
        esac ;;
      hook)
        case "$rest" in
          scripts/harness/*)
            [ -f "$rest" ] || { echo "$id: no existe $rest"; status=1; continue; }
            grep -q "$(basename "$rest")" .claude/settings.json || { echo "$id: $rest no está en settings.json"; status=1; } ;;
          *) echo "$id: hook fuera de scripts/harness"; status=1 ;;
        esac ;;
      regla)
        case "$rest" in
          .claude/rules/*.md) [ -f "$rest" ] || { echo "$id: no existe $rest"; status=1; } ;;
          *) echo "$id: regla fuera de .claude/rules"; status=1 ;;
        esac ;;
      *) echo "$id: tipo de guardia desconocido: $g"; status=1 ;;
    esac
  done <<< "$guards"
done
exit $status
