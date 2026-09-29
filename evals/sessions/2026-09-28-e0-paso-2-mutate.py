#!/usr/bin/env python3
"""Mutation proofs for E0 step 0.2, round 2: remove each fix, run its test
(must be red), restore the file byte for byte and run the test again (green)."""
import os
import re
import shutil
import subprocess
import sys

REPO = "/home/usuario/actaira-ws/actaira"
T = "scripts/harness/tests/"

MUTATIONS = [
    ("M1: sin el unset de GITLEAKS_CONFIG*", "scripts/harness/secrets-scan.sh",
     "unset GITLEAKS_CONFIG GITLEAKS_CONFIG_TOML\n", "# unset quitado por la mutacion\n",
     T + "secrets-scan_test.sh", "test_environment_cannot_replace_the_config"),
    ("M2: escaneo del arbol con ruta absoluta", "scripts/harness/secrets-scan.sh",
     '(cd "$tmp" && "$gl" dir "${flags[@]}" .)', '"$gl" dir "${flags[@]}" "$tmp"',
     T + "secrets-scan_test.sh", "test_untracked_sentinel_fails_with_repo_relative_path"),
    ("M3a: sin exigir useDefault", "scripts/harness/secrets-scan.sh",
     "if [ -f .gitleaks.toml ] && ! grep", "if false && ! grep",
     T + "secrets-scan_test.sh", "test_repo_config_without_default_rules_fails"),
    ("M3b: sin justificar .gitleaksignore", "scripts/harness/secrets-scan.sh",
     "if [ -f .gitleaksignore ]; then", "if false; then",
     T + "secrets-scan_test.sh", "test_gitleaksignore_entry_without_fallo_fails"),
    ("M3c: sin justificar comentarios allow", "scripts/harness/secrets-scan.sh",
     'if [ -n "$hit" ] && ! cites_known_fallo "$hit"; then', "if false; then",
     T + "secrets-scan_test.sh", "test_allow_comment_without_fallo_fails"),
    ("Bajo: git add -A sobre el indice real", "scripts/harness/stop-gate.sh",
     'if GIT_INDEX_FILE="$idx_dir/index" git add -A', "if git add -A",
     T + "stop-gate_test.sh", "test_hook_leaves_the_real_index_untouched"),
    ("Bajo: curl sin --max-time", "scripts/harness/fetch-tool.sh",
     " --max-time 300", "",
     T + "fetch-tool_test.sh", "test_download_has_retries_and_time_limits"),
    ("Bajo: install.sh sin comprobar la raiz del repo", "scripts/harness/install.sh",
     '[ "$top" = "$(cd "$repo" && pwd -P)" ] ||', "true ||",
     T + "install_test.sh", "test_subdirectory_of_a_repo_is_refused"),
    ("Bajo: install.sh sin restaurar en el trap", "scripts/harness/install.sh",
     "trap 'restore_kept; rm -rf \"$keep_dir\"' EXIT", "trap 'rm -rf \"$keep_dir\"' EXIT",
     T + "install_test.sh", "test_failed_reinstall_keeps_fallos_entries"),
    ("Medio: GOFLAGS del entorno llega a go test", "Makefile",
     "unexport GOFLAGS\n", "\n",
     T + "makefile_test.sh", "test_goflags_from_environment_cannot_filter_tests"),
    ("Medio: sin comprobar go env GOFLAGS", "Makefile",
     '\t@if [ -n "$$(go env GOFLAGS)" ]', '\t@if false',
     T + "makefile_test.sh", "test_goflags_in_go_env_file_fails"),
    ("Makefile: fmt-check sin exit 1", "Makefile",
     'echo "gofmt: ficheros sin formatear:"; echo "$$bad"; exit 1; fi',
     'echo "gofmt: ficheros sin formatear:"; echo "$$bad"; fi',
     T + "makefile_test.sh", "test_fmt_check_fails_on_unformatted_go"),
    ("Makefile: fmt-check entra en testdata", "Makefile",
     " -o -path '*/testdata' -prune", "",
     T + "makefile_test.sh", "test_fmt_check_skips_testdata_fixtures"),
    ("Makefile: go test que traga el rojo", "Makefile",
     "\tgo test -count=1 -shuffle=on ./...\n", "\tgo test -count=1 -shuffle=on ./... || true\n",
     T + "makefile_test.sh", "test_test_target_fails_on_red_go_test"),
]


def run_test(test_file, name):
    env = dict(os.environ)
    env["PATH"] = os.path.expanduser("~/.local/go/bin") + ":" + os.path.expanduser("~/go/bin") + ":" + env["PATH"]
    env["GITLEAKS"] = ".tools/gitleaks-8.30.1"
    p = subprocess.run(["bash", test_file, name], cwd=REPO, env=env,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=300)
    return p.returncode, re.sub(r"\x1b\[[0-9;]*m", "", p.stdout)


def main():
    ok = True
    for title, path, old, new, test_file, name in MUTATIONS:
        full = os.path.join(REPO, path)
        backup = full + ".mutation-backup"
        original = open(full, encoding="utf-8").read()
        if original.count(old) != 1:
            print(f"### {title}\nNO APLICABLE: el fragmento aparece {original.count(old)} veces en {path}\n")
            ok = False
            continue
        shutil.copy2(full, backup)
        try:
            with open(full, "w", encoding="utf-8") as fh:
                fh.write(original.replace(old, new))
            rc_mut, out_mut = run_test(test_file, name)
        finally:
            shutil.copy2(backup, full)
            os.remove(backup)
        restored = open(full, encoding="utf-8").read() == original
        rc_ok, out_ok = run_test(test_file, name)
        red = rc_mut != 0 and f"--- FAIL: {name}" in out_mut
        green = rc_ok == 0 and f"--- PASS: {name}" in out_ok
        ok = ok and red and green and restored
        print(f"### {title}")
        print(f"fichero: {path}; test: {test_file}::{name}")
        print(f"con la mutacion (debe ser rojo): exit {rc_mut}")
        print("\n".join(l for l in out_mut.splitlines() if l.strip())[-1500:])
        print(f"restaurado byte a byte: {restored}")
        print(f"con la correccion (debe ser verde): exit {rc_ok}: {out_ok.strip().splitlines()[-1]}")
        print(f"resultado: {'OK' if red and green and restored else 'MAL'}\n")
    print("TODAS OK" if ok else "HAY MUTACIONES MAL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
