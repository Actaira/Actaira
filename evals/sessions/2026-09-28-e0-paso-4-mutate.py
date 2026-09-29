#!/usr/bin/env python3
"""Mutation proofs for E0 step 0.4 (CI and branch protection).

Same method as the step 0.3 proofs: on a copy of the committed tree (git
archive HEAD) in a temporary directory, never in the live repo (F-0008). For
each property: break it in the copy (the workflow, the protection JSON, the
Makefile, check-weakeners.sh or check-protection.sh), or add a file that
breaks it (fragment None), run its test (it must be red, for that reason),
restore the copy byte for byte and run the test again (it must be green).
Exits 1 if any mutation is not proven.
Usage: python3 evals/sessions/2026-09-28-e0-paso-4-mutate.py [commit]; the commit defaults to HEAD, and the
output records which one was copied, so a later tree can rerun the proofs of
the commit they were made on.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CI = ".github/workflows/ci.yml"
OTHER = ".github/workflows/lint.yml"
PROT = "docs/estado/branch-protection.json"
CHECK = "scripts/harness/check-protection.sh"
WEAK = "scripts/harness/check-weakeners.sh"
MAKE = "Makefile"
CI_T = "scripts/harness/tests/ci_test.sh"
CHECK_T = "scripts/harness/tests/check-protection_test.sh"
WEAK_T = "scripts/harness/tests/check-weakeners_test.sh"
MAKE_T = "scripts/harness/tests/makefile_test.sh"
LIB_T = "scripts/harness/tests/lib_test.sh"
SETTINGS_T = "scripts/harness/tests/settings_test.sh"
RUN = "      - run: make check\n"
EXACT = "test_workflow_is_exactly_the_reviewed_one"
REVIEWS = ('"required_pull_request_reviews": {\n    "required_approving_review_count": 0,\n'
           '    "dismiss_stale_reviews": false,\n    "require_code_owner_reviews": false\n  },')

# (title, file, fragment or None to create the file, replacement or content, test file, test name)
MUTATIONS = [
    # .github/workflows/ci.yml
    ("ci: el job lleva name (cambia el nombre del check)", CI,
     "  check:\n    runs-on", "  check:\n    name: CI\n    runs-on",
     CI_T, "test_workflow_has_a_single_check_job_running_make_check"),
    ("ci: un segundo job", CI,
     RUN, RUN + "  other:\n    runs-on: ubuntu-latest\n    steps:\n      - run: make lint\n",
     CI_T, "test_workflow_has_a_single_check_job_running_make_check"),
    ("ci: no ejecuta make check", CI,
     RUN, "      - run: make test\n",
     CI_T, "test_workflow_has_a_single_check_job_running_make_check"),
    ("ci: otro sistema", CI,
     "    runs-on: ubuntu-latest\n", "    runs-on: macos-latest\n",
     CI_T, "test_workflow_has_a_single_check_job_running_make_check"),
    ("ci: sin pull_request", CI,
     "  pull_request:\n", "",
     CI_T, "test_workflow_runs_on_every_pull_request_and_push_to_main"),
    ("ci: filtro de rutas", CI,
     "  pull_request:\n", "  pull_request:\n    paths: ['**.go']\n",
     CI_T, "test_workflow_runs_on_every_pull_request_and_push_to_main"),
    ("ci: sin los push a main", CI,
     "    branches: [main]\n", "",
     CI_T, "test_workflow_runs_on_every_pull_request_and_push_to_main"),
    ("ci: accion fijada por etiqueta", CI,
     "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1", "actions/checkout@v7.0.1",
     CI_T, "test_actions_are_pinned_by_commit_sha"),
    ("ci: SHA corto", CI,
     "actions/setup-go@b7ad1dad31e06c5925ef5d2fc7ad053ef454303e # v7.0.0", "actions/setup-go@b7ad1da # v7.0.0",
     CI_T, "test_actions_are_pinned_by_commit_sha"),
    ("ci: accion sin fijar en estilo flujo (F-0014)", CI,
     RUN, "      - {uses: some-owner/some-action@main}\n" + RUN,
     CI_T, "test_actions_are_pinned_by_commit_sha"),
    ("ci: contents write en el workflow", CI,
     "permissions:\n  contents: read\n\njobs:", "permissions:\n  contents: write\n\njobs:",
     CI_T, "test_permissions_are_read_only"),
    ("ci: un permiso de escritura en el job", CI,
     "    permissions:\n      contents: read\n", "    permissions:\n      contents: read\n      pull-requests: write\n",
     CI_T, "test_permissions_are_read_only"),
    ("ci: sin fetch-depth 0", CI,
     "          fetch-depth: 0\n", "",
     CI_T, "test_checkout_fetches_full_history_without_credentials"),
    ("ci: credenciales guardadas", CI,
     "          persist-credentials: false\n", "",
     CI_T, "test_checkout_fetches_full_history_without_credentials"),
    # F-0014: variants that keep `check` green without running make check
    ("F-0014: if en el job (un job saltado cuenta como verde)", CI,
     "  check:\n    runs-on", "  check:\n    if: github.event.pull_request.draft == false\n    runs-on",
     CI_T, EXACT),
    ("F-0014: paso make check con if: false", CI,
     RUN, RUN + "        if: false\n",
     CI_T, EXACT),
    ("F-0014: continue-on-error con una expresion", CI,
     RUN, RUN + "        continue-on-error: ${{ true }}\n",
     CI_T, EXACT),
    ("F-0014: otro shell que no ejecuta nada", CI,
     RUN, RUN + "        shell: bash -c true {0}\n",
     CI_T, EXACT),
    ("F-0014: un paso previo escribe un GNUmakefile", CI,
     RUN, "      - run: printf 'check:\\n\\t@echo check: OK\\n' > GNUmakefile\n" + RUN,
     CI_T, EXACT),
    ("F-0014: otro workflow con un job check", OTHER,
     None, "name: lint\non:\n  pull_request:\njobs:\n  check:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo fast\n",
     CI_T, "test_no_other_workflow_publishes_a_check_job"),
    ("F-0014: otro workflow con un job llamado check", OTHER,
     None, "name: lint\non:\n  pull_request:\njobs:\n  fast:\n    name: check\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo fast\n",
     CI_T, "test_no_other_workflow_publishes_a_check_job"),
    ("F-0014: otro workflow con una accion sin fijar", OTHER,
     None, "name: lint\non:\n  pull_request:\njobs:\n  lint:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: actions/checkout@v7\n",
     CI_T, "test_actions_are_pinned_by_commit_sha"),
    ("F-0014: check sin test-harness ni secrets", MAKE,
     "check: weakeners pipes fallos skips attribution fmt-check lint test determinism test-harness secrets\n",
     "check: weakeners pipes fallos skips attribution fmt-check lint test determinism\n",
     MAKE_T, "test_check_runs_every_harness_check"),
    ("F-0014: gate sin check", MAKE,
     "gate: check evals-paso e2e-rapido\n", "gate: evals-paso e2e-rapido\n",
     MAKE_T, "test_check_runs_every_harness_check"),
    ("F-0014: weakeners solo con continue-on-error literal", WEAK,
     "grep -nE 'continue-on-error[[:space:]]*:' \"$f\"", "grep -nE 'continue-on-error:[[:space:]]*true' \"$f\"",
     WEAK_T, "test_continue_on_error_with_expression_fails"),
    # docs/estado/branch-protection.json
    ("proteccion pedida: sin enforce_admins", PROT,
     '"enforce_admins": true', '"enforce_admins": false',
     CI_T, "test_branch_protection_requires_pr_check_and_binds_admins"),
    ("proteccion pedida: sin strict", PROT,
     '"strict": true', '"strict": false',
     CI_T, "test_branch_protection_requires_pr_check_and_binds_admins"),
    ("proteccion pedida: sin el check", PROT,
     '"checks": [{ "context": "check", "app_id": 15368 }]', '"checks": []',
     CI_T, "test_branch_protection_requires_pr_check_and_binds_admins"),
    ("proteccion pedida: check de cualquier app", PROT,
     '"checks": [{ "context": "check", "app_id": 15368 }]', '"checks": [{ "context": "check" }]',
     CI_T, "test_branch_protection_requires_pr_check_and_binds_admins"),
    ("proteccion pedida: sin PR obligatorio", PROT,
     REVIEWS, '"required_pull_request_reviews": null,',
     CI_T, "test_branch_protection_requires_pr_check_and_binds_admins"),
    ("proteccion pedida: push forzado", PROT,
     '"allow_force_pushes": false', '"allow_force_pushes": true',
     CI_T, "test_branch_protection_requires_pr_check_and_binds_admins"),
    ("proteccion pedida: borrado", PROT,
     '"allow_deletions": false', '"allow_deletions": true',
     CI_T, "test_branch_protection_requires_pr_check_and_binds_admins"),
    # scripts/harness/check-protection.sh
    ("comprobador: no compara el check", CHECK,
     "  required_checks: ([.required_status_checks.checks[]? | {context, app_id}] | sort_by(.context)),\n", "",
     CHECK_T, "test_missing_required_check_fails"),
    ("comprobador: no compara la app del check", CHECK,
     "{context, app_id}", "{context}",
     CHECK_T, "test_check_from_any_app_fails"),
    ("comprobador: no compara strict", CHECK,
     "  strict: .required_status_checks.strict,\n", "",
     CHECK_T, "test_branch_not_up_to_date_fails"),
    ("comprobador: no compara enforce_admins", CHECK,
     "  enforce_admins: flag(.enforce_admins),\n", "",
     CHECK_T, "test_admins_not_bound_fails"),
    ("comprobador: no compara el PR obligatorio", CHECK,
     "  pull_request_reviews: (.required_pull_request_reviews | if . == null then null else {approvals: .required_approving_review_count, dismiss_stale_reviews, require_code_owner_reviews} end),\n", "",
     CHECK_T, "test_pull_request_not_required_fails"),
    ("comprobador: no compara las excepciones al PR", CHECK,
     "  pull_request_bypass: ((.required_pull_request_reviews.bypass_pull_request_allowances // {}) | [.users[]?, .teams[]?, .apps[]?] | length),\n", "",
     CHECK_T, "test_pull_request_bypass_fails"),
    ("comprobador: no compara el push forzado", CHECK,
     "  allow_force_pushes: flag(.allow_force_pushes),\n", "",
     CHECK_T, "test_force_pushes_or_deletions_allowed_fail"),
    ("comprobador: no compara el borrado", CHECK,
     "  allow_deletions: flag(.allow_deletions),\n", "",
     CHECK_T, "test_force_pushes_or_deletions_allowed_fail"),
    ("comprobador: lee la respuesta sin .enabled", CHECK,
     "def flag(f): if $live then (f | .enabled) else f end;", "def flag(f): f;",
     CHECK_T, "test_matching_protection_passes"),
    ("comprobador: repo que adivina gh en vez del pedido", CHECK,
     'gh api "repos/$repo/branches/main/protection"', "gh api 'repos/{owner}/{repo}/branches/main/protection'",
     CHECK_T, "test_matching_protection_passes"),
    ("comprobador: repo fijo en vez del de origin", CHECK,
     'repo="${BASH_REMATCH[1]}/${BASH_REMATCH[2]%.git}"', 'repo="Actaira/Actaira"',
     CHECK_T, "test_repo_comes_from_the_origin_remote"),
    ("comprobador: acepta un origin que no es de GitHub", CHECK,
     'if [[ "$url" =~ github\\.com[:/]([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)$ ]]; then',
     'if [[ "$url" =~ ([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)$ ]]; then',
     CHECK_T, "test_repo_comes_from_the_origin_remote"),
    ("comprobador: una rama sin proteccion no se detecta como tal", CHECK,
     'if ! raw="$(gh api "repos/$repo/branches/main/protection")"; then',
     'if ! raw="$(gh api "repos/$repo/branches/main/protection" || echo \'{}\')"; then',
     CHECK_T, "test_unprotected_branch_fails"),
    ("comprobador: siempre OK", CHECK,
     'if [ "$live" = "$expected" ]; then', "if true; then",
     CHECK_T, "test_admins_not_bound_fails"),
    # Round 2 of the adversarial pass
    ("ronda 2: ci_test toma ci.yml del entorno", CI_T,
     'CI="$REPO_DIR/.github/workflows/ci.yml"', 'CI="${CI_FILE:-$REPO_DIR/.github/workflows/ci.yml}"',
     LIB_T, "test_no_test_takes_its_target_from_the_environment"),
    ("ronda 2: settings_test toma settings.json del entorno", SETTINGS_T,
     'SETTINGS="$REPO_DIR/.claude/settings.json"', 'SETTINGS="${SETTINGS_FILE:-$REPO_DIR/.claude/settings.json}"',
     LIB_T, "test_no_test_takes_its_target_from_the_environment"),
    ("ronda 2: la guardia de otros workflows mira un directorio sin ci.yml", CI_T,
     'CI="$REPO_DIR/.github/workflows/ci.yml"', 'CI="$REPO_DIR/.github/workflow/ci.yml"',
     CI_T, "test_no_other_workflow_publishes_a_check_job"),
    ("ronda 2: test fuera de .PHONY", MAKE,
     " lint test test-harness ", " lint test-harness ",
     MAKE_T, "test_check_runs_every_harness_check"),
]


def run_test(copy, test_file, name):
    env = dict(os.environ)
    env["PATH"] = os.path.expanduser("~/.local/go/bin") + ":" + os.path.expanduser("~/go/bin") + ":" + env["PATH"]
    env.pop("GH_REPO", None)
    p = subprocess.run(["bash", test_file, name], cwd=copy, env=env,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=300)
    return p.returncode, re.sub(r"\x1b\[[0-9;]*m", "", p.stdout)


def main():
    work = tempfile.mkdtemp(prefix="mutate-")
    copy = os.path.join(work, "repo")
    os.makedirs(copy)
    rev = sys.argv[1] if len(sys.argv) > 1 else "HEAD"
    tree = subprocess.run(["git", "-C", REPO, "archive", rev], stdout=subprocess.PIPE, check=True).stdout
    subprocess.run(["tar", "-x", "-C", copy], input=tree, check=True)
    head = subprocess.run(["git", "-C", REPO, "rev-parse", rev], stdout=subprocess.PIPE, text=True, check=True).stdout.strip()
    print(f"copia de {head} en un directorio temporal; el repo no se toca\n")
    ok = True
    for title, path, old, new, test_file, name in MUTATIONS:
        full = os.path.join(copy, path)
        if old is None:
            if os.path.exists(full):
                print(f"### {title}\nNO APLICABLE: {path} ya existe\nresultado: MAL\n")
                ok = False
                continue
            with open(full, "w", encoding="utf-8") as fh:
                fh.write(new)
            rc_mut, out_mut = run_test(copy, test_file, name)
            os.remove(full)
            restored = not os.path.exists(full)
        else:
            original = open(full, encoding="utf-8").read()
            if original.count(old) != 1:
                print(f"### {title}\nNO APLICABLE: el fragmento aparece {original.count(old)} veces en {path}\nresultado: MAL\n")
                ok = False
                continue
            with open(full, "w", encoding="utf-8") as fh:
                fh.write(original.replace(old, new))
            rc_mut, out_mut = run_test(copy, test_file, name)
            with open(full, "w", encoding="utf-8") as fh:
                fh.write(original)
            restored = open(full, encoding="utf-8").read() == original
        rc_ok, out_ok = run_test(copy, test_file, name)
        red = rc_mut != 0 and f"--- FAIL: {name}" in out_mut
        green = rc_ok == 0 and f"--- PASS: {name}" in out_ok
        ok = ok and red and green and restored
        print(f"### {title}")
        print(f"fichero: {path}{' (creado)' if old is None else ''}; test: {test_file}::{name}")
        print(f"con la mutacion (debe ser rojo): exit {rc_mut}")
        print("\n".join(l for l in out_mut.splitlines() if l.strip())[-1200:])
        print(f"restaurado byte a byte: {restored}")
        print(f"con la correccion (debe ser verde): exit {rc_ok}: {out_ok.strip().splitlines()[-1]}")
        print(f"resultado: {'OK' if red and green and restored else 'MAL'}\n")
    shutil.rmtree(work)
    live = subprocess.run(["git", "-C", REPO, "status", "--porcelain", "--", "scripts", ".claude", ".github", "docs/estado", "Makefile"],
                          stdout=subprocess.PIPE, text=True, check=True).stdout
    print("repo en uso sin cambios" if not live.strip() else "repo en uso CAMBIADO:\n" + live)
    ok = ok and not live.strip()
    print("TODAS OK" if ok else "HAY MUTACIONES MAL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
