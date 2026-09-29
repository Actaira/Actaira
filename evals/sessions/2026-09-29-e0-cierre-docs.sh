#!/usr/bin/env bash
# E0 closing, point 5 of the cierre-epica skill: documentation against reality.
#   1. Every harness test the docs cite (file_test.sh::test_name, or the short
#      form ::test_name right after a file) exists and passes on its own.
#   2. Every "`file_test.sh` (N tests)" count matches the file.
# Reads the E0 status, the ADRs, FALLOS, LECCIONES, CLAUDE.md, the rules and
# the skills. Exits 1 if anything does not match.
# Usage: bash evals/sessions/2026-09-29-e0-cierre-docs.sh
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
export PATH="$HOME/.local/go/bin:$HOME/go/bin:$PATH"
export GITLEAKS="$PWD/.tools/gitleaks-8.30.1"
docs=(docs/estado/E0.md docs/adr/*.md docs/harness/FALLOS.md docs/harness/LECCIONES.md CLAUDE.md
  .claude/rules/*.md .claude/skills/*/SKILL.md)
bad=0

refs="$(python3 - "${docs[@]}" <<'EOF'
import re
import sys
seen = []
for path in sys.argv[1:]:
    current = None
    for m in re.finditer(r"([A-Za-z0-9_-]+_test\.sh)?::(test_[A-Za-z0-9_]+)", open(path, encoding="utf-8").read()):
        current = m.group(1) or current
        if current and f"{current}::{m.group(2)}" not in seen:
            seen.append(f"{current}::{m.group(2)}")
print("\n".join(seen))
EOF
)"
echo "== 1. tests citados en la documentación: $(grep -c . <<< "$refs")"
while IFS= read -r ref; do
  file="${ref%%::*}"
  name="${ref##*::}"
  rc=0
  out="$(bash "scripts/harness/tests/$file" "$name" 2>&1)" || rc=$?
  if [ "$rc" -eq 0 ] && grep -qxF -- "--- PASS: $name" <<< "$out"; then
    echo "OK   $ref"
  else
    echo "MAL  $ref (exit $rc): $(tail -n 3 <<< "$out" | tr '\n' ' ')"
    bad=1
  fi
done <<< "$refs"

echo "== 2. recuentos de tests citados"
counts="$(grep -hoE '`[a-z-]+_test\.sh` \([0-9]+ tests?\)' "${docs[@]}" | sort -u)"
while IFS= read -r claim; do
  [ -n "$claim" ] || continue
  file="$(sed -E 's/^`([a-z-]+_test\.sh)`.*/\1/' <<< "$claim")"
  said="$(sed -E 's/.*\(([0-9]+) tests?\)$/\1/' <<< "$claim")"
  real="$(grep -cE '^test_[A-Za-z0-9_]+\(\)' "scripts/harness/tests/$file")"
  if [ "$said" = "$real" ]; then
    echo "OK   $file: $said"
  else
    echo "MAL  $file: la documentación dice $said, el fichero tiene $real"
    bad=1
  fi
done <<< "$counts"

if [ "$bad" -eq 0 ]; then echo "TODO OK"; else echo "HAY DIFERENCIAS"; fi
exit "$bad"
