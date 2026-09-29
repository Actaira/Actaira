#!/usr/bin/env bash
# Tests for the harness test framework itself (lib.sh and run.sh): a test that
# cannot fail is worse than no test.
source "$(dirname "$0")/lib.sh"

# suite <dir> <body>: writes <dir>/x_test.sh sourcing lib.sh with <body>.
suite() {
  mkdir -p "$1"
  printf '#!/usr/bin/env bash\nsource "%s/tests/lib.sh"\n%s\n' "$HARNESS_DIR" "$2" > "$1/x_test.sh"
}

test_failing_assertion_fails_the_test() {
  suite "$T/s" 'test_bad() { assert_eq a b; echo "no debe llegar aquí"; }
run_tests "$@"'
  local out rc=0
  out="$(bash "$T/s/x_test.sh" 2>&1)" || rc=$?
  assert_eq "$rc" "1" "exit con un test en rojo"
  assert_contains "$out" "--- FAIL: test_bad"
  assert_not_contains "$out" "no debe llegar aquí" "set -e corta el test en la primera aserción"
}

test_helper_is_not_a_test() {
  suite "$T/s" 'helper() { true; }
test_ok() { helper; }
run_tests "$@"'
  local out rc=0
  out="$(bash "$T/s/x_test.sh" helper 2>&1)" || rc=$?
  assert_eq "$rc" "1" "pedir un helper como test falla"
  assert_not_contains "$out" "--- PASS: helper"
}

test_missing_test_fails() {
  suite "$T/s" 'test_ok() { true; }
run_tests "$@"'
  local rc=0
  bash "$T/s/x_test.sh" test_nope >/dev/null 2>&1 || rc=$?
  assert_eq "$rc" "1" "un test que no existe falla"
}

test_runner_fails_file_that_never_runs_tests() {
  suite "$T/s" 'test_always_fails() { fail boom; }'
  local out rc=0
  out="$(bash "$HARNESS_DIR/tests/run.sh" "$T/s" 2>&1)" || rc=$?
  assert_eq "$rc" "1" "un fichero sin run_tests no cuenta como verde"
  assert_contains "$out" "x_test.sh"
}

test_runner_fails_on_any_red_test() {
  suite "$T/s" 'test_ok() { true; }
test_bad() { false; }
run_tests "$@"'
  local rc=0
  bash "$HARNESS_DIR/tests/run.sh" "$T/s" >/dev/null 2>&1 || rc=$?
  assert_eq "$rc" "1" "un test en rojo pone el runner en rojo"
}

test_runner_passes_green_suite() {
  suite "$T/s" 'test_ok() { true; }
run_tests "$@"'
  local out rc=0
  out="$(bash "$HARNESS_DIR/tests/run.sh" "$T/s" 2>&1)" || rc=$?
  assert_eq "$rc" "0" "suite en verde ($out)"
}

# F-0008 and round 2 of step 0.4: a guard that takes the file it checks from
# the environment (FOO="${FOO_FILE:-...}") can be pointed at a good copy and
# pass whatever the repo holds. Mutation proofs copy the whole tree instead.
test_no_test_takes_its_target_from_the_environment() {
  local found
  found="$(grep -nE '^[[:space:]]*(local[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*="?\$\{[A-Za-z_][A-Za-z0-9_]*:-' "$HARNESS_DIR"/tests/*.sh)" || found=""
  assert_eq "$found" "" "tests que toman del entorno el fichero que comprueban"
}

run_tests "$@"
