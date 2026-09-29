#!/usr/bin/env bash
# Tests for scripts/harness/merge-pr.sh with a fake gh on the PATH: the squash
# message enters main without CI, so it is checked before merging (F-0009).
source "$(dirname "$0")/lib.sh"

CLAUDE_FOOTER="Generated with [Claude"" Code](https://claude.com/claude-code)"
SENTINEL="ACTAIRA_TEST_SENTINEL_123456"

# fake_gh [checks exit code]: a gh that logs its arguments, answers pr view
# (while $T/no-checks holds N > 0, the next N polls of the checks answer as
# for a PR that GitHub has not given checks yet),
# with $T/pr.json, the merge commit with fedcba9 and its message with
# $T/merged-msg (what GitHub wrote into main).
fake_gh() {
  mkdir -p "$T/bin"
  cat > "$T/bin/gh" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$T/gh.log"
case "\$*" in
  *mergeCommit*) echo fedcba9 ;;
  "api user"*) echo 123+demo@users.noreply.github.com ;;
  *commit.author.email*) cat "$T/merged-email" ;;
  "api "*) cat "$T/merged-msg" ;;
  "pr view"*) cat "$T/pr.json" ;;
  "pr checks"*"--watch"*) exit ${1:-0} ;;
  "pr checks"*)
    n="\$(cat "$T/no-checks" 2>/dev/null || echo 0)"
    if [ "\$n" -gt 0 ]; then
      echo "\$((n - 1))" > "$T/no-checks"
      echo "no checks reported on the 'demo' branch" >&2
      exit 1
    fi
    printf 'check\tpending\t0\n'
    exit 8 ;;
esac
exit 0
EOF
  chmod +x "$T/bin/gh"
  # A gitleaks that logs its arguments and the files it was given, and finds
  # a leak when one of them holds the test sentinel.
  cat > "$T/bin/gitleaks" <<EOF
#!/usr/bin/env bash
echo "\$* | \$(ls | tr '\n' ' ')" >> "$T/gitleaks.log"
if grep -rq ACTAIRA_TEST_SENTINEL .; then
  echo "leaks found: 1"
  exit 1
fi
exit 0
EOF
  chmod +x "$T/bin/gitleaks"
  jq -n '{title: "E0 step 9: demo", body: "Adds the demo.", headRefOid: "abc1234"}' > "$T/pr.json"
  printf 'Adds the demo.\n' > "$T/body.md"
  printf 'E0 step 9: demo (#7)\n\nAdds the demo.\n' > "$T/merged-msg"
  printf '123+demo@users.noreply.github.com\n' > "$T/merged-email"
  # A private list of made-up terms where check-personal.sh looks for it.
  mkdir -p "$T/home/actaira-ws/privado"
  printf 'cuenta de prueba | cuentaficticia\n' > "$T/home/actaira-ws/privado/datos-personales.txt"
}

merge() { # [args...]; prints the exit code; output in $T/out
  local rc=0
  GITLEAKS="$T/bin/gitleaks" HOME="$T/home" PATH="$T/bin:$PATH" MERGE_PR_CHECK_WAIT=0 \
    "$HARNESS_DIR/merge-pr.sh" "$@" >"$T/out" 2>&1 || rc=$?
  echo "$rc"
}

gh_log() { if [ -f "$T/gh.log" ]; then cat "$T/gh.log"; fi; }

test_merges_a_clean_pr_after_green_checks() {
  fake_gh 0
  assert_eq "$(merge 7 "E0 step 9: demo (#7)" "$T/body.md")" "0" "fusión limpia ($(cat "$T/out"))"
  assert_contains "$(gh_log)" "pr checks 7 --watch --fail-fast"
  assert_contains "$(gh_log)" "pr merge 7 --squash --delete-branch --match-head-commit abc1234 --subject E0 step 9: demo (#7) --body-file $T/body.md --author-email 123+demo@users.noreply.github.com"
  assert_eq "$(cat "$T/gitleaks.log")" "dir --no-banner --redact --log-level warn . | pr-msg squash-msg " "gitleaks sobre los dos textos"
}

test_refuses_a_squash_message_with_attribution() {
  fake_gh 0
  printf 'Adds the demo.\n\n%s\n' "$CLAUDE_FOOTER" > "$T/body.md"
  assert_eq "$(merge 7 "E0 step 9: demo (#7)" "$T/body.md")" "1" "cuerpo del squash con atribución"
  assert_not_contains "$(gh_log)" "pr merge" "no se fusiona"
}

test_refuses_a_pr_description_with_attribution() {
  fake_gh 0
  jq -n --arg b "Adds the demo.

$CLAUDE_FOOTER" '{title: "E0 step 9: demo", body: $b, headRefOid: "abc1234"}' > "$T/pr.json"
  assert_eq "$(merge 7 "E0 step 9: demo (#7)" "$T/body.md")" "1" "descripción del PR con atribución"
  assert_not_contains "$(gh_log)" "pr merge" "no se fusiona"
}

test_does_not_merge_when_checks_fail() {
  fake_gh 1
  assert_eq "$(merge 7 "E0 step 9: demo (#7)" "$T/body.md")" "1" "checks en rojo"
  assert_not_contains "$(gh_log)" "pr merge" "no se fusiona"
}

test_sin_ci_skips_the_checks_only() {
  fake_gh 1
  assert_eq "$(merge --sin-ci 7 "E0 step 9: demo (#7)" "$T/body.md")" "0" "sin CI ($(cat "$T/out"))"
  assert_not_contains "$(gh_log)" "pr checks" "no mira los checks"
  assert_contains "$(gh_log)" "pr merge 7 --squash --delete-branch --match-head-commit abc1234"
}

# Round 2 of step 0.3, finding 7: what entered main is checked after merging,
# as GitHub wrote it, in case it differs from the message that was sent.
test_checks_the_commit_that_entered_main() {
  fake_gh 0
  printf 'E0 step 9: demo (#7)\n\n%s\n' "$CLAUDE_FOOTER" > "$T/merged-msg"
  assert_eq "$(merge 7 "E0 step 9: demo (#7)" "$T/body.md")" "1" "commit en main con atribución"
  assert_contains "$(cat "$T/out")" "fedcba9"
  assert_contains "$(gh_log)" "api repos/{owner}/{repo}/commits/fedcba9"
}

# F-0015, at the clean import: GitHub signs a merge with the account's primary
# e-mail unless told otherwise, and main cannot be rewritten; the squash is
# authored by the account's noreply address and checked after merging.
test_checks_the_author_of_the_commit_that_entered_main() {
  fake_gh 0
  printf 'someone@example.invalid\n' > "$T/merged-email"
  assert_eq "$(merge 7 "E0 step 9: demo (#7)" "$T/body.md")" "1" "commit en main con otro correo de autor"
  assert_contains "$(cat "$T/out")" "entró en main con el correo de autor someone@example.invalid"
  assert_contains "$(gh_log)" "api repos/{owner}/{repo}/commits/fedcba9 --jq .commit.author.email"
}

# F-0015, review of the clean import (finding 2): nothing personal in the
# squash message or the PR text, which enter main or GitHub without CI.
test_refuses_a_squash_message_with_personal_data() {
  fake_gh 0
  printf 'Adds the demo.\n\nThanks, cuentaficticia.\n' > "$T/body.md"
  assert_eq "$(merge 7 "E0 step 9: demo (#7)" "$T/body.md")" "1" "cuerpo del squash con un dato personal"
  assert_contains "$(cat "$T/out")" "llevan datos personales"
  assert_not_contains "$(gh_log)" "pr merge" "no se fusiona"
}

# E0 closing review (security, finding 4): the squash message enters main
# without CI, so a secret in it (or in the PR text) stops the merge.
test_refuses_a_squash_message_with_a_secret() {
  fake_gh 0
  printf 'Adds the demo.\n\nvalue %s\n' "$SENTINEL" > "$T/body.md"
  assert_eq "$(merge 7 "E0 step 9: demo (#7)" "$T/body.md")" "1" "cuerpo del squash con un secreto"
  assert_contains "$(cat "$T/out")" "contienen un secreto"
  assert_not_contains "$(gh_log)" "pr merge" "no se fusiona"
}

test_refuses_a_pr_description_with_a_secret() {
  fake_gh 0
  jq -n --arg b "Adds the demo. value $SENTINEL" '{title: "E0 step 9: demo", body: $b, headRefOid: "abc1234"}' > "$T/pr.json"
  assert_eq "$(merge 7 "E0 step 9: demo (#7)" "$T/body.md")" "1" "descripción del PR con un secreto"
  assert_contains "$(cat "$T/out")" "contienen un secreto"
  assert_not_contains "$(gh_log)" "pr merge" "no se fusiona"
}

test_refuses_without_the_pinned_gitleaks() {
  fake_gh 0
  local rc=0
  GITLEAKS="$T/missing/gitleaks" PATH="$T/bin:$PATH" "$HARNESS_DIR/merge-pr.sh" 7 "E0 step 9: demo (#7)" "$T/body.md" >"$T/out" 2>&1 || rc=$?
  assert_eq "$rc" "1" "sin gitleaks"
  assert_contains "$(cat "$T/out")" "falta el gitleaks fijado"
  assert_not_contains "$(gh_log)" "pr merge" "no se fusiona"
}

# A PR that was just opened has no checks for a few seconds, and
# gh pr checks --watch gives up at once (F-0019).
test_waits_for_the_checks_of_a_new_pr() {
  fake_gh 0
  echo 2 > "$T/no-checks"
  assert_eq "$(merge 7 "E0 step 9: demo (#7)" "$T/body.md")" "0" "espera a que haya checks ($(cat "$T/out"))"
  assert_eq "$(grep -c '^pr checks 7$' "$T/gh.log")" "3" "tres consultas: dos sin checks y una con"
  assert_contains "$(gh_log)" "pr checks 7 --watch --fail-fast"
  assert_contains "$(gh_log)" "pr merge 7"
}

test_gives_up_when_no_check_appears() {
  fake_gh 0
  echo 99 > "$T/no-checks"
  local rc=0
  GITLEAKS="$T/bin/gitleaks" HOME="$T/home" PATH="$T/bin:$PATH" MERGE_PR_CHECK_WAIT=0 MERGE_PR_CHECK_TRIES=3 \
    "$HARNESS_DIR/merge-pr.sh" 7 "E0 step 9: demo (#7)" "$T/body.md" >"$T/out" 2>&1 || rc=$?
  assert_eq "$rc" "1" "sin checks no se fusiona"
  assert_contains "$(cat "$T/out")" "merge-pr: el PR 7 sigue sin checks tras 3 intentos; no se fusiona"
  assert_not_contains "$(gh_log)" "--watch" "no llega a esperar a checks que no existen"
  assert_not_contains "$(gh_log)" "pr merge" "no se fusiona"
}

run_tests "$@"
