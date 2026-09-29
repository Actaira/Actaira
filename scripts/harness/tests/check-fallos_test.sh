#!/usr/bin/env bash
# Tests for scripts/harness/check-fallos.sh. Each case builds a tiny repo in $T
# with its own docs/harness/FALLOS.md, Makefile, settings and Go module.
source "$(dirname "$0")/lib.sh"

HEADER='# Registro de fallos

## Formato

```
## F-0001 Título corto
- guardia: test:pkg/lock/canonical_test.go::TestCanonicalNFC
```

## Entradas
'

# project: go module with one passing, one skipped test, and one shell test file.
project() {
  mkdir -p docs/harness pkg/demo scripts/harness/tests .claude/rules
  printf 'module example.invalid/demo\n\ngo 1.27.1\n' > go.mod
  cat > pkg/demo/demo_test.go <<'EOF'
package demo

import "testing"

func TestPasses(t *testing.T) {}

func TestSkipped(t *testing.T) { t.Skip("not yet") }

func TestFails(t *testing.T) { t.Fatal("boom") }
EOF
  cat > scripts/harness/tests/demo_test.sh <<EOF
#!/usr/bin/env bash
source "$HARNESS_DIR/tests/lib.sh"
helper() { true; }
test_shell_passes() { helper; }
test_shell_fails() { false; }
run_tests "\$@"
EOF
  printf 'check:\n\tscripts/harness/check-weakeners.sh\n' > Makefile
  printf '# regla\n' > .claude/rules/demo.md
  printf '{"hooks":{}}' > .claude/settings.json
}

# fallos <entries>: writes FALLOS.md with the header plus the entries; prints the exit code.
fallos() {
  printf '%s\n%s\n' "$HEADER" "$1" > docs/harness/FALLOS.md
  local rc=0
  "$HARNESS_DIR/check-fallos.sh" >"$T/out" 2>&1 || rc=$?
  echo "$rc"
}

entry() { # id guard-line
  printf '## %s Algo\n- síntoma: x\n%s\n' "$1" "$2"
}

test_entry_without_guard_fails() {
  project
  assert_eq "$(fallos "$(entry F-0001 '- lección: ninguna')")" "1" "entrada sin guardia"
  assert_contains "$(cat "$T/out")" "F-0001: sin guardia"
}

test_missing_go_test_fails() {
  project
  assert_eq "$(fallos "$(entry F-0001 '- guardia: test:pkg/demo/demo_test.go::TestDoesNotExist')")" "1" "test Go que no existe"
}

test_skipped_go_test_fails() {
  project
  assert_eq "$(fallos "$(entry F-0001 '- guardia: test:pkg/demo/demo_test.go::TestSkipped')")" "1" "test Go saltado"
}

test_failing_go_test_fails() {
  project
  assert_eq "$(fallos "$(entry F-0001 '- guardia: test:pkg/demo/demo_test.go::TestFails')")" "1" "test Go que falla"
}

test_passing_go_test_passes() {
  project
  assert_eq "$(fallos "$(entry F-0001 '- guardia: test:pkg/demo/demo_test.go::TestPasses')")" "0" "test Go que pasa ($(cat "$T/out"))"
}

test_shell_test_guards_are_executed() {
  project
  assert_eq "$(fallos "$(entry F-0001 '- guardia: test:scripts/harness/tests/demo_test.sh::test_shell_passes')")" "0" "test de shell que pasa ($(cat "$T/out"))"
  assert_eq "$(fallos "$(entry F-0001 '- guardia: test:scripts/harness/tests/demo_test.sh::test_shell_fails')")" "1" "test de shell que falla"
  assert_eq "$(fallos "$(entry F-0001 '- guardia: test:scripts/harness/tests/demo_test.sh::test_shell_missing')")" "1" "test de shell que no existe"
  assert_eq "$(fallos "$(entry F-0001 '- guardia: test:scripts/harness/tests/demo_test.sh::helper')")" "1" "un helper no es una guardia"
  assert_contains "$(cat "$T/out")" "F-0001" "el motivo se ve en la salida"
}

test_failing_guard_shows_its_output() {
  project
  assert_eq "$(fallos "$(entry F-0001 '- guardia: test:scripts/harness/tests/demo_test.sh::test_shell_fails')")" "1" "guardia en rojo"
  assert_contains "$(cat "$T/out")" "--- FAIL: test_shell_fails" "check-fallos enseña la salida de la guardia"
}

test_duplicate_id_fails() {
  project
  local e
  e="$(entry F-0001 '- guardia: test:pkg/demo/demo_test.go::TestPasses')"
  assert_eq "$(fallos "$e
$e")" "1" "id repetido"
  assert_contains "$(cat "$T/out")" "ids repetidos"
}

test_format_example_in_code_block_does_not_count() {
  project
  # The header example points at a test that does not exist: it must be ignored.
  assert_eq "$(fallos "")" "0" "el ejemplo del formato no cuenta ($(cat "$T/out"))"
}

test_lint_hook_and_rule_guards() {
  project
  assert_eq "$(fallos "$(entry F-0001 '- guardia: lint:scripts/harness/check-weakeners.sh')")" "1" "lint que no existe en este repo"
  mkdir -p scripts/harness && printf '#!/bin/sh\n' > scripts/harness/check-weakeners.sh
  assert_eq "$(fallos "$(entry F-0001 '- guardia: lint:scripts/harness/check-weakeners.sh')")" "0" "lint que existe y está en el Makefile"
  printf '#!/bin/sh\n' > scripts/harness/other.sh
  assert_eq "$(fallos "$(entry F-0001 '- guardia: lint:scripts/harness/other.sh')")" "1" "lint que no está en el Makefile"
  assert_eq "$(fallos "$(entry F-0001 '- guardia: hook:scripts/harness/other.sh')")" "1" "hook que no está en settings.json"
  assert_eq "$(fallos "$(entry F-0001 '- guardia: regla:.claude/rules/demo.md')")" "0" "regla que existe"
  assert_eq "$(fallos "$(entry F-0001 '- guardia: regla:.claude/rules/nope.md')")" "1" "regla que no existe"
  assert_eq "$(fallos "$(entry F-0001 '- guardia: magia:algo')")" "1" "tipo de guardia desconocido"
}

run_tests "$@"
