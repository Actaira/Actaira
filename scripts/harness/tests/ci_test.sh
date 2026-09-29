#!/usr/bin/env bash
# Tests for .github/workflows/ci.yml and docs/estado/branch-protection.json. The
# protection of main is the security boundary (ADR 0000), and it only asks for
# the check `check` to be green: what `check` runs is defined by these files in
# the pull request itself, so an accidental change to them must turn make check
# red (F-0014, L-006). A deliberate change updates these tests in the same PR.
source "$(dirname "$0")/lib.sh"

# Fixed paths: a guard never takes the file it checks from the environment
# (round 2 of step 0.4, F-0008).
CI="$REPO_DIR/.github/workflows/ci.yml"
PROTECTION="$REPO_DIR/docs/estado/branch-protection.json"

# workflows: every workflow file next to ci.yml, one per line.
workflows() {
  local f
  for f in "$(dirname "$CI")"/*.yml "$(dirname "$CI")"/*.yaml; do
    if [ -e "$f" ]; then printf '%s\n' "$f"; fi
  done
}

# The required status check is the job id `check` (a job without `name:`
# reports its id), the only job of the workflow, and it runs exactly `make check`.
test_workflow_has_a_single_check_job_running_make_check() {
  [ -f "$CI" ] || fail "no existe $CI"
  local jobs
  jobs="$(awk '/^jobs:/ {in_jobs = 1; next} /^[^ #]/ {in_jobs = 0} in_jobs && /^  [^ #]/' "$CI")"
  assert_eq "$jobs" "  check:" "jobs del workflow"
  if grep -qE '^    name:' "$CI"; then fail "el job check no debe tener name: (cambiaría el nombre del check obligatorio)"; fi
  grep -qxE '    runs-on: ubuntu-latest' "$CI" || fail "el job no corre en ubuntu-latest"
  grep -qxE '      - run: make check' "$CI" || fail "el job no ejecuta make check"
}

# F-0014: GitHub takes a skipped job as a success even when its check is
# required, and a step can be skipped, allowed to fail or run by another shell.
# Every line that is not a comment must be the reviewed one.
test_workflow_is_exactly_the_reviewed_one() {
  [ -f "$CI" ] || fail "no existe $CI"
  local expected
  expected="$(cat <<'EOF'
name: ci
on:
  pull_request:
  push:
    branches: [main]
permissions:
  contents: read
jobs:
  check:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          fetch-depth: 0
          persist-credentials: false
      - uses: actions/setup-go@b7ad1dad31e06c5925ef5d2fc7ad053ef454303e # v7.0.0
        with:
          go-version-file: go.mod
      - run: make check
EOF
)"
  assert_eq "$(grep -vE '^[[:space:]]*(#|$)' "$CI")" "$expected" \
    "ci.yml no es el revisado: un if, continue-on-error, shell, paso o job nuevo cambia lo que significa check en verde (F-0014)"
}

# F-0014: a job called check in another workflow publishes a check run with the
# same name from the same app, and could stand in for the required one.
test_no_other_workflow_publishes_a_check_job() {
  local f others="" seen=0
  while IFS= read -r f; do
    if [ "$f" = "$CI" ]; then
      seen=1
      continue
    fi
    if grep -qE '^[[:space:]]+check:[[:space:]]*(#.*)?$' "$f" ||
      grep -qiE "^[[:space:]]+name:[[:space:]]*[\"']?check[\"']?[[:space:]]*(#.*)?$" "$f"; then
      others+="$(basename "$f") "
    fi
  done < <(workflows)
  # Round 2 of step 0.4: without ci.yml in the list, the loop looked at nothing.
  assert_eq "$seen" "1" "ci.yml entre los workflows revisados ($(dirname "$CI"))"
  assert_eq "$others" "" "workflows, además de ci.yml, con un job check"
}

# Every workflow file: any `uses:`, in block or flow style, goes to a full
# commit SHA, with the release in a comment on the same line.
test_actions_are_pinned_by_commit_sha() {
  local f lines values out bad=""
  while IFS= read -r f; do
    lines="$(grep -E 'uses:' "$f")" || continue
    values="$(grep -oE 'uses:[[:space:]]*[^[:space:],}]+' <<< "$lines")" || values=""
    out="$(grep -vE "^uses:[[:space:]]*[\"']?[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[0-9a-f]{40}[\"']?$" <<< "$values")" || out=""
    bad+="$out"
    out="$(grep -vE '# v[0-9]' <<< "$lines")" || out=""
    bad+="$out"
  done < <(workflows)
  [ -n "$(workflows)" ] || fail "no hay workflows"
  assert_eq "$bad" "" "acciones sin fijar por SHA de 40 caracteres con su versión en comentario"
}

test_workflow_runs_on_every_pull_request_and_push_to_main() {
  [ -f "$CI" ] || fail "no existe $CI"
  grep -qxE '  pull_request:' "$CI" || fail "no corre en pull_request"
  grep -qxE '    branches: \[main\]' "$CI" || fail "no corre en los push a main"
  if grep -qE '^[[:space:]]*(paths|paths-ignore|branches-ignore):' "$CI"; then
    fail "un filtro de rutas o ramas deja el check obligatorio pendiente"
  fi
}

test_permissions_are_read_only() {
  [ -f "$CI" ] || fail "no existe $CI"
  grep -qxE 'permissions:' "$CI" || fail "falta permissions: a nivel de workflow"
  grep -qxE '  contents: read' "$CI" || fail "el workflow no limita contents a read"
  if grep -qE '(:|-)[[:space:]]*write' "$CI"; then fail "hay permisos de escritura"; fi
}

# Every workflow but release.yml (which signs, E1 step 1.2b) reads only: a
# job that is not the required check still runs the code of the pull request.
test_every_workflow_but_release_is_read_only() {
  local f bad=""
  while IFS= read -r f; do
    [ "$(basename "$f")" = "release.yml" ] && continue
    if ! grep -qxE 'permissions:' "$f" || ! grep -qxE '  contents: read' "$f"; then
      bad+="$(basename "$f") sin permissions: contents: read; "
    fi
    if grep -qE '(:|-)[[:space:]]*write' "$f"; then
      bad+="$(basename "$f") con permisos de escritura; "
    fi
  done < <(workflows)
  assert_eq "$bad" "" "workflows de solo lectura"
}

# The secret scan and the attribution check read every commit of the branch.
test_checkout_fetches_full_history_without_credentials() {
  [ -f "$CI" ] || fail "no existe $CI"
  grep -qxE '          fetch-depth: 0' "$CI" || fail "sin fetch-depth: 0 el escaneo de secretos y el de atribución solo ven un commit"
  grep -qxE '          persist-credentials: false' "$CI" || fail "el token no debe quedarse en .git/config"
}

# The whole protection, compared exactly: the check has to come from GitHub
# Actions (app 15368, GET /apps/github-actions); without app_id any app, or a
# commit status, could satisfy it.
test_branch_protection_requires_pr_check_and_binds_admins() {
  [ -f "$PROTECTION" ] || fail "no existe $PROTECTION"
  jq -e . "$PROTECTION" >/dev/null || fail "branch-protection.json no es JSON válido"
  assert_eq "$(jq -S -c . "$PROTECTION")" \
    '{"allow_deletions":false,"allow_force_pushes":false,"enforce_admins":true,"required_pull_request_reviews":{"dismiss_stale_reviews":false,"require_code_owner_reviews":false,"required_approving_review_count":0},"required_status_checks":{"checks":[{"app_id":15368,"context":"check"}],"strict":true},"restrictions":null}' \
    "protección pedida (PR con 0 aprobaciones, check de GitHub Actions al día con main, enforce_admins, sin push forzado ni borrado)"
}

run_tests "$@"
