#!/usr/bin/env bash
# Tests for scripts/harness/stop-gate.sh (Stop hook).
source "$(dirname "$0")/lib.sh"

# stop_rc <repo> [session]: runs the hook as Claude Code does; stdout goes to
# $T/stdout and stderr to $T/err; prints the exit code.
stop_rc() {
  local rc=0
  printf '{"session_id":"%s","hook_event_name":"Stop"}' "${2:-s1}" |
    CLAUDE_PROJECT_DIR="$1" "$HARNESS_DIR/stop-gate.sh" 2>"$T/err" >"$T/stdout" || rc=$?
  echo "$rc"
}

# system_message: what the hook shows the user. Stderr with exit 0 reaches
# nobody (https://code.claude.com/docs/en/hooks, "Exit code 0").
system_message() { jq -r '.systemMessage // empty' "$T/stdout"; }

# counting_makefile <repo> <exit>: `make check` appends to $T/runs and exits with <exit>.
counting_makefile() {
  printf 'check:\n\t@echo run >> %s\n\t@exit %s\n' "$T/runs" "$2" > "$1/Makefile"
}

runs() { if [ -f "$T/runs" ]; then wc -l < "$T/runs" | tr -d ' '; else echo 0; fi; }

# F-0001: the Stop hook runs `make check` with the PATH inherited from the
# process that launched Claude Code, which may lack a Go in ~/.local/go.
test_make_check_finds_go_when_path_lacks_go() {
  local bp
  bp="$(bare_path "$T/sysbin")"
  if PATH="$bp" command -v go >/dev/null; then fail "precondición: el PATH desnudo no debe tener go"; fi
  mkdir -p "$T/home/.local/go/bin"
  ln -s "$(command -v go)" "$T/home/.local/go/bin/go"
  init_repo "$T/repo"
  printf 'check:\n\tgo version\n' > "$T/repo/Makefile"
  assert_eq "$(HOME="$T/home" PATH="$bp" stop_rc "$T/repo")" "0" "exit de stop-gate ($(cat "$T/err"))"
}

# F-0004: the green cache was keyed on the names of untracked files, not their
# content, so breaking a new file after a green let Claude stop with check red.
test_untracked_file_change_invalidates_cache() {
  init_repo "$T/repo"
  counting_makefile "$T/repo" 0
  echo "v1" > "$T/repo/new_test.txt"
  assert_eq "$(stop_rc "$T/repo")" "0" "verde con el fichero nuevo"
  counting_makefile "$T/repo" 1
  echo "v2" > "$T/repo/new_test.txt"
  assert_eq "$(stop_rc "$T/repo")" "2" "tras cambiar ficheros sin seguir, make check vuelve a ejecutarse"
  assert_eq "$(runs)" "2" "make check se ejecutó dos veces"
}

# The cache key is computed on a throwaway index: the real one must never change.
test_hook_leaves_the_real_index_untouched() {
  init_repo "$T/repo"
  counting_makefile "$T/repo" 0
  echo "nuevo" > "$T/repo/untracked.txt"
  echo "cambio" >> "$T/repo/README.md"
  local before_index before_status
  before_index="$(git -C "$T/repo" ls-files -s)"
  before_status="$(git -C "$T/repo" status --porcelain)"
  assert_eq "$(stop_rc "$T/repo")" "0" "verde"
  assert_eq "$(git -C "$T/repo" ls-files -s)" "$before_index" "índice real tras el hook"
  assert_eq "$(git -C "$T/repo" status --porcelain)" "$before_status" "estado tras el hook"
}

test_without_check_target_exits_zero() {
  init_repo "$T/repo"
  printf 'build:\n\t@false\n' > "$T/repo/Makefile"
  echo change >> "$T/repo/README.md"
  assert_eq "$(stop_rc "$T/repo")" "0" "sin objetivo check"
}

test_red_check_blocks_three_times_then_allows() {
  init_repo "$T/repo"
  counting_makefile "$T/repo" 1
  echo change >> "$T/repo/README.md"
  assert_eq "$(stop_rc "$T/repo")" "2" "primer bloqueo"
  assert_contains "$(cat "$T/err")" "STOP GATE (1/3)"
  assert_eq "$(stop_rc "$T/repo")" "2" "segundo bloqueo"
  assert_contains "$(cat "$T/err")" "STOP GATE (2/3)"
  assert_eq "$(stop_rc "$T/repo")" "2" "tercer bloqueo"
  assert_contains "$(cat "$T/err")" "sigue en rojo tras 3 intentos"
  assert_eq "$(stop_rc "$T/repo")" "0" "cuarto intento: se permite parar"
  assert_contains "$(system_message)" "make check sigue en rojo" "Marcos ve que Claude paró con check en rojo"
}

test_pause_file_allows_stop_and_shows_reason() {
  init_repo "$T/repo"
  counting_makefile "$T/repo" 1
  echo change >> "$T/repo/README.md"
  mkdir -p "$T/repo/.harness"
  echo "falta az login de Marcos" > "$T/repo/.harness/pausa-marcos"
  assert_eq "$(stop_rc "$T/repo")" "0" "pausa para Marcos"
  assert_contains "$(system_message)" "falta az login de Marcos" "el motivo llega a Marcos"
  assert_eq "$(runs)" "0" "con pausa no se ejecuta make check"
  [ ! -e "$T/repo/.harness/pausa-marcos" ] || fail "la pausa se consume al usarla"
}

test_green_is_cached_and_resets_counter() {
  init_repo "$T/repo"
  counting_makefile "$T/repo" 1
  echo change >> "$T/repo/README.md"
  assert_eq "$(stop_rc "$T/repo")" "2" "rojo"
  assert_eq "$(stop_rc "$T/repo")" "2" "rojo otra vez"
  counting_makefile "$T/repo" 0
  assert_eq "$(stop_rc "$T/repo")" "0" "verde"
  local before
  before="$(runs)"
  assert_eq "$(stop_rc "$T/repo")" "0" "mismo árbol"
  assert_eq "$(runs)" "$before" "el mismo árbol no vuelve a ejecutar make check"
  counting_makefile "$T/repo" 1
  assert_eq "$(stop_rc "$T/repo")" "2" "rojo tras el verde"
  assert_contains "$(cat "$T/err")" "STOP GATE (1/3)" "el contador volvió a cero"
}

test_clean_tree_without_unpushed_commits_exits_zero() {
  init_repo "$T/repo"
  git init -q --bare "$T/remote.git"
  git -C "$T/repo" remote add origin "$T/remote.git"
  git -C "$T/repo" push -q origin main
  counting_makefile "$T/repo" 1
  git -C "$T/repo" add Makefile
  git -C "$T/repo" commit -q -m makefile
  git -C "$T/repo" push -q origin main
  assert_eq "$(stop_rc "$T/repo")" "0" "árbol limpio y todo subido"
  assert_eq "$(runs)" "0" "no ejecuta make check"
}

run_tests "$@"
