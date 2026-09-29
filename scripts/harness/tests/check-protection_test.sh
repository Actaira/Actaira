#!/usr/bin/env bash
# Tests for scripts/harness/check-protection.sh with a fake gh on the PATH: the
# live protection of main must be the one in docs/estado/branch-protection.json,
# because it is the security boundary of main (ADR 0000, L-005).
source "$(dirname "$0")/lib.sh"

EXPECTED="$REPO_DIR/docs/estado/branch-protection.json"

# live_ok: what GET branches/main/protection answers with that protection in
# place, including fields the check does not compare.
live_ok() {
  jq -n '{
    url: "https://api.github.com/repos/o/r/branches/main/protection",
    required_status_checks: {strict: true, contexts: ["check"], checks: [{context: "check", app_id: 15368}]},
    required_pull_request_reviews: {dismiss_stale_reviews: false, require_code_owner_reviews: false,
      require_last_push_approval: false, required_approving_review_count: 0},
    required_signatures: {enabled: false},
    enforce_admins: {enabled: true},
    required_linear_history: {enabled: false},
    allow_force_pushes: {enabled: false},
    allow_deletions: {enabled: false},
    block_creations: {enabled: false},
    required_conversation_resolution: {enabled: false},
    lock_branch: {enabled: false},
    allow_fork_syncing: {enabled: false}
  }'
}

# fake_gh <json>: a gh that logs its arguments and answers `api` with <json>;
# with $T/missing it fails the way GitHub answers a branch without protection.
fake_gh() {
  mkdir -p "$T/bin"
  printf '%s\n' "$1" > "$T/live.json"
  cat > "$T/bin/gh" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$T/gh.log"
if [ -f "$T/missing" ]; then
  echo "gh: Branch not protected (HTTP 404)" >&2
  exit 1
fi
cat "$T/live.json"
EOF
  chmod +x "$T/bin/gh"
}

protection() { # prints the exit code; output in $T/out
  local rc=0
  PATH="$T/bin:$PATH" "$HARNESS_DIR/check-protection.sh" --repo o/r "$EXPECTED" >"$T/out" 2>&1 || rc=$?
  echo "$rc"
}

# with_live <jq filter>: the fake gh answers live_ok changed by the filter.
with_live() { fake_gh "$(live_ok | jq "$1")"; }

test_matching_protection_passes() {
  fake_gh "$(live_ok)"
  assert_eq "$(protection)" "0" "protección igual que el JSON ($(cat "$T/out"))"
  assert_contains "$(cat "$T/out")" "protección de main en o/r: OK"
  assert_eq "$(cat "$T/gh.log")" "api repos/o/r/branches/main/protection" "llamada a gh"
}

# Round 1 of step 0.4, finding 6: the repo is the one origin pushes to, never
# the one gh would guess (GH_REPO), and a remote that is not GitHub is refused.
test_repo_comes_from_the_origin_remote() {
  fake_gh "$(live_ok)"
  init_repo "$T/clone"
  git -C "$T/clone" remote add origin "$T/bare.git"
  local url rc
  for url in https://github.com/acme/widget.git git@github.com:acme/widget.git; do
    git -C "$T/clone" remote set-url origin "$url"
    rm -f "$T/gh.log"
    rc=0
    (cd "$T/clone" && GH_REPO=other/repo PATH="$T/bin:$PATH" "$HARNESS_DIR/check-protection.sh" "$EXPECTED") >"$T/out" 2>&1 || rc=$?
    assert_eq "$rc" "0" "origin $url ($(cat "$T/out"))"
    assert_eq "$(cat "$T/gh.log")" "api repos/acme/widget/branches/main/protection" "repo de $url"
  done
  git -C "$T/clone" remote set-url origin "$T/bare.git"
  rc=0
  (cd "$T/clone" && PATH="$T/bin:$PATH" "$HARNESS_DIR/check-protection.sh" "$EXPECTED") >"$T/out" 2>&1 || rc=$?
  assert_eq "$rc" "1" "origin que no es de GitHub"
  assert_contains "$(cat "$T/out")" "no es un repo de GitHub"
}

test_admins_not_bound_fails() {
  with_live '.enforce_admins.enabled = false'
  assert_eq "$(protection)" "1" "enforce_admins desactivado"
  assert_contains "$(cat "$T/out")" "enforce_admins: esperado true, en GitHub false"
}

test_missing_required_check_fails() {
  with_live '.required_status_checks.checks = [] | .required_status_checks.contexts = []'
  assert_eq "$(protection)" "1" "sin el check obligatorio"
  assert_contains "$(cat "$T/out")" 'required_checks: esperado [{"app_id":15368,"context":"check"}], en GitHub []'
}

# Round 1 of step 0.4, finding 2: a check any app (or a commit status) can
# satisfy is not the CI.
test_check_from_any_app_fails() {
  with_live '.required_status_checks.checks[0].app_id = -1'
  assert_eq "$(protection)" "1" "check de cualquier app"
  assert_contains "$(cat "$T/out")" 'en GitHub [{"app_id":-1,"context":"check"}]'
  with_live '.required_status_checks.checks[0].app_id = null'
  assert_eq "$(protection)" "1" "check sin app"
  assert_contains "$(cat "$T/out")" 'en GitHub [{"app_id":null,"context":"check"}]'
}

test_branch_not_up_to_date_fails() {
  with_live '.required_status_checks.strict = false'
  assert_eq "$(protection)" "1" "strict desactivado"
  assert_contains "$(cat "$T/out")" "strict: esperado true, en GitHub false"
}

test_pull_request_not_required_fails() {
  with_live 'del(.required_pull_request_reviews)'
  assert_eq "$(protection)" "1" "sin PR obligatorio"
  assert_contains "$(cat "$T/out")" "pull_request_reviews: esperado"
  assert_contains "$(cat "$T/out")" "en GitHub null"
}

# Round 1 of step 0.4, finding 2: nobody may skip the pull request.
test_pull_request_bypass_fails() {
  with_live '.required_pull_request_reviews.bypass_pull_request_allowances = {users: [{login: "someone"}], teams: [], apps: []}'
  assert_eq "$(protection)" "1" "excepción al PR obligatorio"
  assert_contains "$(cat "$T/out")" "pull_request_bypass: esperado 0, en GitHub 1"
}

test_force_pushes_or_deletions_allowed_fail() {
  with_live '.allow_force_pushes.enabled = true'
  assert_eq "$(protection)" "1" "push forzado permitido"
  assert_contains "$(cat "$T/out")" "allow_force_pushes: esperado false, en GitHub true"
  with_live '.allow_deletions.enabled = true'
  assert_eq "$(protection)" "1" "borrado permitido"
  assert_contains "$(cat "$T/out")" "allow_deletions: esperado false, en GitHub true"
}

test_unprotected_branch_fails() {
  fake_gh "$(live_ok)"
  touch "$T/missing"
  assert_eq "$(protection)" "1" "rama sin protección"
  assert_contains "$(cat "$T/out")" "main de o/r no está protegida o no se puede leer su protección"
  assert_contains "$(cat "$T/out")" "Branch not protected (HTTP 404)"
}

run_tests "$@"
