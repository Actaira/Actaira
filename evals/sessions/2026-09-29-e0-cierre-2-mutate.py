#!/usr/bin/env python3
"""Mutation proofs for Marcos's decisions of 2026-09-29 at the E0 closing.

The guards of F-0015 (check-personal.sh), F-0016 (permissions), L-007 (orders in
CLAUDE.md and the skills pass the guard) and the new check prerequisite. Same
method as the other proofs: on a copy of a committed tree (git archive) in a
temporary directory, never in the live repo (F-0008). For each guard: break it
in the copy, run its test (it must be red, for that reason), restore the file
byte for byte and run the test again (it must be green). Exits 1 if any
mutation is not proven.
Usage: python3 evals/sessions/2026-09-29-e0-cierre-2-mutate.py [commit]; the
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
PERSONAL = "scripts/harness/check-personal.sh"
SETTINGS = ".claude/settings.json"
MAKE = "Makefile"
PERSONAL_T = "scripts/harness/tests/personal_test.sh"
SETTINGS_T = "scripts/harness/tests/settings_test.sh"
GUARD_T = "scripts/harness/tests/guard-git_test.sh"
MAKE_T = "scripts/harness/tests/makefile_test.sh"
MERGE = "scripts/harness/merge-pr.sh"
MERGE_T = "scripts/harness/tests/merge-pr_test.sh"
MERGE_OLD = "`gh pr create` y `scripts/harness/merge-pr.sh`, que espera"
MERGE_BAD = "`gh pr create`, `gh pr checks --watch` y `gh pr " + "merge --squash --delete-branch`, que espera"

# (title, file, fragment, replacement, test file, test name)
MUTATIONS = [
    ("personal: sin quitar los acentos", PERSONAL,
     'not unicodedata.combining(c) and unicodedata.category(c) != "Cf"', 'unicodedata.category(c) != "Cf"',
     PERSONAL_T, "test_term_in_a_tracked_file_fails_without_printing_it"),
    ("personal: sin quitar los caracteres invisibles", PERSONAL,
     'not unicodedata.combining(c) and unicodedata.category(c) != "Cf"', "not unicodedata.combining(c)",
     PERSONAL_T, "test_term_in_a_path_other_encodings_or_with_invisible_characters_fails"),
    ("personal: solo palabras sueltas, no frases", PERSONAL,
     "max_words = max((len(k) for k in terms), default=0)", "max_words = 1",
     PERSONAL_T, "test_term_in_a_tracked_file_fails_without_printing_it"),
    ("personal: el hallazgo enseña el texto", PERSONAL,
     'found.append((f"dato personal ({category})", bisect', 'found.append((f"dato personal ({category}) {text}", bisect',
     PERSONAL_T, "test_term_in_a_tracked_file_fails_without_printing_it"),
    ("personal: sin los ficheros sin seguir", PERSONAL,
     'git("ls-files", "-z", "--cached", "--others", "--exclude-standard")', 'git("ls-files", "-z", "--cached")',
     PERSONAL_T, "test_untracked_file_fails_and_ignored_file_passes"),
    ("personal: sin los nombres de fichero", PERSONAL,
     'for what, _ in findings_in(path.replace("/", " / ")):', "for what, _ in []:",
     PERSONAL_T, "test_term_in_a_path_other_encodings_or_with_invisible_characters_fails"),
    ("personal: sin UTF-16", PERSONAL,
     "        if data.startswith(bom):", "        if False:",
     PERSONAL_T, "test_term_in_a_path_other_encodings_or_with_invisible_characters_fails"),
    ("personal: sin cp1252", PERSONAL,
     'return data.decode("cp1252", "replace")', 'return data.decode("utf-8", "replace")',
     PERSONAL_T, "test_term_in_a_path_other_encodings_or_with_invisible_characters_fails"),
    ("personal: sin el indice", PERSONAL,
     'git("diff", "--cached", "--no-color")', 'git("diff", "--no-color")',
     PERSONAL_T, "test_term_only_in_the_index_or_in_an_earlier_commit_fails"),
    ("personal: sin las lineas que añaden los commits", PERSONAL,
     "        found |= {w for w, _ in findings_in(added_lines(patch))}\n", "",
     PERSONAL_T, "test_term_only_in_the_index_or_in_an_earlier_commit_fails"),
    ("personal: sin la historia de la rama", PERSONAL,
     'for sha in git("rev-list", rng).decode().split():', "for sha in []:",
     PERSONAL_T, "test_commit_message_and_identity_fail"),
    ("personal: tambien la historia de main (F-0009)", PERSONAL,
     'rng = "refs/remotes/origin/main..HEAD" if has_main else "HEAD"', 'rng = "HEAD"',
     PERSONAL_T, "test_only_the_commits_of_the_branch_are_scanned"),
    ("personal: sin buscar correos", PERSONAL,
     "        for m in EMAIL.finditer(text):", '        for m in EMAIL.finditer(""):',
     PERSONAL_T, "test_personal_email_fails_outside_testdata_and_identities"),
    ("personal: correos tambien en testdata", PERSONAL,
     'fixture = path.startswith("testdata/") or "/testdata/" in path', "fixture = False",
     PERSONAL_T, "test_personal_email_fails_outside_testdata_and_identities"),
    ("personal: correos tambien en las identidades", PERSONAL,
     "found = {w for w, _ in findings_in(who, emails=False)}", "found = {w for w, _ in findings_in(who)}",
     PERSONAL_T, "test_personal_email_fails_outside_testdata_and_identities"),
    ("personal: sin lista en local, pasa", PERSONAL,
     'echo "check-personal: falta la lista privada de términos ($terms)" >&2\n    exit 1',
     'echo "check-personal: falta la lista privada de términos ($terms)" >&2\n    exit 0',
     PERSONAL_T, "test_missing_list_fails_locally_and_is_announced_in_ci"),
    ("personal: --files no mira los ficheros", PERSONAL,
     'for what, line in findings_in(decode(open(path, "rb").read())):', "for what, line in []:",
     PERSONAL_T, "test_files_mode_scans_only_the_given_files"),
    ("merge-pr: sin buscar datos personales en el squash", MERGE,
     'if ! "$here/check-personal.sh" --files "$work/squash-msg" "$work/pr-msg"; then', "if false; then",
     MERGE_T, "test_refuses_a_squash_message_with_personal_data"),
    ("personal: fuera de make check", MAKE,
     "check: weakeners pipes fallos skips attribution personal fmt-check",
     "check: weakeners pipes fallos skips attribution fmt-check",
     MAKE_T, "test_check_runs_every_harness_check"),
    ("permisos: gh pr checkout sin denegar", SETTINGS,
     '      "Bash(gh pr checkout*)",\n', "",
     SETTINGS_T, "test_settings_keep_foreign_pr_code_and_credentials_out"),
    ("permisos: lectura de ~/.config/gh sin denegar", SETTINGS,
     '      "Read(~/.config/gh/**)",\n', "",
     SETTINGS_T, "test_settings_keep_foreign_pr_code_and_credentials_out"),
    ("permisos: gh pr * permitido otra vez", SETTINGS,
     '"Bash(gh pr create*)",', '"Bash(gh pr *)",',
     SETTINGS_T, "test_settings_keep_foreign_pr_code_and_credentials_out"),
    ("L-007: CLAUDE.md manda una fusión que el guard bloquea", "CLAUDE.md",
     MERGE_OLD, MERGE_BAD,
     GUARD_T, "test_orders_in_claude_md_and_skills_pass_the_guard"),
    ("permisos: fetch de refs/pull/ sin denegar (patron con espacio)", SETTINGS,
     '"Bash(git fetch *pull/*)"', '"Bash(git fetch * pull/*)"',
     SETTINGS_T, "test_settings_keep_foreign_pr_code_and_credentials_out"),
    ("permisos: alias gh co sin denegar", SETTINGS,
     '      "Bash(git pull *pull/*)",\n      "Bash(gh co *)"\n', '      "Bash(git pull *pull/*)"\n',
     SETTINGS_T, "test_settings_keep_foreign_pr_code_and_credentials_out"),
    ("merge-pr: fusion sin el correo noreply de autor", MERGE,
     ' \\\n  --author-email "$author_email"\n', "\n",
     MERGE_T, "test_merges_a_clean_pr_after_green_checks"),
    ("merge-pr: sin comprobar el autor del commit que entro", MERGE,
     'if [ "$merged_email" != "$author_email" ]; then', "if false; then",
     MERGE_T, "test_checks_the_author_of_the_commit_that_entered_main"),
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
