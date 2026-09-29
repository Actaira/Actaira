#!/usr/bin/env bash
# Tests for scripts/harness/check-attribution.sh and the commit-msg hook.
# Marcos, 2026-09-28: no commit carries Claude co-authorship or attribution.
source "$(dirname "$0")/lib.sh"

# The trailer and footer Claude Code adds by default, built here and only
# committed in throwaway repos; plus one variant per rule of the check, so a
# test fails if that single rule is removed.
CLAUDE_TRAILER="Co-Authored-By: Claude <noreply@""anthropic.com>"
CLAUDE_FOOTER="Generated with [Claude"" Code](https://claude.com/claude-code)"
COAUTHOR_ONLY="Co-authored-by: Claude Opus <claude-bot@example.invalid>"
NOREPLY_ONLY="Signed-off-by: Release Bot <noreply@""anthropic.com>"

attribution() { # <repo> [args...]; prints the exit code; output in $T/out
  local repo="$1" rc=0
  shift
  (cd "$repo" && "$HARNESS_DIR/check-attribution.sh" "$@") >"$T/out" 2>&1 || rc=$?
  echo "$rc"
}

commit_msg() { # <repo> <message...>: an empty commit with the given -m parts
  local repo="$1"
  shift
  local args=() m
  for m in "$@"; do args+=(-m "$m"); done
  git -C "$repo" commit -q --allow-empty --no-verify "${args[@]}"
}

# repo_with_origin: $T/repo with main pushed to a bare origin, on branch e0/paso-9-x.
repo_with_origin() {
  init_repo "$T/repo"
  git init -q --bare "$T/origin.git"
  git -C "$T/repo" remote add origin "$T/origin.git"
  git -C "$T/repo" push -q -u origin main
  git -C "$T/repo" switch -q -c e0/paso-9-x
}

test_clean_history_passes() {
  init_repo "$T/repo"
  commit_msg "$T/repo" "Add feature" "Co-authored-by: Persona Ficticia <persona@example.invalid>"
  assert_eq "$(attribution "$T/repo")" "0" "historia sin atribución de Claude ($(cat "$T/out"))"
}

test_default_claude_code_trailer_fails() {
  init_repo "$T/repo"
  commit_msg "$T/repo" "Add feature" "$CLAUDE_TRAILER"
  assert_eq "$(attribution "$T/repo")" "1" "trailer por defecto de Claude Code"
}

test_claude_coauthor_trailer_fails() {
  init_repo "$T/repo"
  commit_msg "$T/repo" "Add feature" "$COAUTHOR_ONLY"
  local sha
  sha="$(git -C "$T/repo" rev-parse --short HEAD)"
  assert_eq "$(attribution "$T/repo")" "1" "commit con coautoría de Claude"
  assert_contains "$(cat "$T/out")" "$sha"
}

test_anthropic_noreply_address_fails() {
  init_repo "$T/repo"
  commit_msg "$T/repo" "Add feature" "$NOREPLY_ONLY"
  assert_eq "$(attribution "$T/repo")" "1" "dirección noreply de Anthropic"
}

test_generated_with_claude_footer_fails() {
  init_repo "$T/repo"
  commit_msg "$T/repo" "Add feature" "$CLAUDE_FOOTER"
  assert_eq "$(attribution "$T/repo")" "1" "commit con la línea Generated with Claude Code"
}

test_claude_as_commit_author_fails() {
  init_repo "$T/repo"
  git -C "$T/repo" commit -q --allow-empty --no-verify -m "Add feature" --author="Claude <bot@example.invalid>"
  assert_eq "$(attribution "$T/repo")" "1" "commit con Claude como autor"
}

# F-0009: Actaira talks about Claude all the time; only attribution counts.
test_product_text_mentioning_claude_passes() {
  init_repo "$T/repo"
  commit_msg "$T/repo" "Parse .mcp.json files generated with claude mcp add" \
    "Detect Claude Code hooks and Anthropic SDK calls in the analysed repo." \
    "Co-authored-by: Claude Dupont <claude.dupont@example.invalid>"
  assert_eq "$(attribution "$T/repo")" "0" "texto del producto ($(cat "$T/out"))"
}

test_attribution_in_an_old_commit_of_the_branch_fails() {
  repo_with_origin
  commit_msg "$T/repo" "Old" "$CLAUDE_TRAILER"
  commit_msg "$T/repo" "Newer and clean"
  assert_eq "$(attribution "$T/repo")" "1" "atribución en un commit anterior de la rama"
}

# F-0009: what is already in main cannot be fixed without rewriting it, so it
# must not turn every branch red forever; the branch is what gets checked.
test_attribution_already_in_main_does_not_block_branches() {
  init_repo "$T/repo"
  commit_msg "$T/repo" "Squash from the past" "$CLAUDE_FOOTER"
  git init -q --bare "$T/origin.git"
  git -C "$T/repo" remote add origin "$T/origin.git"
  git -C "$T/repo" push -q -u origin main
  git -C "$T/repo" switch -q -c e0/paso-9-x
  commit_msg "$T/repo" "Clean work on the branch"
  assert_eq "$(attribution "$T/repo")" "0" "rama limpia sobre un main con atribución ($(cat "$T/out"))"
  commit_msg "$T/repo" "More work" "$CLAUDE_TRAILER"
  assert_eq "$(attribution "$T/repo")" "1" "atribución en la rama"
}

test_shallow_clone_fails() {
  init_repo "$T/repo"
  commit_msg "$T/repo" "Second"
  git clone -q --depth 1 "file://$T/repo" "$T/shallow"
  assert_eq "$(attribution "$T/shallow")" "1" "clon superficial"
  assert_contains "$(cat "$T/out")" "superficial"
}

test_message_file_mode() {
  init_repo "$T/repo"
  printf 'Add feature\n\n%s\n' "$CLAUDE_TRAILER" > "$T/bad-msg"
  printf 'Add feature\n' > "$T/good-msg"
  assert_eq "$(attribution "$T/repo" --message "$T/bad-msg")" "1" "mensaje con coautoría de Claude"
  assert_eq "$(attribution "$T/repo" --message "$T/good-msg")" "0" "mensaje limpio"
}

test_message_mode_ignores_letter_case() {
  init_repo "$T/repo"
  printf 'Add feature\n\nCO-AUTHORED-BY: CLAUDE OPUS <BOT@EXAMPLE.INVALID>\n' > "$T/msg"
  assert_eq "$(attribution "$T/repo" --message "$T/msg")" "1" "coautoría en mayúsculas"
}

# git keeps lines starting with # when the message comes from -m or -F.
test_message_mode_checks_comment_lines() {
  init_repo "$T/repo"
  printf 'Add feature\n\n# %s\n' "$COAUTHOR_ONLY" > "$T/msg"
  assert_eq "$(attribution "$T/repo" --message "$T/msg")" "1" "atribución en una línea que empieza por #"
}

# install_hook <repo>: the commit-msg hook as git runs it, without scripts/harness in the repo.
install_hook() {
  cp "$HARNESS_DIR/commit-msg" "$1/.git/hooks/commit-msg"
  chmod +x "$1/.git/hooks/commit-msg"
}

test_commit_msg_hook_rejects_attribution() {
  init_repo "$T/repo"
  install_hook "$T/repo"
  local before rc=0
  before="$(git -C "$T/repo" rev-parse HEAD)"
  git -C "$T/repo" commit -q --allow-empty -m "Add feature" -m "$CLAUDE_TRAILER" 2>"$T/err" || rc=$?
  [ "$rc" -ne 0 ] || fail "el hook dejó pasar un commit con coautoría de Claude"
  assert_contains "$(cat "$T/err")" "atribución de Claude"
  assert_eq "$(git -C "$T/repo" rev-parse HEAD)" "$before" "no se creó el commit"
}

# The hook lives in the hooks directory shared by every worktree and branch,
# also those without scripts/harness/: it must not depend on them.
test_commit_msg_hook_works_without_the_harness_scripts() {
  init_repo "$T/repo"
  install_hook "$T/repo"
  [ ! -e "$T/repo/scripts" ] || fail "precondición: el repo no tiene scripts/"
  git -C "$T/repo" commit -q --allow-empty -m "Clean commit" 2>"$T/err" || fail "rechazó un commit limpio: $(cat "$T/err")"
}

test_hook_and_script_use_the_same_pattern() {
  local hook script
  hook="$(grep -E "^pattern='" "$HARNESS_DIR/commit-msg")"
  script="$(grep -E "^pattern='" "$HARNESS_DIR/check-attribution.sh")"
  [ -n "$hook" ] || fail "commit-msg no define pattern="
  assert_eq "$hook" "$script" "patrón del hook y del script"
}

run_tests "$@"
