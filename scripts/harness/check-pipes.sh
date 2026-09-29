#!/usr/bin/env bash
# L-000e, F-0012: with `set -o pipefail`, a pipe into a reader that exits
# early (head, grep -q/-m/-l) returns 141 when the writer is still writing, so
# the result depends on the size of the input: a false red, or a false green
# in an `if`. Capture the output in a variable and use a here-string instead.
# Checks every shell script under scripts/ (the harness included), the git
# hooks without extension and the Makefile.
set -uo pipefail
files="$(
  { ls Makefile 2>/dev/null
    find scripts -type f \( -name '*.sh' -o -name pre-push -o -name commit-msg \) 2>/dev/null
  } | sort -u
)"
status=0
# A single | (not ||) followed by head, or by grep with q, m or l in a flag.
early_exit='(^|[^|])\|[[:space:]]*(head([[:space:]]|$)|grep([[:space:]]+[^|[:space:]]+)*[[:space:]]+-[a-zA-Z]*[qml])'
for f in $files; do
  if grep -nHE "$early_exit" "$f"; then
    echo "$f: tubería hacia un lector que sale antes (head, grep -q/-m/-l): con pipefail da 141 según el tamaño; usa una variable y <<<"
    status=1
  fi
done
exit "$status"
