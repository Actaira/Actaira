#!/usr/bin/env bash
# Tests for scripts/harness/post-edit.sh (PostToolUse hook).
source "$(dirname "$0")/lib.sh"

# post_edit <file>: runs the hook as Claude Code does, with a JSON payload on stdin.
post_edit() {
  jq -n --arg f "$1" '{tool_name:"Write",tool_input:{file_path:$f}}' |
    CLAUDE_PROJECT_DIR="$T" "$HARNESS_DIR/post-edit.sh"
}

# fake_home_with_go <home>: a HOME whose ~/.local/go/bin holds the real Go
# tools (as a user install without sudo does), so the test does not depend
# on where Go lives on this machine or in CI.
fake_home_with_go() {
  local real_gofmt real_go
  real_gofmt="$(command -v gofmt)" || fail "gofmt no está en el PATH de los tests"
  real_go="$(command -v go)" || fail "go no está en el PATH de los tests"
  mkdir -p "$1/.local/go/bin"
  ln -s "$real_gofmt" "$1/.local/go/bin/gofmt"
  ln -s "$real_go" "$1/.local/go/bin/go"
}

# F-0001: hooks inherit the PATH of the process that launched Claude Code,
# which may not include a Go installed in ~/.local/go.
test_gofmt_found_when_path_lacks_go() {
  local bp out
  bp="$(bare_path "$T/sysbin")"
  if PATH="$bp" command -v gofmt >/dev/null; then fail "precondición: el PATH desnudo no debe tener gofmt"; fi
  fake_home_with_go "$T/home"
  printf 'package probe\nfunc   Probe( )int{\nreturn    1 }\n' > "$T/probe.go"
  out="$(HOME="$T/home" PATH="$bp" post_edit "$T/probe.go")"
  assert_not_contains "$out" "additionalContext" "el hook no debe informar de fallo"
  assert_eq "$(cat "$T/probe.go")" "$(printf 'package probe\n\nfunc Probe() int {\n\treturn 1\n}\n')" "probe.go formateado"
}

# PostToolUse cannot block: a file gofmt cannot parse is reported back to
# Claude as additionalContext (valid JSON), the hook exits 0, the file is untouched.
test_syntax_error_is_reported_as_additional_context() {
  local content out rc=0
  content="$(printf 'package probe\nfunc Broken( {\n')"
  printf '%s\n' "$content" > "$T/broken.go"
  out="$(post_edit "$T/broken.go")" || rc=$?
  assert_eq "$rc" "0" "exit del hook"
  jq -e '.hookSpecificOutput.hookEventName == "PostToolUse"' <<< "$out" >/dev/null ||
    fail "la salida no es el JSON de PostToolUse: [$out]"
  assert_contains "$(jq -r '.hookSpecificOutput.additionalContext' <<< "$out")" "gofmt failed on $T/broken.go"
  assert_eq "$(cat "$T/broken.go")" "$content" "el fichero roto no se toca"
}

test_non_go_files_are_left_alone() {
  printf 'x  =  1\n' > "$T/notes.txt"
  local out
  out="$(post_edit "$T/notes.txt")"
  assert_eq "$out" "" "sin salida para un fichero que no formatea"
  assert_eq "$(cat "$T/notes.txt")" "x  =  1" "el fichero no cambia"
}

run_tests "$@"
