#!/usr/bin/env bash
# Real run of E0 step 0.4, asked for by Marcos: the branch protection of main
# is in place, and the server rejects a direct push to main even from the repo
# owner (enforce_admins). Order:
#   1. the repo is the one origin pushes to; who pushes and whether they are
#      an admin is printed;
#   2. check-protection.sh must pass for that repo, or nothing is pushed;
#   3. a throwaway clone (mktemp) makes an empty commit on top of main and
#      pushes it straight to main, with local git hooks off and gh as the only
#      credential helper;
#   4. the push must fail with GitHub's protected branch error (GH006 and
#      "remote rejected"), and main must not move.
# The local guard (guard-git.sh) and pre-push are a best-effort net, not the
# boundary (ADR 0000): this script tests the boundary itself. Needs gh
# credentials with admin rights in the environment; the token is never printed.
# It tries a direct push to main on purpose, which CLAUDE.md forbids: run it
# only with Marcos's explicit authorization for that run. It is not part of
# make gate or make e2e-completo. Marcos asked for it on 2026-09-28 (step 0.4;
# run at 21:17:40Z and, in this version, at 21:53:38Z) and again on
# 2026-09-29, after the repo was recreated (run at 11:35:29Z):
# docs/estado/E0.md, "Discrepancias anotadas".
# Usage: GH_TOKEN=... bash evals/sessions/2026-09-28-e0-paso-4-real.sh
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
url="$(git -C "$repo_dir" remote get-url origin)"
if [[ ! "$url" =~ github\.com[:/]([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)$ ]]; then
  echo "MAL: origin ($url) no es un repo de GitHub"
  exit 1
fi
repo="${BASH_REMATCH[1]}/${BASH_REMATCH[2]%.git}"

echo "== 1. repo e identidad"
echo "repo de origin: $repo"
echo "cuenta de gh: $(gh api user --jq .login)"
echo "administradora del repo: $(gh api "repos/$repo" --jq .permissions.admin)"

echo "== 2. protección de main en GitHub"
(cd "$repo_dir" && scripts/harness/check-protection.sh --repo "$repo")

before="$(git ls-remote "$url" refs/heads/main | cut -f1)"
echo "main en GitHub antes: $before"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git clone -q --depth 1 --branch main "$url" "$tmp/clone"
git -C "$tmp/clone" -c user.name="E0 probe" -c user.email="probe@example.invalid" \
  commit -q --allow-empty -m "Probe: a direct update of main must be rejected by the server"

echo "== 3. push directo a main desde un clon temporal, sin hooks locales"
echo "git -c core.hooksPath=/dev/null -c credential.https://github.com.helper= -c 'credential.https://github.com.helper=!gh auth git-credential' push origin HEAD:refs/heads/main"
rc=0
out="$(git -C "$tmp/clone" -c core.hooksPath=/dev/null \
  -c credential.https://github.com.helper= -c 'credential.https://github.com.helper=!gh auth git-credential' \
  push origin HEAD:refs/heads/main 2>&1)" || rc=$?
printf '%s\n' "$out"
echo "exit: $rc"

after="$(git ls-remote "$url" refs/heads/main | cut -f1)"
echo "main en GitHub después: $after"

echo "== 4. resultado"
if [ "$rc" -eq 0 ]; then
  echo "MAL: el servidor aceptó el push"
  exit 1
fi
if ! grep -q "GH006: Protected branch update failed" <<< "$out" || ! grep -qF "[remote rejected]" <<< "$out"; then
  echo "MAL: el rechazo no es el de la protección de la rama en el servidor"
  exit 1
fi
if [ "$before" != "$after" ]; then
  echo "MAL: main se movió"
  exit 1
fi
echo "OK: el servidor rechazó el push directo a main por la protección, y main no se movió"
