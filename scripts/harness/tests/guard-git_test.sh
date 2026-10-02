#!/usr/bin/env bash
# Tests for scripts/harness/guard-git.sh (PreToolUse hook on Bash).
# Commands are given exactly as Claude Code sends them: a JSON payload with
# the raw command text.
source "$(dirname "$0")/lib.sh"

# guard <repo> <command>: runs the hook as Claude Code does; prints its exit code.
guard() {
  local rc=0
  jq -n --arg c "$2" '{tool_name:"Bash",tool_input:{command:$c}}' |
    CLAUDE_PROJECT_DIR="$1" "$HARNESS_DIR/guard-git.sh" >/dev/null 2>&1 || rc=$?
  echo "$rc"
}

# expect <repo> <code> <command...>: every command must give <code>.
expect() {
  local repo="$1" code="$2" c
  shift 2
  for c in "$@"; do
    assert_eq "$(guard "$repo" "$c")" "$code" "$c"
  done
}

# repo_on_branch <name>: a repo checked out on a step branch (not main).
repo_on_branch() {
  init_repo "$T/repo"
  git -C "$T/repo" switch -q -c "$1"
}

test_blocks_force_and_no_verify_and_main() {
  repo_on_branch e0/paso-2-x
  expect "$T/repo" 2 \
    "git push --force" \
    "git push --force-with-lease origin e0/paso-2-x" \
    "git push -f origin x" \
    "git push origin +x" \
    "git push origin main" \
    "git -C . push origin main" \
    "git -C /some/where push origin main" \
    "git push origin HEAD:main" \
    "git push origin HEAD:refs/heads/main" \
    "git push origin :main" \
    "git push --no-verify" \
    "cd /tmp && git push origin main"
}

# F-0007: shell quoting, operators and short option clusters hid main and
# --force from a regex that expected plain words separated by spaces.
test_blocks_quoted_or_chained_main() {
  repo_on_branch e0/paso-2-x
  expect "$T/repo" 2 \
    "git push origin 'main'" \
    'git push origin "main"' \
    "git push origin main;" \
    "git push origin main&& echo ok" \
    "git push -uf origin x" \
    "git push -fu origin x" \
    "git push origin m\"ai\"n" \
    "git push origin ma\\in" \
    "git push --all origin" \
    "git push --mirror origin" \
    "git --git-dir=.git push origin main" \
    "sh -c 'git push origin main'" \
    "echo \$(git push origin main)"
}

# F-0010: bash joins a backslash-newline continuation before running the
# command; the hook read two harmless lines.
test_blocks_line_continuations() {
  repo_on_branch e0/paso-2-x
  expect "$T/repo" 2 \
    "$(printf 'git push \\\n  --no-verify origin e0/paso-2-x')" \
    "$(printf 'git push origin \\\n  main')" \
    "$(printf 'git push \\\n  --force-with-lease origin e0/paso-2-x')" \
    "$(printf 'git \\\npush origin main')" \
    "$(printf 'gh pr \\\n  merge 3 --squash')"
}

# Round 1 of step 0.3, finding 4: abbreviations and synonyms of dangerous
# options, matching and wildcard refspecs, and inline configuration.
test_blocks_abbreviations_refspec_patterns_and_inline_config() {
  repo_on_branch e0/paso-2-x
  expect "$T/repo" 2 \
    "git push --branches origin" \
    "git push --al origin" \
    "git push --mirr origin" \
    "git push --no-veri origin e0/paso-2-x" \
    "git push origin :" \
    "git push origin 'refs/heads/*'" \
    "git push origin 'refs/heads/*:refs/heads/*'" \
    "git -c push.default=matching push origin" \
    "git -c remote.origin.push=HEAD:refs/heads/main push origin" \
    "git -c alias.p=push p origin main" \
    "git -c core.hooksPath=/dev/null commit -m x" \
    "git --config-env=core.hooksPath=HOOKS commit -m x" \
    "git config alias.p push" \
    "git config --global alias.p 'push origin'" \
    "git config push.default matching" \
    "git config core.hooksPath /dev/null" \
    "git config remote.origin.push HEAD:refs/heads/main"
}

# Aliases from the user's git config are expanded: `git p` may be a push.
test_blocks_configured_push_alias() {
  repo_on_branch e0/paso-2-x
  git -C "$T/repo" config alias.p "push"
  git -C "$T/repo" config alias.sh '!git push origin main'
  expect "$T/repo" 2 \
    "git p origin main" \
    "git p --force origin e0/paso-2-x" \
    "git sh"
  expect "$T/repo" 0 "git p origin e0/paso-2-x"
}

# Round 1 of step 0.3, finding 5: the hook reads text before expansion, so a
# push that expands anything is refused rather than guessed.
test_blocks_shell_expansions_in_a_push() {
  repo_on_branch e0/paso-2-x
  expect "$T/repo" 2 \
    "b=main; git push origin \$b" \
    "git push origin \${BR:-main}" \
    "git push origin \$(echo main)" \
    "git push origin \`echo main\`" \
    "git push origin {main,e0/x}" \
    "git push origin HEAD:ma{i,}n" \
    "git push origin \$'\\x6dain'" \
    "f() { git push \$1 \$2; }; f origin main" \
    "echo main | xargs git push origin" \
    "\$(command -v git) push origin main" \
    "\${GIT:-git} push origin main"
}

test_blocks_any_push_from_main() {
  init_repo "$T/repo"
  expect "$T/repo" 2 \
    "git push -u origin feature" \
    "git push" \
    "git push origin HEAD"
}

# A repo named with -C is checked too, not only the project.
test_blocks_push_from_another_repo_on_main() {
  repo_on_branch e0/paso-2-x
  init_repo "$T/other"
  expect "$T/repo" 2 "git -C $T/other push" "cd $T/repo && git -C $T/other push -u origin x"
}

# F-0011: closing an epic pushes the tag e<N>-cerrada from main
# (skill cierre-epica); nothing else may be pushed from main.
test_allows_only_the_closing_tag_from_main() {
  init_repo "$T/repo"
  expect "$T/repo" 0 \
    "git push origin e0-cerrada" \
    "git push origin e12-cerrada" \
    "git switch main && git pull --ff-only && git tag e0-cerrada && git push origin e0-cerrada"
  expect "$T/repo" 2 \
    "git push origin e0-cerrada main" \
    "git push origin e0-cerrada:refs/heads/main" \
    "git push --tags origin" \
    "git push --follow-tags origin e0-cerrada" \
    "git push origin e0-cerradas" \
    "git push origin release-cerrada" \
    "git push origin e0-cerrada && git push origin feature"
}

test_allows_step_branch_push_and_non_push_commands() {
  repo_on_branch e0/paso-2-x
  expect "$T/repo" 0 \
    "git push -u origin e0/paso-2-x" \
    "git push origin e0/paso-2-mainline" \
    "git push -u origin e0/paso-2-x && git switch main" \
    "git push --follow-tags origin e0/paso-2-x" \
    "git status" \
    "git log --oneline main..HEAD" \
    "git switch main" \
    "make check"
}

# Round 1 of step 0.3, finding 13: text that only mentions a push is not a push.
test_allows_commands_that_only_mention_push() {
  repo_on_branch e0/paso-2-x
  expect "$T/repo" 0 \
    "git commit -m 'Reject push to main in the pre-push hook'" \
    "git commit -m 'Speed up push +10 percent'" \
    "git commit -m 'Block the dashed git-push binary'" \
    "git commit -m 'Move the push check into a function and drop an alias'" \
    "git log --grep push main..HEAD" \
    "git config user.email harness@example.invalid" \
    "git config --get alias.p" \
    "git -c color.ui=never log -1" \
    "grep -rn push scripts/"
}

test_allows_non_push_commands_on_main() {
  init_repo "$T/repo"
  expect "$T/repo" 0 \
    "git pull --ff-only" \
    "git switch -c e0/paso-3-x" \
    "git tag e0-cerrada"
}

# The branch that matters is the one of the directory Claude works in (the
# input field cwd, which follows cd and worktrees), not only the project root.
test_uses_the_cwd_of_the_session() {
  repo_on_branch e0/paso-2-x
  init_repo "$T/other"
  local rc=0
  jq -n --arg c "git push" --arg d "$T/other" '{tool_name:"Bash",cwd:$d,tool_input:{command:$c}}' |
    CLAUDE_PROJECT_DIR="$T/repo" "$HARNESS_DIR/guard-git.sh" >/dev/null 2>&1 || rc=$?
  assert_eq "$rc" "2" "push con el cwd de la sesión en un repo en main"
}

# Monitor runs shell commands too (settings.json matches Bash|Monitor|PowerShell).
test_blocks_a_push_run_by_monitor() {
  repo_on_branch e0/paso-2-x
  local rc=0
  jq -n '{tool_name:"Monitor",tool_input:{command:"git push origin main",description:"x"}}' |
    CLAUDE_PROJECT_DIR="$T/repo" "$HARNESS_DIR/guard-git.sh" >/dev/null 2>&1 || rc=$?
  assert_eq "$rc" "2" "push lanzado con Monitor"
}

# Without jq the hook cannot read the command: it must block, never let it run.
test_blocks_everything_without_jq() {
  repo_on_branch e0/paso-2-x
  local bp rc=0
  bp="$(bare_path "$T/sysbin")"
  rm -f "$T/sysbin/jq"
  printf '{"tool_input":{"command":"git status"}}' |
    PATH="$bp" CLAUDE_PROJECT_DIR="$T/repo" "$HARNESS_DIR/guard-git.sh" >/dev/null 2>"$T/err" || rc=$?
  assert_eq "$rc" "2" "sin jq"
  assert_contains "$(cat "$T/err")" "jq"
}

# Round 3 of step 0.3, low finding: without python3 the tokenized reading
# cannot run, so a push is blocked (the same push passes with python3), while
# a command that does not push still runs.
test_blocks_a_push_without_python3() {
  repo_on_branch e0/paso-2-x
  local bp c rc
  bp="$(bare_path "$T/sysbin")"
  [ ! -e "$T/sysbin/python3" ] || fail "el PATH de prueba no debe tener python3"
  c="git push -u origin e0/paso-2-x"
  assert_eq "$(guard "$T/repo" "$c")" "0" "con python3, el push de una rama de paso pasa"
  rc=0
  jq -n --arg c "$c" '{tool_name:"Bash",tool_input:{command:$c}}' |
    HOME="$T/home" PATH="$bp" CLAUDE_PROJECT_DIR="$T/repo" "$HARNESS_DIR/guard-git.sh" >/dev/null 2>"$T/err" || rc=$?
  assert_eq "$rc" "2" "sin python3, el push"
  assert_contains "$(cat "$T/err")" "falta python3"
  rc=0
  jq -n '{tool_name:"Bash",tool_input:{command:"git status"}}' |
    HOME="$T/home" PATH="$bp" CLAUDE_PROJECT_DIR="$T/repo" "$HARNESS_DIR/guard-git.sh" >/dev/null 2>"$T/err" || rc=$?
  assert_eq "$rc" "0" "sin python3, un comando que no sube nada"
}

# Round 2 of step 0.3, finding 1: a quoted value with a space or an operator in
# a git global option must not shift what the hook takes as the subcommand.
test_blocks_quoted_values_in_global_options() {
  repo_on_branch e0/paso-2-x
  expect "$T/repo" 2 \
    "git -c 'user.name=a b' push --no-verify origin e0/paso-2-x" \
    "git -c 'x.y=a;b' push --no-verify origin e0/paso-2-x" \
    "git -c \"core.sshCommand=ssh -i key\" push origin main" \
    "git -C 'dir with space' push --force origin e0/paso-2-x" \
    "git --git-dir='a b/.git' push origin main"
}

# Round 2 of step 0.3, finding 2: git reached through a variable, a function or
# a shell alias is refused when the command pushes.
test_blocks_git_behind_variables_functions_or_aliases() {
  repo_on_branch e0/paso-2-x
  expect "$T/repo" 2 \
    "g=git; \$g push --no-verify origin e0/paso-2-x" \
    "f() { git \"\$@\"; }; f push --no-verify origin e0/paso-2-x" \
    "function f { git \"\$@\"; }; f push origin e0/paso-2-x" \
    "alias g=git; g push --no-verify origin e0/paso-2-x"
}

# Round 2 of step 0.3, finding 3: other ways to push or to change git's
# configuration for one command.
test_blocks_other_push_paths_and_config_from_the_environment() {
  repo_on_branch e0/paso-2-x
  expect "$T/repo" 2 \
    "git send-pack origin refs/heads/e0/paso-2-x" \
    "/usr/lib/git-core/git-push origin main" \
    "git-push origin e0/paso-2-x" \
    "GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null git push origin e0/paso-2-x" \
    "GIT_CONFIG_PARAMETERS=\"'alias.p=push'\" git p origin e0/paso-2-x" \
    "HOME=/tmp/h git push origin e0/paso-2-x" \
    "export GIT_CONFIG_GLOBAL=/tmp/g; git push origin e0/paso-2-x" \
    "printf '[alias]\\n p = push\\n' >> .git/config && git p origin e0/paso-2-x" \
    "git config user.nick foo --get && git config alias.p push --get"
  expect "$T/repo" 0 \
    "git config --get alias.p" \
    "git config get user.email" \
    "git config --global --get user.name"
}

# Round 2 of step 0.3, finding 4: the directory a push acts on follows cd,
# pushd and git -C, including relative paths and ~.
test_follows_cd_and_git_c_to_the_repo_that_pushes() {
  repo_on_branch e0/paso-2-x
  init_repo "$T/other"
  mkdir -p "$T/home"
  init_repo "$T/home/x"
  expect "$T/repo" 2 \
    "cd $T/other && git push" \
    "cd $T && git -C other push" \
    "pushd $T/other && git push origin feature" \
    "git -C \$D push origin e0/paso-2-x"
  assert_eq "$(HOME="$T/home" guard "$T/repo" "git -C ~/x push origin feature")" "2" "git -C ~/x en main"
  expect "$T/repo" 0 "cd $T/repo && git push -u origin e0/paso-2-x"
}

# Round 2 of step 0.3, finding 7: a merge must go through merge-pr.sh, which
# checks the squash message that enters main (F-0009).
test_blocks_direct_pull_request_merges() {
  repo_on_branch e0/paso-2-x
  expect "$T/repo" 2 \
    "gh pr merge 3 --squash --delete-branch" \
    "GH_TOKEN=x gh pr merge 3 --squash" \
    "gh api -X PUT repos/o/r/pulls/3/merge"
  expect "$T/repo" 0 \
    "gh pr view 3 --json mergeCommit" \
    "gh pr create --fill" \
    "gh pr checks 3 --watch" \
    "scripts/harness/merge-pr.sh 3 subject body.md"
}

# A heredoc body is data for the tokenized reading (an apostrophe in it must
# not make the command unreadable), but the flattened reading still sees a
# push inside it when the heredoc feeds a shell.
test_heredocs() {
  repo_on_branch e0/paso-2-x
  expect "$T/repo" 0 "$(printf "cat > notes.txt <<'EOF'\nwe don't push to main by hand\nEOF")"
  expect "$T/repo" 2 "$(printf "bash <<'EOF'\ngit push origin main\nEOF")"
}

# Round 2 of step 0.3, finding 9: a redirection like 2>&1 is not an argument.
test_closing_tag_with_redirections() {
  init_repo "$T/repo"
  expect "$T/repo" 0 \
    "git push origin e0-cerrada 2>&1" \
    "git switch main && git pull --ff-only && git tag e0-cerrada && git push origin e0-cerrada 2>&1 | tail -1"
}

# F-0011, repeated at the E0 closing (CLAUDE.md told Claude to merge with an
# order the guard blocks), lesson L-007: every git or gh order that CLAUDE.md
# or a skill gives in backticks passes the guard, on a step branch, or on main
# for the epic closing tag. A doc that only describes what a script runs does
# not put that command in backticks.
test_orders_in_claude_md_and_skills_pass_the_guard() {
  local orders order n=0 repo
  orders="$(python3 - "$REPO_DIR" <<'EOF'
import glob, os, re, sys
root = sys.argv[1]
files = [os.path.join(root, "CLAUDE.md")] + sorted(glob.glob(os.path.join(root, ".claude/skills/*/SKILL.md")))
prefixes = ("git push", "git switch", "git pull", "git tag", "gh pr ", "scripts/harness/merge-pr.sh")
subst = {"<N>": "1", "<M>": "1", "<nombre>": "x", "<rama>": "e1/paso-1-x", "<pr>": "7",
         "<asunto>": "s", "<fichero con el cuerpo>": "body.md"}
for f in files:
    for m in re.finditer(r"`([^`\n]+)`", open(f, encoding="utf-8").read()):
        c = m.group(1).strip()
        # F-0027: a push with global options first (git -C . push) is an order too.
        if c.startswith(prefixes) or re.match(r"git\s.*\bpush\b", c):
            for k, v in subst.items():
                c = c.replace(k, v)
            print(c)
EOF
)"
  init_repo "$T/main"
  repo_on_branch e1/paso-1-x
  while IFS= read -r order; do
    [ -n "$order" ] || continue
    n=$((n + 1))
    repo="$T/repo"
    case "$order" in *cerrada*) repo="$T/main" ;; esac
    assert_eq "$(guard "$repo" "$order")" "0" "orden de la documentación: $order"
  done <<< "$orders"
  [ "$n" -ge 5 ] || fail "solo se han encontrado $n órdenes en CLAUDE.md y las skills"
}

# In PreToolUse only exit 2 blocks: a crash (exit 1) lets the command run.
test_blocks_push_to_main_without_home() {
  repo_on_branch e0/paso-2-x
  local rc
  rc="$(env -u HOME bash -c "$(declare -f guard); HARNESS_DIR='$HARNESS_DIR' guard '$T/repo' 'git push origin main'")"
  assert_eq "$rc" "2" "sin HOME el guard sigue bloqueando"
}

run_tests "$@"
