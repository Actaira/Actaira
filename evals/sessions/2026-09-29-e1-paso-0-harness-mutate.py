#!/usr/bin/env python3
"""Mutation proofs of the harness PR of E1 step 0 (e1/paso-0-harness).

The project contact address in check-personal.sh (Marcos, 2026-09-29) and
merge-pr.sh waiting for the checks of a new PR (F-0019). Same method as the
other proofs: on a copy of a committed tree (git archive) in a temporary
directory, never in the live repo (F-0008). For each guard: break it in the
copy, run its test (it must be red, for that reason), restore the file byte for
byte and run the test again (it must be green). Exits 1 if any mutation is not
proven.
Usage: python3 evals/sessions/2026-09-29-e1-paso-0-harness-mutate.py [commit];
the commit defaults to HEAD, and the output records which one was copied.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
GITLEAKS = "gitleaks-8.30.1"
PERSONAL = "scripts/harness/check-personal.sh"
PERSONAL_T = "scripts/harness/tests/personal_test.sh"
MERGE = "scripts/harness/merge-pr.sh"
MERGE_T = "scripts/harness/tests/merge-pr_test.sh"

# (title, file, fragment, replacement, test file, test name)
MUTATIONS = [
    ("contacto: ningún correo permitido", PERSONAL,
     "CONTACT = contact_address()\n", 'CONTACT = ""\n',
     PERSONAL_T, "test_project_contact_email_passes_outside_code"),
    ("contacto: el correo en mayúsculas no se reconoce", PERSONAL,
     "if CONTACT and m.group().lower() == CONTACT:", "if CONTACT and m.group() == CONTACT:",
     PERSONAL_T, "test_project_contact_email_passes_outside_code"),
    ("contacto: con correo de contacto, cualquier gmail pasa", PERSONAL,
     "if CONTACT and m.group().lower() == CONTACT:", "if CONTACT:",
     PERSONAL_T, "test_other_personal_email_fails_next_to_the_contact_email"),
    ("contacto: también fijo en el código", PERSONAL,
     "                if code:\n", "                if False:\n",
     PERSONAL_T, "test_contact_email_fixed_in_code_fails"),
    ("contacto: los ficheros de código no se distinguen", PERSONAL,
     "code=bool(CODE.search(path))", "code=False",
     PERSONAL_T, "test_contact_email_fixed_in_code_fails"),
    ("contacto: un correo fijo si falta config/contact.env", PERSONAL,
     "    if top.returncode != 0 or not os.path.isfile(path):\n        return \"\"\n",
     "    if top.returncode != 0 or not os.path.isfile(path):\n        return \"proyecto.ficticio@\" + \"gmail.com\"\n",
     PERSONAL_T, "test_contact_email_without_its_config_fails"),
    ("merge-pr: sin esperar a que haya checks (F-0019)", MERGE,
     '  while ! out="$(gh pr checks "$pr" 2>&1)"; do\n', "  while false; do\n",
     MERGE_T, "test_waits_for_the_checks_of_a_new_pr"),
    ("merge-pr: espera sin límite (F-0019)", MERGE,
     '    if [ "$tries" -ge "${MERGE_PR_CHECK_TRIES:-30}" ]; then\n', "    if false; then\n",
     MERGE_T, "test_gives_up_when_no_check_appears"),
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
