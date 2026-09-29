#!/usr/bin/env bash
# Runs every harness test file (*_test.sh) in [dir] (default: this directory).
# Used by `make test-harness`. A file counts as green only if it exits 0,
# prints at least one "--- PASS:" and no "--- FAIL:"; a file that forgets
# `run_tests "$@"` runs nothing and is red. Also red if there are no files.
set -uo pipefail
dir="${1:-$(cd "$(dirname "$0")" && pwd)}"
shopt -s nullglob
files=("$dir"/*_test.sh)
if [ "${#files[@]}" -eq 0 ]; then
  echo "test-harness: no hay ficheros *_test.sh en $dir"
  exit 1
fi
status=0
for f in "${files[@]}"; do
  echo "== $(basename "$f")"
  rc=0
  out="$(bash "$f" 2>&1)" || rc=$?
  printf '%s\n' "$out"
  if [ "$rc" -ne 0 ] || ! grep -q '^--- PASS: ' <<< "$out" || grep -q '^--- FAIL: ' <<< "$out"; then
    echo "test-harness: $(basename "$f") en rojo (exit $rc)"
    status=1
  fi
done
if [ "$status" -ne 0 ]; then
  echo "test-harness: hay tests en rojo"
fi
exit "$status"
