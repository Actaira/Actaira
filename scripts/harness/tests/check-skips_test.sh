#!/usr/bin/env bash
# Tests for scripts/harness/check-skips.sh: a skipped Go test is an exception
# that switches a check off, so it must cite a recorded F-NNNN (L-003).
source "$(dirname "$0")/lib.sh"

# repo_with_fallo: a Go module repo whose FALLOS.md records F-0007.
repo_with_fallo() {
  init_repo "$T/repo"
  mkdir -p "$T/repo/docs/harness" "$T/repo/pkg/demo"
  printf '# Registro de fallos\n\n## Entradas\n\n## F-0007 Fixture\n- guardia: regla:.claude/rules/go.md\n' \
    > "$T/repo/docs/harness/FALLOS.md"
  printf 'module example.invalid/demo\n\ngo 1.27.1\n' > "$T/repo/go.mod"
  printf 'package demo\n' > "$T/repo/pkg/demo/demo.go"
}

# go_test_file <path> <body line>: a _test.go file whose only test runs <body line>.
go_test_file() {
  mkdir -p "$(dirname "$1")"
  printf 'package demo\n\nimport "testing"\n\nfunc TestX(t *testing.T) {\n\t%s\n}\n' "$2" > "$1"
}

skips() { # prints the exit code; output in $T/out
  local rc=0
  (cd "$T/repo" && "$HARNESS_DIR/check-skips.sh") >"$T/out" 2>&1 || rc=$?
  echo "$rc"
}

test_repo_without_skips_passes() {
  repo_with_fallo
  go_test_file "$T/repo/pkg/demo/demo_test.go" 't.Log("ok")'
  assert_eq "$(skips)" "0" "sin tests saltados ($(cat "$T/out"))"
}

test_unjustified_skip_fails() {
  repo_with_fallo
  go_test_file "$T/repo/pkg/demo/demo_test.go" 't.Skip("slow")'
  assert_eq "$(skips)" "1" "t.Skip sin F-NNNN"
  assert_contains "$(cat "$T/out")" "pkg/demo/demo_test.go:6"
}

test_skip_citing_unknown_fallo_fails() {
  repo_with_fallo
  go_test_file "$T/repo/pkg/demo/demo_test.go" 't.Skip("F-0999: upstream flaky")'
  assert_eq "$(skips)" "1" "t.Skip que cita un fallo inexistente"
}

test_justified_skip_passes() {
  repo_with_fallo
  go_test_file "$T/repo/pkg/demo/demo_test.go" 't.Skip("F-0007: upstream flaky")'
  assert_eq "$(skips)" "0" "t.Skip justificado ($(cat "$T/out"))"
}

test_skipnow_and_skipf_are_checked() {
  repo_with_fallo
  go_test_file "$T/repo/pkg/demo/a_test.go" 't.SkipNow()'
  go_test_file "$T/repo/pkg/demo/b_test.go" 't.Skipf("slow %d", 1)'
  assert_eq "$(skips)" "1" "SkipNow y Skipf"
  assert_contains "$(cat "$T/out")" "pkg/demo/a_test.go"
  assert_contains "$(cat "$T/out")" "pkg/demo/b_test.go"
}

test_testdata_fixtures_are_ignored() {
  repo_with_fallo
  go_test_file "$T/repo/pkg/demo/testdata/trap/trap_test.go" 't.Skip("fixture of an analysed repo")'
  assert_eq "$(skips)" "0" "los fixtures de testdata no son tests del módulo ($(cat "$T/out"))"
}

# Round 1 of step 0.3, finding 10: the citation must be in the code, not in
# the path of the file.
test_fallo_in_the_path_does_not_justify_a_skip() {
  repo_with_fallo
  go_test_file "$T/repo/pkg/F-0007/x_test.go" 't.Skip("slow")'
  assert_eq "$(skips)" "1" "F-NNNN solo en la ruta"
}

test_skip_used_as_a_value_is_checked() {
  repo_with_fallo
  go_test_file "$T/repo/pkg/demo/demo_test.go" 'skip := t.SkipNow; skip()'
  assert_eq "$(skips)" "1" "t.SkipNow como valor"
}

# go_constrained_test <path> <constraint line> [line above]: a test file behind a build constraint.
go_constrained_test() {
  mkdir -p "$(dirname "$1")"
  {
    if [ -n "${3:-}" ]; then printf '%s\n' "$3"; fi
    printf '%s\n\npackage demo\n\nimport "testing"\n\nfunc TestX(t *testing.T) {}\n' "$2"
  } > "$1"
}

# Round 2 of step 0.3, finding 5: a test file that `make check` (go test
# ./..., no tags) never compiles is a skipped test too, whatever the reason:
# an unknown tag, a tag no recipe sets, a condition never true, or the file name.
test_test_files_the_default_build_never_compiles_fail() {
  local constraint
  for constraint in "//go:build never" "// +build ignore" "//go:build integration" \
    "//go:build race" "//go:build go1.99" "//go:build linux && !linux"; do
    repo_with_fallo
    go_constrained_test "$T/repo/pkg/demo/a_test.go" "$constraint"
    assert_eq "$(skips)" "1" "$constraint"
    assert_contains "$(cat "$T/out")" "pkg/demo/a_test.go"
    rm -rf "$T/repo"
  done
  repo_with_fallo
  go_test_file "$T/repo/pkg/demo/d_windows_test.go" 't.Log("never on linux")'
  assert_eq "$(skips)" "1" "fichero excluido por el nombre"
  assert_contains "$(cat "$T/out")" "pkg/demo/d_windows_test.go"
}

test_constraints_true_in_make_check_pass() {
  repo_with_fallo
  go_constrained_test "$T/repo/pkg/demo/a_test.go" "//go:build linux && !race"
  go_constrained_test "$T/repo/pkg/demo/b_test.go" "//go:build go1.27 && (amd64 || arm64)"
  assert_eq "$(skips)" "0" "restricciones que make check cumple ($(cat "$T/out"))"
}

# E0 closing review (integration, finding 2): the required check compiles on
# linux/amd64, so a test for Linux only (E1: //go:build linux) counts there
# and is not flagged when check-skips runs elsewhere (the macOS job of E1); a
# test the required check never compiles is flagged on every system.
test_build_is_judged_on_the_platform_of_the_required_check() {
  repo_with_fallo
  go_constrained_test "$T/repo/pkg/demo/a_test.go" "//go:build linux"
  go_test_file "$T/repo/pkg/demo/b_linux_test.go" 't.Log("linux only")'
  sed -i 's/TestX/TestY/' "$T/repo/pkg/demo/b_linux_test.go"
  local rc=0
  (cd "$T/repo" && GOOS=darwin GOARCH=arm64 "$HARNESS_DIR/check-skips.sh") >"$T/out" 2>&1 || rc=$?
  assert_eq "$rc" "0" "tests solo de Linux, con check-skips en darwin ($(cat "$T/out"))"
  go_test_file "$T/repo/pkg/demo/c_darwin_test.go" 't.Log("never in the required check")'
  sed -i 's/TestX/TestZ/' "$T/repo/pkg/demo/c_darwin_test.go"
  rc=0
  (cd "$T/repo" && GOOS=darwin GOARCH=arm64 "$HARNESS_DIR/check-skips.sh") >"$T/out" 2>&1 || rc=$?
  assert_eq "$rc" "1" "test solo de darwin, con check-skips en darwin"
  assert_contains "$(cat "$T/out")" "pkg/demo/c_darwin_test.go"
  assert_not_contains "$(cat "$T/out")" "b_linux_test.go"
}

test_justified_ignored_test_file_passes() {
  repo_with_fallo
  go_constrained_test "$T/repo/pkg/demo/a_test.go" "//go:build never" "// F-0007: parked until the upstream fix"
  assert_eq "$(skips)" "0" "fichero ignorado con F-NNNN en la cabecera ($(cat "$T/out"))"
}

# Round 2 of step 0.3, finding 5: a helper outside _test.go can skip tests
# (testutil.RequireDocker(t)); production code may have its own Skip method.
test_skip_in_a_test_helper_fails() {
  repo_with_fallo
  mkdir -p "$T/repo/internal/testutil"
  printf 'package testutil\n\nimport "testing"\n\nfunc RequireDocker(t testing.TB) {\n\tt.Skip("no docker")\n}\n' \
    > "$T/repo/internal/testutil/docker.go"
  assert_eq "$(skips)" "1" "t.Skip en un helper"
  assert_contains "$(cat "$T/out")" "internal/testutil/docker.go:6"
}

test_skip_method_in_production_code_passes() {
  repo_with_fallo
  mkdir -p "$T/repo/pkg/parse"
  printf 'package parse\n\ntype Cursor struct{}\n\nfunc (c *Cursor) Skip(n int) {}\n\nfunc Walk(c *Cursor) { c.Skip(1) }\n' \
    > "$T/repo/pkg/parse/cursor.go"
  assert_eq "$(skips)" "0" "un método Skip propio en código de producción ($(cat "$T/out"))"
}

run_tests "$@"
