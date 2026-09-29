#!/usr/bin/env bash
# Tests for scripts/harness/install.sh. The package is rebuilt from this repo
# with the same layout as ~/actaira-ws/paquete, so the test needs nothing
# outside the repo.
source "$(dirname "$0")/lib.sh"

# make_package <dir>: harness/{.claude,CLAUDE.md,docs/harness,scripts/harness}, PLAN.md, 10_llm.md, epicas/.
make_package() {
  local p="$1"
  mkdir -p "$p/harness/docs" "$p/harness/scripts" "$p/harness/.claude" "$p/epicas"
  cp -a "$REPO_DIR/.claude/settings.json" "$REPO_DIR/.claude/agents" "$REPO_DIR/.claude/rules" \
    "$REPO_DIR/.claude/skills" "$p/harness/.claude/"
  cp "$REPO_DIR/CLAUDE.md" "$p/harness/CLAUDE.md"
  cp -a "$REPO_DIR/docs/harness" "$p/harness/docs/harness"
  cp -a "$REPO_DIR/scripts/harness" "$p/harness/scripts/harness"
  cp "$REPO_DIR/docs/PLAN.md" "$p/PLAN.md"
  cp "$REPO_DIR/docs/LLM.md" "$p/10_llm.md"
  cp -a "$REPO_DIR/docs/epicas/." "$p/epicas/"
}

install_into() { # repo
  "$HARNESS_DIR/install.sh" "$T/pkg" "$1" >/dev/null
}

test_installs_settings_scripts_and_pre_push() {
  make_package "$T/pkg"
  init_repo "$T/repo"
  install_into "$T/repo"
  jq -e . "$T/repo/.claude/settings.json" >/dev/null || fail "settings.json no es JSON válido"
  local s
  for s in guard-git.sh post-edit.sh stop-gate.sh check-weakeners.sh check-fallos.sh; do
    [ -x "$T/repo/scripts/harness/$s" ] || fail "$s no es ejecutable"
  done
  [ -x "$T/repo/.git/hooks/pre-push" ] || fail "falta el pre-push"
  [ -x "$T/repo/.git/hooks/commit-msg" ] || fail "falta el commit-msg"
  cmp -s "$T/repo/.git/hooks/commit-msg" "$REPO_DIR/scripts/harness/commit-msg" || fail "el commit-msg instalado no es scripts/harness/commit-msg"
  [ -f "$T/repo/docs/PLAN.md" ] && [ -f "$T/repo/docs/LLM.md" ] && [ -f "$T/repo/docs/epicas/E0.md" ] ||
    fail "faltan PLAN.md, LLM.md o las épicas"
  grep -qxF '* text=auto eol=lf' "$T/repo/.gitattributes" || fail ".gitattributes sin eol=lf"
  grep -qxF '.harness/' "$T/repo/.gitignore" || fail ".gitignore sin .harness/"
}

test_pre_push_rejects_main() {
  make_package "$T/pkg"
  init_repo "$T/repo"
  install_into "$T/repo"
  git init -q --bare "$T/remote.git"
  git -C "$T/repo" remote add origin "$T/remote.git"
  local rc=0
  git -C "$T/repo" push -q origin main 2>"$T/err" || rc=$?
  [ "$rc" -ne 0 ] || fail "el pre-push dejó subir a main"
  assert_contains "$(cat "$T/err")" "push directo a main prohibido"
  git -C "$T/repo" switch -q -c e0/paso-9-x
  git -C "$T/repo" push -q origin e0/paso-9-x || fail "el pre-push bloqueó una rama de paso"
}

test_reinstall_keeps_fallos_with_entries() {
  make_package "$T/pkg"
  init_repo "$T/repo"
  install_into "$T/repo"
  printf '\n## F-0042 Fallo propio del repo\n- guardia: regla:.claude/rules/go.md\n' >> "$T/repo/docs/harness/FALLOS.md"
  local before
  before="$(cat "$T/repo/docs/harness/FALLOS.md")"
  install_into "$T/repo"
  assert_eq "$(cat "$T/repo/docs/harness/FALLOS.md")" "$before" "FALLOS.md tras reinstalar"
}

test_stale_package_is_refused_before_touching_the_repo() {
  make_package "$T/pkg"
  rm "$T/pkg/harness/scripts/harness/env.sh" "$T/pkg/harness/scripts/harness/pre-push"
  init_repo "$T/repo"
  local out rc=0
  out="$("$HARNESS_DIR/install.sh" "$T/pkg" "$T/repo" 2>&1)" || rc=$?
  assert_eq "$rc" "1" "paquete antiguo"
  assert_contains "$out" "paquete incompleto o antiguo"
  [ ! -e "$T/repo/.claude" ] || fail "no debe copiar nada de un paquete antiguo"
}

test_subdirectory_of_a_repo_is_refused() {
  make_package "$T/pkg"
  init_repo "$T/repo"
  mkdir -p "$T/repo/docs"
  local rc=0
  "$HARNESS_DIR/install.sh" "$T/pkg" "$T/repo/docs" >/dev/null 2>&1 || rc=$?
  assert_eq "$rc" "1" "instalar en un subdirectorio del repo"
  [ ! -e "$T/repo/docs/.claude" ] || fail "no debe instalar dentro de docs/"
}

test_failed_reinstall_keeps_fallos_entries() {
  make_package "$T/pkg"
  init_repo "$T/repo"
  install_into "$T/repo"
  printf '\n## F-0042 Fallo propio del repo\n- guardia: regla:.claude/rules/go.md\n' >> "$T/repo/docs/harness/FALLOS.md"
  local before rc=0
  before="$(cat "$T/repo/docs/harness/FALLOS.md")"
  # docs/estado as a file makes the reinstall fail after the package copy.
  rm -r "$T/repo/docs/estado"
  touch "$T/repo/docs/estado"
  "$HARNESS_DIR/install.sh" "$T/pkg" "$T/repo" >/dev/null 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "precondición: la reinstalación debía fallar"
  assert_eq "$(cat "$T/repo/docs/harness/FALLOS.md")" "$before" "FALLOS.md tras una reinstalación fallida"
}

run_tests "$@"
