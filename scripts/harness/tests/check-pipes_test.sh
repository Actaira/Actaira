#!/usr/bin/env bash
# Tests for scripts/harness/check-pipes.sh (L-000e, F-0012): with pipefail, a
# pipe into a reader that exits early (head, grep -q/-m/-l) fails with 141
# when the writer is still writing, which reads as a false red or a false green.
source "$(dirname "$0")/lib.sh"
# The fixtures write the pipes as '|'' head' so that this file itself does not
# contain the pattern the lint looks for.

pipes() { # prints the exit code; output in $T/out
  local rc=0
  "$HARNESS_DIR/check-pipes.sh" >"$T/out" 2>&1 || rc=$?
  echo "$rc"
}

script_with() { # <line>: scripts/x.sh containing the line
  mkdir -p scripts
  printf '#!/usr/bin/env bash\nset -euo pipefail\n%s\n' "$1" > scripts/x.sh
}

test_clean_scripts_pass() {
  script_with 'if grep -q x <<< "$v"; then echo y; fi'
  printf 'check:\n\tgo test ./...\n' > Makefile
  assert_eq "$(pipes)" "0" "sin tuberías a lectores que salen antes ($(cat "$T/out"))"
}

test_pipe_into_head_fails() {
  script_with 'first="$(grep -v x file |'' head -n 2)"'
  assert_eq "$(pipes)" "1" "| head"
  assert_contains "$(cat "$T/out")" "scripts/x.sh:3"
}

test_pipe_into_grep_quiet_fails() {
  local line
  for line in 'git log |'' grep -q x' 'cmd |'' grep -qE x' 'cmd |'' grep -m1 x' 'cmd |'' grep -l x'; do
    script_with "$line"
    assert_eq "$(pipes)" "1" "$line"
  done
}

test_or_list_and_here_strings_pass() {
  script_with 'if [ -z "$a" ] || grep -q x <<< "$v"; then echo y; fi'
  assert_eq "$(pipes)" "0" "|| no es una tubería ($(cat "$T/out"))"
}

test_makefile_and_hooks_without_extension_are_checked() {
  printf 'check:\n\tgit log |'' head -1\n' > Makefile
  assert_eq "$(pipes)" "1" "Makefile"
  rm Makefile
  mkdir -p scripts/harness
  printf '#!/usr/bin/env bash\ngit log |'' head -1\n' > scripts/harness/pre-push
  assert_eq "$(pipes)" "1" "hook de git sin extensión"
}

run_tests "$@"
