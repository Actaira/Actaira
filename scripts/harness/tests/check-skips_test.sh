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

# //nolint switches golangci-lint off (L-003, E1 step 1.1): the directive names
# its linters and cites a recorded F-NNNN on the same line.
nolint_file() { # <path> <comment after the call>
  mkdir -p "$(dirname "$1")"
  printf 'package demo\n\nfunc f() error { return nil }\n\nfunc g() {\n\tf() %s\n}\n' "$2" > "$1"
}

test_nolint_without_a_fallo_fails() {
  repo_with_fallo
  nolint_file "$T/repo/pkg/demo/g.go" '//nolint:errcheck // the caller logs it'
  assert_eq "$(skips)" "1" "//nolint sin F-NNNN"
  assert_contains "$(cat "$T/out")" "check-skips: //nolint sin un F-NNNN de FALLOS.md en esa línea: pkg/demo/g.go:6"
}

test_nolint_citing_a_known_fallo_passes() {
  repo_with_fallo
  nolint_file "$T/repo/pkg/demo/g.go" '//nolint:errcheck // F-0007: the caller logs it'
  assert_eq "$(skips)" "0" "//nolint justificado ($(cat "$T/out"))"
}

test_nolint_citing_an_unknown_fallo_fails() {
  repo_with_fallo
  nolint_file "$T/repo/pkg/demo/g.go" '//nolint:errcheck // F-0999: the caller logs it'
  assert_eq "$(skips)" "1" "//nolint que cita un fallo inexistente"
}

test_nolint_without_a_linter_fails() {
  repo_with_fallo
  nolint_file "$T/repo/pkg/demo/a.go" '//nolint // F-0007: the caller logs it'
  nolint_file "$T/repo/pkg/demo/b.go" '//nolint:all // F-0007: the caller logs it'
  nolint_file "$T/repo/pkg/demo/c.go" '// nolint:errcheck // F-0007: the caller logs it'
  assert_eq "$(skips)" "1" "//nolint sin linter concreto"
  assert_contains "$(cat "$T/out")" "check-skips: //nolint con una forma no admitida (se escribe //nolint:<linter> // F-NNNN): pkg/demo/a.go:6"
  assert_contains "$(cat "$T/out")" "check-skips: //nolint sin nombrar su linter: pkg/demo/b.go:6"
  assert_contains "$(cat "$T/out")" "check-skips: //nolint con una forma no admitida (se escribe //nolint:<linter> // F-NNNN): pkg/demo/c.go:6"
}

test_nolint_in_testdata_is_ignored() {
  repo_with_fallo
  nolint_file "$T/repo/pkg/demo/testdata/fixture/g.go" '//nolint // fixture of an analysed repo'
  assert_eq "$(skips)" "0" "testdata son fixtures ($(cat "$T/out"))"
}

# Review round 1 of E1 step 1.1 (F-0020): golangci-lint strips the slashes and
# spaces before "nolint" and reads the linter names in any case. Each of these
# forms is refused: the ones golangci-lint applies and their look-alikes.
test_nolint_forms_that_golangci_lint_also_reads_fail() {
  repo_with_fallo
  nolint_file "$T/repo/pkg/demo/a.go" '// /nolint:all // F-0007: reason'
  nolint_file "$T/repo/pkg/demo/b.go" '//nolint:ALL // F-0007: reason'
  nolint_file "$T/repo/pkg/demo/c.go" '//nolint:errcheck, all // F-0007: reason'
  nolint_file "$T/repo/pkg/demo/d.go" '///nolint:errcheck // F-0007: reason'
  nolint_file "$T/repo/pkg/demo/e.go" '//NOLINT:errcheck // F-0007: reason'
  nolint_file "$T/repo/pkg/demo/f.go" '//nolint:errcheck,all // F-0007: reason'
  assert_eq "$(skips)" "1" "formas de //nolint que golangci-lint también lee"
  local f
  for f in a b c d e; do
    assert_contains "$(cat "$T/out")" "pkg/demo/$f.go:6"
  done
  assert_contains "$(cat "$T/out")" "check-skips: //nolint sin nombrar su linter: pkg/demo/f.go:6"
}

# The guard is checked against the tool it guards (F-0020, L-012). Every form
# cites a recorded F-NNNN, so only the form itself can make check-skips.sh
# refuse it. The function trips two linters: a form that makes golangci-lint
# drop anything but errcheck, or that is not the canonical //nolint:errcheck,
# must be refused, and with a message about the form, not about the citation.
test_every_nolint_form_that_golangci_lint_applies_is_flagged() {
  local gl
  gl="$REPO_DIR/$(make -s --no-print-directory -C "$REPO_DIR" -f "$REPO_DIR/Makefile" print-GOLANGCI_LINT)"
  [ -x "$gl" ] || fail "no existe $gl (make tools)"
  repo_with_fallo
  printf 'version: "2"\nlinters:\n  default: none\n  enable:\n    - errcheck\n    - ineffassign\n  exclusions:\n    generated: disable\n' > "$T/repo/.golangci.yml"
  local form out rc applied=0
  local forms=('//nolint:errcheck // F-0007: reason' '//nolint:errcheck ,all // F-0007: reason'
    $'//nolint:errcheck,\tall // F-0007: reason' '//nolint:errcheck, all // F-0007: reason' '//nolint:errcheck, ALL // F-0007: reason'
    '//nolint:allx // F-0007: reason' '//nolint:ALL // F-0007: reason' '// /nolint:all // F-0007: reason'
    '///nolint:all // F-0007: reason' '// nolint:all // F-0007: reason' '//nolint // F-0007: reason'
    '/* nolint:all */ // F-0007: reason' '//lint:ignore errcheck F-0007: reason')
  for form in "${forms[@]}"; do
    printf 'package demo\n\nfunc f() error { return nil }\n\nfunc G() int {\n\tf() %s\n\tn := 1\n\tn = 2\n\treturn n\n}\n' "$form" > "$T/repo/pkg/demo/g.go"
    rc=0
    out="$(cd "$T/repo" && "$gl" run --allow-serial-runners ./... 2>&1)" || rc=$?
    [[ "$out" == *"(errcheck)"* || "$out" == *"(ineffassign)"* || "$rc" -eq 0 ]] || fail "golangci-lint falló con \"$form\": $out"
    if [ "$form" = '//nolint:errcheck // F-0007: reason' ]; then
      [[ "$out" != *"(errcheck)"* && "$out" == *"(ineffassign)"* ]] || fail "la forma canónica tiene que apagar solo errcheck: $out"
      assert_eq "$(skips)" "0" "la forma canónica con su F-NNNN ($(cat "$T/out"))"
      continue
    fi
    if [[ "$out" == *"(errcheck)"* && "$out" == *"(ineffassign)"* ]]; then
      continue
    fi
    applied=$((applied + 1))
    assert_eq "$(skips)" "1" "golangci-lint aplica \"$form\" y check-skips.sh tiene que rechazarlo"
    assert_not_contains "$(cat "$T/out")" "sin un F-NNNN" "\"$form\": el motivo es la forma, no la cita"
  done
  [ "$applied" -ge 8 ] || fail "golangci-lint solo aplicó $applied formas: la prueba ya no compara nada"
}

# Comments and strings that only talk about nolint are not directives
# (review round 2 of E1 step 1.1).
test_prose_about_nolint_passes() {
  repo_with_fallo
  printf 'package demo\n\n// nolintlint is enabled in .golangci.yml.\nconst c = 1\n' > "$T/repo/pkg/demo/prose.go"
  assert_eq "$(skips)" "0" "un comentario que habla de nolintlint ($(cat "$T/out"))"
}

# A .gitattributes that marks Go files as binary must not hide them.
test_binary_attributes_do_not_hide_a_go_file() {
  repo_with_fallo
  nolint_file "$T/repo/pkg/demo/g.go" '//nolint:errcheck // the caller logs it'
  go_test_file "$T/repo/pkg/demo/demo_test.go" 't.Skip("slow")'
  printf '*.go binary\n' > "$T/repo/.gitattributes"
  assert_eq "$(skips)" "1" "*.go binary en .gitattributes"
  assert_contains "$(cat "$T/out")" "pkg/demo/g.go:6"
  assert_contains "$(cat "$T/out")" "pkg/demo/demo_test.go:6"
}

# F-0021 (review round 3 of E1 step 1.1): the guard reads git's view of the
# files, so what that view hides is refused outright, by a white list, instead
# of chasing each variant.
test_go_symlink_fails() {
  repo_with_fallo
  mkdir -p "$T/repo/docs/notes"
  printf 'package demo\n\nfunc f() error { return nil }\n\nfunc g() {\n\tf() //nolint:errcheck, all // no reason\n}\n' > "$T/repo/docs/notes/g.txt"
  ln -s ../../docs/notes/g.txt "$T/repo/pkg/demo/g.go"
  assert_eq "$(skips)" "1" "un .go que es un enlace simbólico"
  assert_contains "$(cat "$T/out")" "check-skips: un .go que es un enlace simbólico: pkg/demo/g.go"
}

test_go_path_outside_the_allowed_characters_fails() {
  repo_with_fallo
  nolint_file "$T/repo/pkg/demo/a:b:F-0007.go" '//nolint:errcheck // the caller logs it'
  go_test_file "$T/repo/pkg/demo/café_test.go" 't.Skip("slow")'
  assert_eq "$(skips)" "1" "rutas fuera de [A-Za-z0-9._/-]"
  assert_contains "$(cat "$T/out")" "check-skips: la ruta de un .go tiene caracteres fuera de [A-Za-z0-9._/-]: pkg/demo/a:b:F-0007.go"
  assert_contains "$(cat "$T/out")" "check-skips: la ruta de un .go tiene caracteres fuera de [A-Za-z0-9._/-]: pkg/demo/café_test.go"
}

test_line_directive_fails() {
  repo_with_fallo
  printf 'package demo\n\n//line notes.tmpl:1\nfunc f() error { return nil }\n' > "$T/repo/pkg/demo/a.go"
  printf 'package demo\n\nfunc g() error { /*line notes.tmpl:1*/ return nil }\n' > "$T/repo/pkg/demo/b.go"
  assert_eq "$(skips)" "1" "directivas //line"
  assert_contains "$(cat "$T/out")" "check-skips: directiva //line (apaga linters en el código que la sigue): pkg/demo/a.go:3"
  assert_contains "$(cat "$T/out")" "check-skips: directiva //line (apaga linters en el código que la sigue): pkg/demo/b.go:3"
}

test_skip_in_a_helper_importing_testing_with_an_alias_fails() {
  repo_with_fallo
  printf 'package demo\n\nimport tb "testing"\n\nfunc RequireDocker(t *tb.T) {\n\tt.Skip("no docker")\n}\n' > "$T/repo/pkg/demo/helper.go"
  assert_eq "$(skips)" "1" "helper que importa testing con alias"
  assert_contains "$(cat "$T/out")" "pkg/demo/helper.go:6"
}

run_tests "$@"
