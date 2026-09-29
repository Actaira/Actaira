#!/usr/bin/env bash
# Tests for the Makefile itself: things that could turn `make check` green
# without touching a recipe.
source "$(dirname "$0")/lib.sh"

# GOFLAGS in the environment could filter tests (-run) or skip slow ones (-short).
test_goflags_from_environment_cannot_filter_tests() {
  local out rc=0
  out="$(cd "$REPO_DIR" && GOFLAGS='-run=^NoSuchTest$' make -s test 2>&1)" || rc=$?
  assert_eq "$rc" "0" "make test con GOFLAGS en el entorno ($out)"
  assert_not_contains "$out" "no tests to run" "GOFLAGS del entorno no llega a go test"
}

# GOFLAGS written with `go env -w` lives in the go env file, not in the
# environment: make test refuses to run instead of silently obeying it.
test_goflags_in_go_env_file_fails() {
  GOENV="$T/goenv" go env -w GOFLAGS=-short
  local out rc=0
  out="$(cd "$REPO_DIR" && GOENV="$T/goenv" make -s test 2>&1)" || rc=$?
  assert_eq "$rc" "2" "make test con GOFLAGS en go env"
  assert_contains "$out" "GOFLAGS no vacío"
}

# go_module <dir>: a throwaway module to run the repo's Makefile targets on,
# with `make -f`, so the test never touches the repo.
go_module() {
  mkdir -p "$1/pkg/demo"
  printf 'module example.invalid/demo\n\ngo 1.27.1\n' > "$1/go.mod"
  printf 'package demo\n\nfunc Demo() int { return 1 }\n' > "$1/pkg/demo/demo.go"
}

test_fmt_check_fails_on_unformatted_go() {
  go_module "$T/m"
  printf 'package demo\nfunc   Bad( )int{\nreturn 1}\n' > "$T/m/pkg/demo/bad.go"
  local out rc=0
  out="$(cd "$T/m" && make -s -f "$REPO_DIR/Makefile" fmt-check 2>&1)" || rc=$?
  assert_eq "$rc" "2" "fmt-check con un .go sin formatear"
  assert_contains "$out" "pkg/demo/bad.go"
}

test_fmt_check_skips_testdata_fixtures() {
  go_module "$T/m"
  mkdir -p "$T/m/pkg/demo/testdata"
  printf 'package fixture\nfunc   Trap( ){}\n' > "$T/m/pkg/demo/testdata/trap.go"
  local out rc=0
  out="$(cd "$T/m" && make -s -f "$REPO_DIR/Makefile" fmt-check 2>&1)" || rc=$?
  assert_eq "$rc" "0" "fixtures sin formatear en testdata ($out)"
}

test_test_target_fails_on_red_go_test() {
  go_module "$T/m"
  printf 'package demo\n\nimport "testing"\n\nfunc TestRed(t *testing.T) { t.Fatal("rojo") }\n' > "$T/m/pkg/demo/demo_test.go"
  local out rc=0
  out="$(cd "$T/m" && make -s -f "$REPO_DIR/Makefile" test 2>&1)" || rc=$?
  assert_eq "$rc" "2" "make test con un test Go en rojo"
  assert_contains "$out" "--- FAIL: TestRed"
}

# E0 closing review (integration, finding 13): make install-hooks puts the same
# pre-push and commit-msg as scripts/harness/ into the repo's hooks directory.
test_install_hooks_installs_both_hooks() {
  init_repo "$T/repo"
  mkdir -p "$T/repo/scripts/harness"
  cp "$REPO_DIR/scripts/harness/pre-push" "$REPO_DIR/scripts/harness/commit-msg" "$T/repo/scripts/harness/"
  local out rc=0 h
  out="$(cd "$T/repo" && make -s -f "$REPO_DIR/Makefile" install-hooks 2>&1)" || rc=$?
  assert_eq "$rc" "0" "make install-hooks ($out)"
  for h in pre-push commit-msg; do
    cmp -s "$T/repo/.git/hooks/$h" "$REPO_DIR/scripts/harness/$h" || fail "$h no está instalado igual que scripts/harness/$h"
    [ -x "$T/repo/.git/hooks/$h" ] || fail "$h instalado sin permiso de ejecución"
  done
}

# F-0014: the required check runs `make check` as the pull request defines it,
# so every check of the harness stays among its prerequisites.
test_check_runs_every_harness_check() {
  local check gate phony t missing=""
  check="$(grep -E '^check:' "$REPO_DIR/Makefile")"
  gate="$(grep -E '^gate:' "$REPO_DIR/Makefile")"
  assert_eq "$check" \
    "check: weakeners pipes fallos skips attribution personal fmt-check lint test determinism test-harness secrets" "prerrequisitos de check"
  assert_eq "$gate" "gate: check evals-paso e2e-rapido" "prerrequisitos de gate"
  # Round 2 of step 0.4: a target missing from .PHONY is skipped when a path
  # with its name exists (a test/ directory), and check still says OK.
  phony="$(awk '/^\.PHONY:/ {p = 1} p {printf " %s", $0} p && !/\\$/ {p = 0}' "$REPO_DIR/Makefile")"
  phony="${phony//\\/ }"
  phony="${phony//$'\t'/ } "
  for t in check gate ${check#check:} ${gate#gate:}; do
    [[ "$phony" == *" $t "* ]] || missing+="$t "
  done
  assert_eq "$missing" "" "objetivos de check y gate fuera de .PHONY"
}

run_tests "$@"
