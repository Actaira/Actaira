#!/usr/bin/env bash
# Tests for scripts/harness/secrets-scan.sh. They use the pinned gitleaks
# ($GITLEAKS, exported by the Makefile) with a sentinel rule, so no fixture
# ever looks like a real credential.
source "$(dirname "$0")/lib.sh"

: "${GITLEAKS:?GITLEAKS debe apuntar al gitleaks fijado (lo exporta el Makefile)}"
GITLEAKS="$(cd "$(dirname "$GITLEAKS")" && pwd)/$(basename "$GITLEAKS")"

SENTINEL="ACTAIRA_TEST_SENTINEL_123456"
# gitleaks' inline allow marker, built in two parts so that no file of this
# repo contains it literally (secrets-scan.sh would demand a FALLOS entry).
ALLOW="gitleaks"":allow"

SENTINEL_RULE='[[rules]]
id = "actaira-test-sentinel"
description = "Test sentinel, not a credential"
regex = '"'''"'ACTAIRA_TEST_SENTINEL_[0-9]{6}'"'''"'
'

# scan <repo>: runs the scan from inside the repo with --config pointing at
# the sentinel rule only. Prints the output.
scan() {
  printf '%s' "$SENTINEL_RULE" > "$T/sentinel.toml"
  (cd "$1" && "$HARNESS_DIR/secrets-scan.sh" --config "$T/sentinel.toml" "$GITLEAKS" 2>&1)
}

# scan_repo_config <repo>: the production path (`make secrets`): no --config,
# gitleaks finds the repo's own .gitleaks.toml.
scan_repo_config() {
  (cd "$1" && "$HARNESS_DIR/secrets-scan.sh" "$GITLEAKS" 2>&1)
}

# commit_config <repo> [sin-defaults]: a tracked .gitleaks.toml with the
# sentinel rule, extending the default rules unless "sin-defaults" is given.
commit_config() {
  {
    if [ "${2:-}" != "sin-defaults" ]; then printf '[extend]\nuseDefault = true\n\n'; fi
    printf '%s' "$SENTINEL_RULE"
  } > "$1/.gitleaks.toml"
  git -C "$1" add .gitleaks.toml
  git -C "$1" commit -q -m config
}

# record_fallo <repo> <id>: a FALLOS.md with one entry, the justification
# that .gitleaksignore entries and inline allow comments must cite.
record_fallo() {
  mkdir -p "$1/docs/harness"
  printf '# Registro de fallos\n\n## Entradas\n\n## %s Fixture de prueba\n- guardia: regla:.claude/rules/go.md\n' "$2" \
    > "$1/docs/harness/FALLOS.md"
}

# assert_detected <output>: the sentinel was really found (not a crash or usage error).
assert_detected() {
  assert_contains "$1" "actaira-test-sentinel" "hallazgo del centinela en la salida"
  assert_contains "$1" "leaks found" "gitleaks informa del hallazgo"
}

test_clean_repo_passes() {
  init_repo "$T/repo"
  local out rc=0
  out="$(scan "$T/repo")" || rc=$?
  assert_eq "$rc" "0" "exit en repo limpio ($out)"
}

# E0 closing review (security, finding 4): a token in a commit message would
# enter main, where it can no longer be rewritten.
test_sentinel_in_a_commit_message_fails() {
  init_repo "$T/repo"
  git -C "$T/repo" commit -q --allow-empty -m "Add notes" -m "value $SENTINEL"
  local out rc=0
  out="$(scan "$T/repo")" || rc=$?
  assert_eq "$rc" "1" "centinela en un mensaje de commit"
  assert_detected "$out"
  assert_contains "$out" "commit-messages.txt"
  assert_not_contains "$out" "$SENTINEL" "la salida debe ir redactada"
}

# E0 closing review (integration, finding 3): only the history HEAD reaches is
# scanned, so a finding on an abandoned branch cannot turn every check red.
test_sentinel_only_on_another_branch_passes() {
  init_repo "$T/repo"
  git -C "$T/repo" switch -q -c other
  echo "value $SENTINEL" > "$T/repo/leak.txt"
  git -C "$T/repo" add leak.txt
  git -C "$T/repo" commit -q -m "Leak on another branch"
  git -C "$T/repo" switch -q main
  local out rc=0
  out="$(scan "$T/repo")" || rc=$?
  assert_eq "$rc" "0" "centinela solo en otra rama ($out)"
}

test_repo_without_commits_passes() {
  git init -q -b main "$T/repo"
  echo "nada secreto" > "$T/repo/file.txt"
  git -C "$T/repo" add file.txt
  local out rc=0
  out="$(scan "$T/repo")" || rc=$?
  assert_eq "$rc" "0" "repo sin commits ($out)"
}

test_committed_sentinel_fails() {
  init_repo "$T/repo"
  echo "value $SENTINEL" > "$T/repo/config.txt"
  git -C "$T/repo" add config.txt
  git -C "$T/repo" commit -q -m leak
  git -C "$T/repo" rm -q config.txt
  git -C "$T/repo" commit -q -m "remove leak"
  local out rc=0
  out="$(scan "$T/repo")" || rc=$?
  assert_eq "$rc" "1" "exit con secreto en el historial"
  assert_detected "$out"
  assert_not_contains "$out" "$SENTINEL" "la salida debe ir redactada"
}

# The scan directory is a mktemp under $TMPDIR: pointing TMPDIR at a known
# directory lets the test check that no path of the scan directory leaks out.
test_untracked_sentinel_fails_with_repo_relative_path() {
  init_repo "$T/repo"
  echo "value $SENTINEL" > "$T/repo/new.txt"
  mkdir -p "$T/scantmp"
  local out rc=0
  out="$(TMPDIR="$T/scantmp" scan "$T/repo")" || rc=$?
  assert_eq "$rc" "1" "exit con secreto en un fichero nuevo sin commitear"
  assert_contains "$out" "Fingerprint: new.txt:actaira-test-sentinel:1" "huella relativa al repo, estable para .gitleaksignore"
  assert_not_contains "$out" "$T/scantmp" "ninguna ruta del directorio del escaneo"
  assert_not_contains "$out" "$SENTINEL" "la salida debe ir redactada"
}

test_modified_tracked_sentinel_fails() {
  init_repo "$T/repo"
  echo "value $SENTINEL" >> "$T/repo/README.md"
  local out rc=0
  out="$(scan "$T/repo")" || rc=$?
  assert_eq "$rc" "1" "exit con secreto en un fichero modificado"
  assert_detected "$out"
}

test_staged_sentinel_removed_from_worktree_fails() {
  init_repo "$T/repo"
  echo "value $SENTINEL" >> "$T/repo/README.md"
  git -C "$T/repo" add README.md
  git -C "$T/repo" show HEAD:README.md > "$T/repo/README.md"
  local out rc=0
  out="$(scan "$T/repo")" || rc=$?
  assert_eq "$rc" "1" "un secreto preparado con git add se commitearía aunque ya no esté en el fichero"
  assert_detected "$out"
}

test_ignored_files_are_not_scanned() {
  init_repo "$T/repo"
  printf '.env\n.tools/\n' > "$T/repo/.gitignore"
  git -C "$T/repo" add .gitignore
  git -C "$T/repo" commit -q -m ignore
  mkdir -p "$T/repo/.tools"
  echo "value $SENTINEL" > "$T/repo/.env"
  echo "value ACTAIRA_TEST_SENTINEL_654321" > "$T/repo/.tools/blob"
  local out rc=0
  out="$(scan "$T/repo")" || rc=$?
  assert_eq "$rc" "0" "los ficheros ignorados son locales y no se escanean ($out)"
}

# F-0002: a nested repo (a subagent worktree in .claude/worktrees/) is listed
# by git as a directory entry; copying it recursively scanned its ignored files.
test_nested_repo_is_not_scanned() {
  init_repo "$T/repo"
  git init -q -b main "$T/repo/.claude/worktrees/agent-x"
  printf '.env\n' > "$T/repo/.claude/worktrees/agent-x/.gitignore"
  echo "value $SENTINEL" > "$T/repo/.claude/worktrees/agent-x/.env"
  local out rc=0
  out="$(scan "$T/repo")" || rc=$?
  assert_eq "$rc" "0" "el .env ignorado de una repo anidada no se commitea ($out)"
}

test_deleted_tracked_file_does_not_break_scan() {
  init_repo "$T/repo"
  rm "$T/repo/README.md"
  local out rc=0
  out="$(scan "$T/repo")" || rc=$?
  assert_eq "$rc" "0" "un fichero borrado sin commitear no rompe el escaneo ($out)"
}

test_repo_config_is_used_without_config_flag() {
  init_repo "$T/repo"
  commit_config "$T/repo"
  echo "value $SENTINEL" > "$T/repo/new.txt"
  local out rc=0
  out="$(scan_repo_config "$T/repo")" || rc=$?
  assert_eq "$rc" "1" "el .gitleaks.toml del repo se usa en make secrets"
  assert_detected "$out"
}

# The commit messages are scanned outside the repo directory: the repo's own
# .gitleaks.toml has to reach that scan too.
test_repo_config_applies_to_commit_messages() {
  init_repo "$T/repo"
  commit_config "$T/repo"
  git -C "$T/repo" commit -q --allow-empty -m "Add notes" -m "value $SENTINEL"
  local out rc=0
  out="$(scan_repo_config "$T/repo")" || rc=$?
  assert_eq "$rc" "1" "el .gitleaks.toml del repo se aplica a los mensajes de commit"
  assert_detected "$out"
  assert_contains "$out" "commit-messages.txt"
}

# F-0005: GITLEAKS_CONFIG and GITLEAKS_CONFIG_TOML outrank the repo's
# .gitleaks.toml in gitleaks; a config with only the default rules does not
# know the sentinel, so if the environment won, the scan would pass.
test_environment_cannot_replace_the_config() {
  init_repo "$T/repo"
  commit_config "$T/repo"
  echo "value $SENTINEL" > "$T/repo/new.txt"
  printf '[extend]\nuseDefault = true\n' > "$T/defaults-only.toml"
  local out rc=0
  out="$(GITLEAKS_CONFIG="$T/defaults-only.toml" GITLEAKS_CONFIG_TOML="$(cat "$T/defaults-only.toml")" \
    scan_repo_config "$T/repo")" || rc=$?
  assert_eq "$rc" "1" "GITLEAKS_CONFIG del entorno no puede apagar el escaneo"
  assert_detected "$out"
}

test_untracked_repo_config_fails() {
  init_repo "$T/repo"
  printf '[extend]\nuseDefault = true\n' > "$T/repo/.gitleaks.toml"
  local out rc=0
  out="$(scan_repo_config "$T/repo")" || rc=$?
  assert_eq "$rc" "1" "un .gitleaks.toml sin seguir no puede cambiar las reglas"
  assert_contains "$out" ".gitleaks.toml"
}

test_repo_config_without_default_rules_fails() {
  init_repo "$T/repo"
  commit_config "$T/repo" sin-defaults
  local out rc=0
  out="$(scan_repo_config "$T/repo")" || rc=$?
  assert_eq "$rc" "1" "un .gitleaks.toml que no extiende las reglas por defecto las apaga"
  assert_contains "$out" "useDefault"
}

test_untracked_gitleaksignore_fails() {
  init_repo "$T/repo"
  record_fallo "$T/repo" F-0007
  printf '# F-0007 fixture\nnew.txt:actaira-test-sentinel:1\n' > "$T/repo/.gitleaksignore"
  local out rc=0
  out="$(scan "$T/repo")" || rc=$?
  assert_eq "$rc" "1" "un .gitleaksignore sin seguir no puede ocultar hallazgos"
  assert_contains "$out" ".gitleaksignore"
}

# F-0006: an ignore entry must cite, in the comment line just above it, a
# FALLOS.md entry that justifies it.
test_gitleaksignore_entry_without_fallo_fails() {
  init_repo "$T/repo"
  record_fallo "$T/repo" F-0007
  printf 'new.txt:actaira-test-sentinel:1\n' > "$T/repo/.gitleaksignore"
  git -C "$T/repo" add .gitleaksignore
  local out rc=0
  out="$(scan "$T/repo")" || rc=$?
  assert_eq "$rc" "1" "entrada de .gitleaksignore sin F-NNNN encima"
  assert_contains "$out" "new.txt:actaira-test-sentinel:1"
}

test_gitleaksignore_entry_with_unknown_fallo_fails() {
  init_repo "$T/repo"
  record_fallo "$T/repo" F-0007
  printf '# F-0999 no existe\nnew.txt:actaira-test-sentinel:1\n' > "$T/repo/.gitleaksignore"
  git -C "$T/repo" add .gitleaksignore
  local rc=0
  scan "$T/repo" >/dev/null || rc=$?
  assert_eq "$rc" "1" "entrada de .gitleaksignore que cita un fallo inexistente"
}

test_justified_gitleaksignore_entry_hides_the_finding() {
  init_repo "$T/repo"
  record_fallo "$T/repo" F-0007
  printf '# F-0007 fixture\nnew.txt:actaira-test-sentinel:1\n' > "$T/repo/.gitleaksignore"
  git -C "$T/repo" add .gitleaksignore
  echo "value $SENTINEL" > "$T/repo/new.txt"
  local out rc=0
  out="$(scan "$T/repo")" || rc=$?
  assert_eq "$rc" "0" "una entrada justificada oculta su hallazgo ($out)"
}

test_allow_comment_without_fallo_fails() {
  init_repo "$T/repo"
  record_fallo "$T/repo" F-0007
  echo "value $SENTINEL # $ALLOW" > "$T/repo/new.txt"
  local out rc=0
  out="$(scan "$T/repo")" || rc=$?
  assert_eq "$rc" "1" "comentario allow sin F-NNNN"
  assert_contains "$out" "new.txt:1"
}

test_allow_comment_with_unknown_fallo_fails() {
  init_repo "$T/repo"
  record_fallo "$T/repo" F-0007
  echo "value $SENTINEL # $ALLOW F-0999" > "$T/repo/new.txt"
  local rc=0
  scan "$T/repo" >/dev/null || rc=$?
  assert_eq "$rc" "1" "comentario allow que cita un fallo inexistente"
}

# Round 1 of step 0.3, finding 10: an F-NNNN in the path is not a justification.
test_fallo_in_the_path_does_not_justify_an_allow_comment() {
  init_repo "$T/repo"
  record_fallo "$T/repo" F-0007
  mkdir -p "$T/repo/docs/F-0007"
  echo "value $SENTINEL # $ALLOW" > "$T/repo/docs/F-0007/new.txt"
  local out rc=0
  out="$(scan "$T/repo")" || rc=$?
  assert_eq "$rc" "1" "F-NNNN solo en la ruta"
  assert_contains "$out" "docs/F-0007/new.txt:1"
}

test_justified_allow_comment_hides_the_finding() {
  init_repo "$T/repo"
  record_fallo "$T/repo" F-0007
  echo "value $SENTINEL # $ALLOW F-0007" > "$T/repo/new.txt"
  local out rc=0
  out="$(scan "$T/repo")" || rc=$?
  assert_eq "$rc" "0" "un comentario allow justificado oculta su línea ($out)"
}

run_tests "$@"
