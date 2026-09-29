#!/usr/bin/env python3
"""Mutation proofs of E1 step 1.1 (e1/paso-1-estructura).

The CLI skeleton, the layout and repository tests (internal/repotest), the
//nolint rule of check-skips.sh and golangci-lint in make lint. Same method as
the other proofs: on a copy of a committed tree (git archive) in a temporary
directory, never in the live repo (F-0008). For each guard: break it in the
copy, run its test (it must be red, for that reason), restore the file byte for
byte and run the test again (it must be green). Exits 1 if any mutation is not
proven. A test named go:<package> runs with go test -v -run '^Name$'.
Usage: python3 evals/sessions/2026-09-29-e1-paso-1-mutate.py [commit]; the
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
TOOLS = [GITLEAKS, "golangci-lint-2.14.0"]
CLI = "internal/cli/cli.go"
CLI_T = "go:./internal/cli"
REPO_T = "go:./internal/repotest"
SKIPS = "scripts/harness/check-skips.sh"
SKIPS_T = "scripts/harness/tests/check-skips_test.sh"
MAKE_T = "scripts/harness/tests/makefile_test.sh"

# (title, file, fragment, replacement, test file, test name)
MUTATIONS = [
    ("cli: version sin el nombre", CLI,
     'fmt.Fprintf(stdout, "actaira %s\\n", version.Version)', 'fmt.Fprintf(stdout, "%s\\n", version.Version)',
     CLI_T, "TestVersionPrintsTheBuildVersion"),
    ("cli: version acepta argumentos", CLI,
     '\tif len(args) > 0 {\n\t\tsay(stderr, "actaira: %q takes no arguments\\n", "version")\n',
     '\tif false {\n\t\tsay(stderr, "actaira: %q takes no arguments\\n", "version")\n',
     CLI_T, "TestVersionRejectsArguments"),
    ("cli: sin comando sale con 0", CLI,
     "\t\twriteUsage(stderr)\n\t\treturn ExitUsage\n", "\t\twriteUsage(stderr)\n\t\treturn ExitOK\n",
     CLI_T, "TestNoCommandPrintsUsageAndIsAUsageError"),
    ("cli: comando desconocido sale con 0", CLI,
     "\twriteUsage(stderr)\n\treturn ExitUsage\n}\n", "\twriteUsage(stderr)\n\treturn ExitOK\n}\n",
     CLI_T, "TestUnknownCommandIsAUsageError"),
    ("cli: --help no es ayuda", CLI,
     '\tcase "-h", "--help":\n', '\tcase "-h":\n',
     CLI_T, "TestHelpPrintsUsageAndSucceeds"),
    ("cli: el uso no lista los comandos", CLI,
     '\t\tfmt.Fprintf(&b, "  %-8s %s\\n", c.name, c.summary)\n', "\t\t_ = c\n",
     CLI_T, "TestCommandsAreImplementedAndListedInTheUsage"),
    ("cli: otro código de error interno", CLI,
     "\tExitInternal = 3 ", "\tExitInternal = 4 ",
     CLI_T, "TestExitCodesAreTheDocumentedOnes"),
    ("repotest: pkg importa internal", "pkg/model/doc.go",
     "package model\n", 'package model\n\nimport _ "github.com/actaira/actaira/internal/version"\n',
     REPO_T, "TestPkgDoesNotImportInternal"),
    ("repotest: el test de pkg pasa en vacío", "internal/repotest/repotest_test.go",
     "\t\tpackages[filepath.ToSlash(filepath.Dir(rel))] = true\n", "\t\t_ = rel\n",
     REPO_T, "TestPkgDoesNotImportInternal"),
    ("repotest: licencia cambiada", "LICENSE",
     "Version 2.0, January 2004", "Version 2.1, January 2004",
     REPO_T, "TestLicenseIsTheOfficialApache2"),
    ("repotest: el README en inglés enseña un comando que no existe", "README.md",
     "./actaira version\n", "./actaira discover\n",
     REPO_T, "TestReadmesOnlyNameImplementedCommands"),
    ("repotest: el README en castellano enseña un comando que no existe", "README.es.md",
     "./actaira version\n", "./actaira lock\n",
     REPO_T, "TestReadmesOnlyNameImplementedCommands"),
    ("repotest: SECURITY.md con otro correo que el de contacto", "config/contact.env",
     "ACTAIRA_CONTACT_EMAIL=actairasolutions@", "ACTAIRA_CONTACT_EMAIL=otro.contacto@",
     REPO_T, "TestSecurityPolicyGivesTheProjectContact"),
    ("nolint: sin F-NNNN pasa", SKIPS,
     '    problem="//nolint sin un F-NNNN de FALLOS.md en esa línea"\n', '    problem=""\n',
     SKIPS_T, "test_nolint_without_a_fallo_fails"),
    ("nolint: vale cualquier F-NNNN", SKIPS,
     '  if [ -z "$problem" ] && ! cites_known_fallo "$text" "$known"; then\n',
     '  if [ -z "$problem" ] && [[ ! "$text" =~ F-[0-9]{4} ]]; then\n',
     SKIPS_T, "test_nolint_citing_an_unknown_fallo_fails"),
    ("nolint: sin linter pasa", SKIPS,
     '        problem="//nolint sin nombrar su linter"\n', '        problem=""\n',
     SKIPS_T, "test_nolint_without_a_linter_fails"),
    ("nolint: la forma mal escrita pasa", SKIPS,
     '        problem="//nolint mal escrito (golangci-lint lo aplica igual; se escribe //nolint:<linter> // F-NNNN)"\n',
     '        problem=""\n',
     SKIPS_T, "test_nolint_without_a_linter_fails"),
    ("nolint: también en testdata", SKIPS,
     "-E '//[/[:space:]]*nolint' -- '*.go' ':(exclude,glob)**/testdata/**')\"", "-E '//[/[:space:]]*nolint' -- '*.go')\"",
     SKIPS_T, "test_nolint_in_testdata_is_ignored"),
    ("lint: sin golangci-lint", "Makefile",
     "\t$(GOLANGCI_LINT) run --allow-serial-runners ./...\n", "",
     MAKE_T, "test_lint_runs_golangci_lint_with_the_repo_config"),
    ("lint: sin nolintlint", ".golangci.yml",
     "    - nolintlint\n", "",
     MAKE_T, "test_lint_runs_golangci_lint_with_the_repo_config"),
    # Review round 1 (F-0020 and the rest of the round).
    ("nolint: la forma con barras y espacios no se ve", SKIPS,
     "--untracked -E '//[/[:space:]]*nolint' -- '*.go'", "--untracked -E '//nolint' -- '*.go'",
     SKIPS_T, "test_nolint_forms_that_golangci_lint_also_reads_fail"),
    ("nolint: la guardia ya no cubre lo que aplica golangci-lint", SKIPS,
     "--untracked -E '//[/[:space:]]*nolint' -- '*.go'", "--untracked -E '//nolint' -- '*.go'",
     SKIPS_T, "test_every_nolint_form_that_golangci_lint_applies_is_flagged"),
    ("nolint: las mayúsculas no se ven", SKIPS,
     "git grep -n -I -i --untracked -E '//[/[:space:]]*nolint'", "git grep -n -I --untracked -E '//[/[:space:]]*nolint'",
     SKIPS_T, "test_nolint_forms_that_golangci_lint_also_reads_fail"),
    ("nolint: sin exigir la forma exacta", SKIPS,
     '      if [[ ! "$d" =~ ^//nolint:[a-z0-9_-]+(,[a-z0-9_-]+)*$ ]]; then\n', "      if false; then\n",
     SKIPS_T, "test_nolint_forms_that_golangci_lint_also_reads_fail"),
    ("nolint: all solo si va solo", SKIPS,
     '      elif [[ ",${d#//nolint:}," == *",all,"* ]]; then\n', '      elif [[ "$d" == "//nolint:all" ]]; then\n',
     SKIPS_T, "test_nolint_forms_that_golangci_lint_also_reads_fail"),
    ("nolint: una cita buena no basta", SKIPS,
     '  if [ -z "$problem" ] && ! cites_known_fallo "$text" "$known"; then\n',
     '  if [ -z "$problem" ] && ! cites_known_fallo "$text" ""; then\n',
     SKIPS_T, "test_nolint_citing_a_known_fallo_passes"),
    ("lint: la cabecera de código generado apaga los linters", ".golangci.yml",
     "  exclusions:\n    generated: disable\n", "",
     MAKE_T, "test_lint_runs_golangci_lint_with_the_repo_config"),
    ("lint: otro conjunto de linters", ".golangci.yml",
     "  default: standard\n", "  default: fast\n",
     MAKE_T, "test_golangci_config_is_the_reviewed_one"),
    ("lint: ejecuciones solapadas fallan", "Makefile",
     "run --allow-serial-runners ./...", "run ./...",
     MAKE_T, "test_lint_runs_golangci_lint_with_the_repo_config"),
    ("cli: help acepta argumentos", CLI,
     '\tif len(args) > 0 {\n\t\tsay(stderr, "actaira: %q takes no arguments\\n", "help")\n',
     '\tif false {\n\t\tsay(stderr, "actaira: %q takes no arguments\\n", "help")\n',
     CLI_T, "TestHelpRejectsArguments"),
    ("cli: help da por bueno un fallo al escribir", CLI,
     "\tif _, err := io.WriteString(stdout, usage()); err != nil {\n",
     "\tif _, err := io.WriteString(stdout, usage()); false && err != nil {\n",
     CLI_T, "TestFailingToWriteTheOutputIsAnInternalError"),
    ("repotest: pkg depende de internal", "pkg/model/doc.go",
     "package model\n", 'package model\n\nimport _ "github.com/actaira/actaira/internal/version"\n',
     REPO_T, "TestPkgDoesNotDependOnInternal"),
    ("repotest: los bloques ~~~ no se miran", "internal/repotest/repotest_test.go",
     "|~~~.*?~~~", "",
     REPO_T, "TestCommandsShownFindsEveryFormOfCode"),
    ("repotest: el código en línea que empieza por actaira no se mira", "internal/repotest/repotest_test.go",
     "(?:^|[\\s/>\\x60])actaira", "(?:^|[\\s/>])actaira",
     REPO_T, "TestCommandsShownFindsEveryFormOfCode"),
]


def run_test(copy, test_file, name):
    """A harness shell test (file_test.sh name) or a Go test (go:./pkg name)."""
    env = dict(os.environ)
    env["PATH"] = os.path.expanduser("~/.local/go/bin") + ":" + os.path.expanduser("~/go/bin") + ":" + env["PATH"]
    env["GITLEAKS"] = os.path.join(copy, ".tools", GITLEAKS)
    env.pop("GH_REPO", None)
    env.pop("GOFLAGS", None)
    if test_file.startswith("go:"):
        cmd = ["go", "test", "-count=1", "-v", "-run", f"^{name}$", test_file[3:]]
    else:
        cmd = ["bash", test_file, name]
    p = subprocess.run(cmd, cwd=copy, env=env,
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
    for tool in TOOLS:
        shutil.copy2(os.path.join(REPO, ".tools", tool), os.path.join(copy, ".tools"))
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
    live = subprocess.run(["git", "-C", REPO, "status", "--porcelain", "--", "scripts", ".claude", ".github", "Makefile", "cmd", "internal", "pkg"],
                          stdout=subprocess.PIPE, text=True, check=True).stdout
    print("repo en uso sin cambios" if not live.strip() else "repo en uso CAMBIADO:\n" + live)
    ok = ok and not live.strip()
    print("TODAS OK" if ok else "HAY MUTACIONES MAL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
