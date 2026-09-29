#!/usr/bin/env bash
# Tests for scripts/harness/check-weakeners.sh. Each case builds a tiny project
# in $T (the script scans the current directory) with exactly one weakener,
# and checks both the exit code and the reason reported.
source "$(dirname "$0")/lib.sh"

# weakeners: runs the check in $T; output goes to $T/out; prints the exit code.
weakeners() {
  local rc=0
  "$HARNESS_DIR/check-weakeners.sh" >"$T/out" 2>&1 || rc=$?
  echo "$rc"
}

# clean_makefile [extra recipe line]: a Makefile with the required shell
# settings; the optional line is appended to the check recipe.
clean_makefile() {
  printf 'SHELL := bash\n.SHELLFLAGS := -euo pipefail -c\n\ncheck:\n\tgo test ./...\n\t@echo "sin evals todavía"\n' > Makefile
  if [ -n "${1:-}" ]; then printf '\t%s\n' "$1" >> Makefile; fi
}

test_clean_project_passes() {
  clean_makefile
  mkdir -p .github/workflows scripts
  printf 'jobs:\n  check:\n    runs-on: ubuntu-latest\n    steps:\n      - run: make check\n' > .github/workflows/ci.yml
  printf '#!/usr/bin/env bash\nset -euo pipefail\necho ok\n' > scripts/tool.sh
  assert_eq "$(weakeners)" "0" "proyecto limpio ($(cat "$T/out"))"
}

test_or_true_in_makefile_fails() {
  clean_makefile 'go vet ./... || true'
  assert_eq "$(weakeners)" "1" "|| true en el Makefile"
  assert_contains "$(cat "$T/out")" "|| que traga errores"
}

test_dash_prefixed_recipe_fails() {
  clean_makefile '-go vet ./...'
  assert_eq "$(weakeners)" "1" "receta con -"
  assert_contains "$(cat "$T/out")" "receta con prefijo '-'"
}

test_ignore_special_target_fails() {
  clean_makefile
  printf '.IGNORE:\n' >> Makefile
  assert_eq "$(weakeners)" "1" ".IGNORE"
  assert_contains "$(cat "$T/out")" ".IGNORE"
}

test_make_keep_going_fails() {
  clean_makefile '$(MAKE) -k test'
  assert_eq "$(weakeners)" "1" '$(MAKE) -k'
  assert_contains "$(cat "$T/out")" "make con -i o -k"
}

test_continue_on_error_workflow_fails() {
  clean_makefile
  mkdir -p .github/workflows
  printf 'jobs:\n  check:\n    runs-on: ubuntu-latest\n    continue-on-error: true\n    steps:\n      - run: make check\n' > .github/workflows/ci.yml
  assert_eq "$(weakeners)" "1" "continue-on-error: true"
  assert_contains "$(cat "$T/out")" "continue-on-error"
}

# F-0014: for GitHub an expression is as good as a literal true.
test_continue_on_error_with_expression_fails() {
  clean_makefile
  mkdir -p .github/workflows
  printf 'jobs:\n  check:\n    runs-on: ubuntu-latest\n    steps:\n      - run: make check\n        continue-on-error: ${{ true }}\n' > .github/workflows/ci.yml
  assert_eq "$(weakeners)" "1" 'continue-on-error: ${{ true }}'
  assert_contains "$(cat "$T/out")" "continue-on-error"
}

test_or_true_in_project_script_fails() {
  clean_makefile
  mkdir -p scripts
  printf '#!/usr/bin/env bash\ngo test ./... || true\n' > scripts/tool.sh
  assert_eq "$(weakeners)" "1" "|| true en un script del proyecto"
  assert_contains "$(cat "$T/out")" "scripts/tool.sh"
}

# Round 1, finding 13: without -e in .SHELLFLAGS, a failing command in a
# multi-command recipe line (a loop, `a; b`) no longer fails the recipe.
test_makefile_without_bash_shell_fails() {
  clean_makefile
  sed -i '/^SHELL := bash$/d' Makefile
  assert_eq "$(weakeners)" "1" "Makefile sin SHELL := bash"
  assert_contains "$(cat "$T/out")" "SHELL := bash"
}

test_makefile_with_other_shell_fails() {
  clean_makefile
  sed -i 's/^SHELL := bash$/SHELL := true/' Makefile
  assert_eq "$(weakeners)" "1" "SHELL := true"
  assert_contains "$(cat "$T/out")" "SHELL := bash"
}

test_shellflags_without_errexit_fails() {
  clean_makefile
  sed -i 's/^\.SHELLFLAGS := .*/.SHELLFLAGS := -uo pipefail -c/' Makefile
  assert_eq "$(weakeners)" "1" ".SHELLFLAGS sin -e"
  assert_contains "$(cat "$T/out")" ".SHELLFLAGS"
}

test_shellflags_without_pipefail_fails() {
  clean_makefile
  sed -i 's/^\.SHELLFLAGS := .*/.SHELLFLAGS := -eu -c/' Makefile
  assert_eq "$(weakeners)" "1" ".SHELLFLAGS sin pipefail"
  assert_contains "$(cat "$T/out")" ".SHELLFLAGS"
}

# Round 1 of step 0.3, finding 11: a later or target-specific assignment
# would undo the required settings.
test_second_shellflags_assignment_fails() {
  clean_makefile
  printf '.SHELLFLAGS = -c\n' >> Makefile
  assert_eq "$(weakeners)" "1" "segunda asignación de .SHELLFLAGS"
  assert_contains "$(cat "$T/out")" ".SHELLFLAGS"
}

test_target_specific_shell_fails() {
  clean_makefile
  printf 'check: SHELL := sh\n' >> Makefile
  assert_eq "$(weakeners)" "1" "SHELL de un objetivo concreto"
  assert_contains "$(cat "$T/out")" "SHELL := bash"
}

# Round 1 of step 0.3, finding 8: other ways to reach the same settings.
test_posix_assignment_of_shellflags_fails() {
  clean_makefile
  printf '.SHELLFLAGS ::= -c\n' >> Makefile
  assert_eq "$(weakeners)" "1" ".SHELLFLAGS ::="
  assert_contains "$(cat "$T/out")" ".SHELLFLAGS"
}

test_errexit_turned_off_in_shellflags_fails() {
  clean_makefile
  sed -i 's/^\.SHELLFLAGS := .*/.SHELLFLAGS := -euo pipefail +e -c/' Makefile
  assert_eq "$(weakeners)" "1" ".SHELLFLAGS con +e"
  assert_contains "$(cat "$T/out")" ".SHELLFLAGS"
}

test_define_block_for_shell_settings_fails() {
  clean_makefile
  printf 'define .SHELLFLAGS\n-c\nendef\n' >> Makefile
  assert_eq "$(weakeners)" "1" "define .SHELLFLAGS"
  assert_contains "$(cat "$T/out")" "define"
}

test_include_directive_fails() {
  clean_makefile
  printf 'include extra.mk\n' >> Makefile
  printf '.IGNORE:\n' > extra.mk
  assert_eq "$(weakeners)" "1" "include de otro makefile"
  assert_contains "$(cat "$T/out")" "include"
}

test_makefiles_that_take_precedence_fail() {
  local name
  for name in GNUmakefile makefile; do
    rm -f GNUmakefile makefile
    clean_makefile
    printf 'check:\n\t@true\n' > "$name"
    assert_eq "$(weakeners)" "1" "$name junto al Makefile"
    assert_contains "$(cat "$T/out")" "$name"
  done
}

# Round 1 of step 0.3, finding 9: make flags and test filters in any file.
test_make_ignore_errors_in_workflow_fails() {
  clean_makefile
  mkdir -p .github/workflows
  printf 'jobs:\n  check:\n    runs-on: ubuntu-latest\n    steps:\n      - run: make -i check\n' > .github/workflows/ci.yml
  assert_eq "$(weakeners)" "1" "make -i en un workflow"
  assert_contains "$(cat "$T/out")" "make con -i o -k"
}

test_makeflags_in_workflow_env_fails() {
  clean_makefile
  mkdir -p .github/workflows
  printf 'jobs:\n  check:\n    runs-on: ubuntu-latest\n    env:\n      MAKEFLAGS: i\n    steps:\n      - run: make check\n' > .github/workflows/ci.yml
  assert_eq "$(weakeners)" "1" "MAKEFLAGS en el entorno de un workflow"
  assert_contains "$(cat "$T/out")" "MAKEFLAGS"
}

test_make_variable_override_fails() {
  clean_makefile
  mkdir -p .github/workflows
  printf 'jobs:\n  check:\n    runs-on: ubuntu-latest\n    steps:\n      - run: make check .SHELLFLAGS=-c\n' > .github/workflows/ci.yml
  assert_eq "$(weakeners)" "1" "make check .SHELLFLAGS=-c"
  assert_contains "$(cat "$T/out")" "variable de make"
}

test_makeflags_in_project_script_fails() {
  clean_makefile
  mkdir -p scripts
  printf '#!/usr/bin/env bash\nMAKEFLAGS=i make check\n' > scripts/tool.sh
  assert_eq "$(weakeners)" "1" "MAKEFLAGS=i en un script"
  assert_contains "$(cat "$T/out")" "MAKEFLAGS"
}

# Round 2 of step 0.3, finding 6: the same weakeners written another way.
test_makeflags_with_several_options_fails() {
  clean_makefile
  printf 'MAKEFLAGS += -s -i\n' >> Makefile
  assert_eq "$(weakeners)" "1" "MAKEFLAGS += -s -i"
  assert_contains "$(cat "$T/out")" "MAKEFLAGS"
}

test_long_option_abbreviations_fail() {
  local line
  for line in "make --ignore check" "make --keep check" "make --keep-g check"; do
    clean_makefile
    mkdir -p .github/workflows
    printf 'jobs:\n  check:\n    runs-on: ubuntu-latest\n    steps:\n      - run: %s\n' "$line" > .github/workflows/ci.yml
    assert_eq "$(weakeners)" "1" "$line"
    assert_contains "$(cat "$T/out")" "make con -i o -k"
  done
}

test_indented_ignore_fails() {
  clean_makefile
  printf '  .IGNORE:\n' >> Makefile
  assert_eq "$(weakeners)" "1" ".IGNORE con sangría"
  assert_contains "$(cat "$T/out")" ".IGNORE"
}

test_set_plus_o_fails() {
  local line
  for line in "set +o errexit" "set +o pipefail" "set -u +e"; do
    clean_makefile
    mkdir -p scripts
    printf '#!/usr/bin/env bash\n%s\nfalse\n' "$line" > scripts/tool.sh
    assert_eq "$(weakeners)" "1" "$line"
    assert_contains "$(cat "$T/out")" "set +e"
  done
}

test_true_by_path_fails() {
  local line
  for line in 'go vet ./... || /bin/true' 'go vet ./...; /usr/bin/true'; do
    clean_makefile "$line"
    assert_eq "$(weakeners)" "1" "$line"
  done
}

test_go_test_filters_fail() {
  local filter
  for filter in "-short" "-run TestFast" "-skip TestSlow" "--run=TestFast" "-test.short"; do
    clean_makefile "go test $filter ./..."
    assert_eq "$(weakeners)" "1" "go test $filter"
    assert_contains "$(cat "$T/out")" "filtro de tests"
  done
}

run_tests "$@"
