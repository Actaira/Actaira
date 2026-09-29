#!/usr/bin/env python3
"""Mutation proofs of E1 step 1.2a (e1/paso-2a-parser).

The tree-sitter wrapper (pkg/extract/treesitter) and the rule that every
workflow but release.yml is read-only. Same method as the other proofs: on a
copy of a committed tree (git archive) in a temporary directory, never in the
live repo (F-0008). For each guard: break it in the copy, run its test (it
must be red, for that reason), restore the file byte for byte and run the test
again (it must be green). Exits 1 if any mutation is not proven. A test named
go:<package> runs with go test -v -run '^Name$'.
Usage: python3 evals/sessions/2026-09-29-e1-paso-2a-mutate.py [commit]; the
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
TS = "pkg/extract/treesitter/treesitter.go"
TS_T = "go:./pkg/extract/treesitter"
CI_T = "scripts/harness/tests/ci_test.sh"

# (title, file, fragment, replacement, test file, test name)
MUTATIONS = [
    ("treesitter: Close no libera el árbol", TS,
     "\t\tt.t.Close()\n\t\tt.t = nil\n", "\t\tt.t = nil\n",
     TS_T, "TestParsingAThousandFilesDoesNotLeak"),
    ("treesitter: un segundo Close libera otra vez", TS,
     "\tif t.t != nil {\n\t\tt.t.Close()\n\t\tt.t = nil\n\t}\n", "\tt.t.Close()\n",
     TS_T, "TestCloseTwiceIsSafe"),
    ("treesitter: TSX con la gramática de TypeScript", TS,
     "\t\treturn sitter.NewLanguage(typescript.LanguageTSX()), nil\n", "\t\treturn sitter.NewLanguage(typescript.LanguageTypescript()), nil\n",
     TS_T, "TestParsesEachLanguage"),
    ("treesitter: TypeScript con la gramática de TSX", TS,
     "\t\treturn sitter.NewLanguage(typescript.LanguageTypescript()), nil\n", "\t\treturn sitter.NewLanguage(typescript.LanguageTSX()), nil\n",
     TS_T, "TestTSXIsNotTypeScript"),
    ("treesitter: un lenguaje desconocido cae en Python", TS,
     '\treturn nil, fmt.Errorf("treesitter: unknown language %v", l)\n', "\treturn sitter.NewLanguage(python.Language()), nil\n",
     TS_T, "TestUnknownLanguageIsAnError"),
    ("treesitter: HasError siempre falso", TS,
     "\treturn t.t.RootNode().HasError()\n", "\treturn false\n",
     TS_T, "TestBrokenSyntaxIsATreeWithErrors"),
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
        # A Go test can also be red by killing the process (a double free
        # aborts with SIGABRT): then its "=== RUN" is the last one printed.
        runs = re.findall(r"^=== RUN   (\S+)", out_mut, re.M)
        if test_file.startswith("go:") and rc_mut != 0 and runs and runs[-1] == name and "SIGABRT" in out_mut:
            red = True
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
