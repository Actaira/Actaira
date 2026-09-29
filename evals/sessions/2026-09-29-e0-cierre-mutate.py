#!/usr/bin/env python3
"""Mutation proofs for the fixes of the E0 closing review (round 1).

Same method as the step proofs: on a copy of a committed tree (git archive)
in a temporary directory, never in the live repo (F-0008). For each fix:
remove it in the copy, run its test (it must be red, for that reason),
restore the file byte for byte and run the test again (it must be green).
Exits 1 if any mutation is not proven.
Usage: python3 evals/sessions/2026-09-29-e0-cierre-mutate.py [commit]; the
commit defaults to HEAD, and the output records which one was copied.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
GITLEAKS = "gitleaks-8.30.1"
SKIPS = "scripts/harness/check-skips.sh"
SCAN = "scripts/harness/secrets-scan.sh"
MERGE = "scripts/harness/merge-pr.sh"
MAKE = "Makefile"
SKIPS_T = "scripts/harness/tests/check-skips_test.sh"
SCAN_T = "scripts/harness/tests/secrets-scan_test.sh"
MERGE_T = "scripts/harness/tests/merge-pr_test.sh"
MAKE_T = "scripts/harness/tests/makefile_test.sh"

# (title, file, fragment, replacement, test file, test name)
MUTATIONS = [
    ("check-skips: juzga la compilacion del sistema en que corre", SKIPS,
     "GOOS=linux GOARCH=amd64 CGO_ENABLED=1 \\\n    go list", "go list",
     SKIPS_T, "test_build_is_judged_on_the_platform_of_the_required_check"),
    ("secrets-scan: historia de todas las refs", SCAN,
     '"$gl" git "${flags[@]}" --log-opts=HEAD .', '"$gl" git "${flags[@]}" .',
     SCAN_T, "test_sentinel_only_on_another_branch_passes"),
    ("secrets-scan: sin escanear los mensajes de commit", SCAN,
     '  (cd "$tmp/messages" && "$gl" dir "${msg_flags[@]}" .)\n', "",
     SCAN_T, "test_sentinel_in_a_commit_message_fails"),
    ("secrets-scan: mensajes sin la configuracion del repo", SCAN,
     '  if [ -z "$config" ] && [ -f .gitleaks.toml ]; then msg_flags+=(--config "$root/.gitleaks.toml"); fi\n', "",
     SCAN_T, "test_repo_config_applies_to_commit_messages"),
    ("merge-pr: sin escanear el mensaje del squash", MERGE,
     'if ! (cd "$work/texts" && "$gl" "${gl_args[@]}" .); then', "if false; then",
     MERGE_T, "test_refuses_a_squash_message_with_a_secret"),
    ("merge-pr: solo el mensaje del squash, no el texto del PR", MERGE,
     'cp "$work/squash-msg" "$work/pr-msg" "$work/texts/"', 'cp "$work/squash-msg" "$work/texts/"',
     MERGE_T, "test_refuses_a_pr_description_with_a_secret"),
    ("merge-pr: sin comprobar que existe el gitleaks fijado", MERGE,
     'if [ ! -x "$gl" ]; then', "if false; then",
     MERGE_T, "test_refuses_without_the_pinned_gitleaks"),
    ("make install-hooks: solo pre-push", MAKE,
     "for name in pre-push commit-msg; do", "for name in pre-push; do",
     MAKE_T, "test_install_hooks_installs_both_hooks"),
]


def run_test(copy, test_file, name):
    env = dict(os.environ)
    env["PATH"] = os.path.expanduser("~/.local/go/bin") + ":" + os.path.expanduser("~/go/bin") + ":" + env["PATH"]
    env["GITLEAKS"] = os.path.join(copy, ".tools", GITLEAKS)
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
    os.makedirs(os.path.join(copy, ".tools"))
    shutil.copy2(os.path.join(REPO, ".tools", GITLEAKS), os.path.join(copy, ".tools"))
    head = subprocess.run(["git", "-C", REPO, "rev-parse", rev], stdout=subprocess.PIPE, text=True, check=True).stdout.strip()
    print(f"copia de {head} en un directorio temporal; el repo no se toca\n")
    ok = True
    for title, path, old, new, test_file, name in MUTATIONS:
        full = os.path.join(copy, path)
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
        print(f"fichero: {path}; test: {test_file}::{name}")
        print(f"con la mutacion (debe ser rojo): exit {rc_mut}")
        print("\n".join(l for l in out_mut.splitlines() if l.strip())[-1200:])
        print(f"restaurado byte a byte: {restored}")
        print(f"con la correccion (debe ser verde): exit {rc_ok}: {out_ok.strip().splitlines()[-1]}")
        print(f"resultado: {'OK' if red and green and restored else 'MAL'}\n")
    shutil.rmtree(work)
    live = subprocess.run(["git", "-C", REPO, "status", "--porcelain", "--", "scripts", ".claude", ".github", "Makefile"],
                          stdout=subprocess.PIPE, text=True, check=True).stdout
    print("repo en uso sin cambios" if not live.strip() else "repo en uso CAMBIADO:\n" + live)
    ok = ok and not live.strip()
    print("TODAS OK" if ok else "HAY MUTACIONES MAL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
