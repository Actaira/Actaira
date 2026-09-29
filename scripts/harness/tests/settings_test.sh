#!/usr/bin/env bash
# Tests for .claude/settings.json (permissions and hook wiring).
source "$(dirname "$0")/lib.sh"

# Fixed path: a guard never takes the file it checks from the environment
# (F-0008). Mutation proofs work on a copy of the whole tree, so the live
# settings.json is never edited while Claude Code runs on it.
SETTINGS="$REPO_DIR/.claude/settings.json"
ENV_LINE='source "$(dirname "${BASH_SOURCE[0]}")/env.sh"'

# hook_scripts: repo-relative path of every hook command in settings.json.
hook_scripts() {
  jq -r '.hooks[][].hooks[].command' "$SETTINGS" | sed -E 's#^"?\$CLAUDE_PROJECT_DIR"?/##'
}

# L-001 (from F-0001): hooks inherit a PATH without user toolchains, so every
# hook script loads scripts/harness/env.sh right after `set`, before anything else.
test_every_hook_script_sources_env_first() {
  local scripts s code
  scripts="$(hook_scripts)"
  [ -n "$scripts" ] || fail "settings.json no tiene hooks"
  while IFS= read -r s; do
    [ -f "$REPO_DIR/$s" ] || fail "el hook apunta a un fichero que no existe: $s"
    # First two lines of code, ignoring blank lines and comments. No pipe into
    # head: with pipefail it fails once the file is large enough (F-0012).
    code="$(grep -vE '^[[:space:]]*(#|$)' "$REPO_DIR/$s")"
    [[ "$(sed -n 1p <<< "$code")" == set\ * ]] || fail "$s: la primera línea de código no es set"
    assert_eq "$(sed -n 2p <<< "$code")" "$ENV_LINE" "$s: segunda línea de código"
  done <<< "$scripts"
}

test_settings_is_valid_json_with_the_three_hooks() {
  jq -e . "$SETTINGS" >/dev/null || fail "settings.json no es JSON válido"
  # Bash alone does not match Monitor or PowerShell, which also run shell
  # commands (https://code.claude.com/docs/en/tools-reference).
  assert_eq "$(jq -r '.hooks.PreToolUse[] | select(.matcher == "Bash|Monitor|PowerShell") | .hooks[].command' "$SETTINGS")" \
    '"$CLAUDE_PROJECT_DIR"/scripts/harness/guard-git.sh' "PreToolUse de Bash, Monitor y PowerShell"
  assert_eq "$(jq -r '.hooks.PostToolUse[] | select(.matcher == "Edit|Write") | .hooks[].command' "$SETTINGS")" \
    '"$CLAUDE_PROJECT_DIR"/scripts/harness/post-edit.sh' "PostToolUse de Edit|Write"
  assert_eq "$(jq -r '.hooks.Stop[].hooks[].command' "$SETTINGS")" \
    '"$CLAUDE_PROJECT_DIR"/scripts/harness/stop-gate.sh' "Stop"
}

test_settings_denies_dangerous_commands() {
  local rule
  for rule in \
    "Bash(git push --force*)" "Bash(git push -f*)" "Bash(git push origin main*)" \
    "Bash(git push --no-verify*)" "Bash(git reset --hard*)" "Bash(git push --delete*)" \
    "Bash(git tag -d*)" "Bash(rm -rf /*)" "Bash(rm -rf ~*)" \
    "Bash(az group delete*)" "Bash(az ad app delete*)" "Bash(stripe * --live*)" \
    "Read(./.env)" "Read(**/.env)" "Read(**/*.pem)" "Read(**/*.key)"; do
    jq -e --arg r "$rule" '.permissions.deny | index($r)' "$SETTINGS" >/dev/null ||
      fail "falta la denegación $rule"
  done
}

# F-0016 (E0 closing, security review): the hooks run the scripts of the
# working tree, so the code of a foreign pull request must never be brought
# into it without asking, and the credential stores stay out of the transcript.
# Marcos, 2026-09-29: gh pr is allowed only for create, view, checks and diff;
# gh auth token keeps working for the per-command token of the Actaira account.
test_settings_keep_foreign_pr_code_and_credentials_out() {
  local rule
  for rule in "Bash(gh pr checkout*)" "Bash(gh co *)" "Bash(git fetch *pull/*)" "Bash(git pull *pull/*)" "Read(~/.config/gh/**)" \
    "Read(~/.ssh/**)" "Read(~/.azure/**)" "Bash(gh auth status*)"; do
    jq -e --arg r "$rule" '.permissions.deny | index($r)' "$SETTINGS" >/dev/null ||
      fail "falta la denegación $rule"
  done
  assert_eq "$(jq -c '[.permissions.allow[] | select(startswith("Bash(gh pr"))]' "$SETTINGS")" \
    '["Bash(gh pr create*)","Bash(gh pr view *)","Bash(gh pr checks *)","Bash(gh pr diff *)"]' "gh pr permitido sin preguntar"
  assert_eq "$(jq -c '[.permissions.deny[] | select(startswith("Bash(gh auth token") or . == "Bash(gh auth *)" or . == "Bash(gh *)")]' "$SETTINGS")" \
    '[]' "nada deniega gh auth token"
}

# Marcos, 2026-09-28: no commit or PR carries Claude co-authorship or attribution.
test_settings_disable_claude_attribution() {
  assert_eq "$(jq -c '.attribution' "$SETTINGS")" '{"commit":"","pr":"","sessionUrl":false}' "attribution"
}

run_tests "$@"
