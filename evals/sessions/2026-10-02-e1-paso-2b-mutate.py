#!/usr/bin/env python3
"""Mutation proofs of E1 step 1.2b (e1/paso-2b-distribucion).

The static build script (scripts/release/build-static.sh) and the shape of the
release workflow (.github/workflows/release.yml). Same method as the other
proofs: on a copy of a committed tree (git archive) in a temporary directory,
never in the live repo (F-0008). For each guard: break it in the copy, run its
test (it must be red, for that reason), restore the file byte for byte and run
the test again (it must be green). Exits 1 if any mutation is not proven.
Usage: python3 evals/sessions/2026-10-02-e1-paso-2b-mutate.py [commit]; the
commit defaults to HEAD, and the output records which one was copied.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BUILD = "scripts/release/build-static.sh"
REL = ".github/workflows/release.yml"
T = "scripts/harness/tests/release_test.sh"

# (title, file, fragment, replacement, test name)
MUTATIONS = [
    ("build: no comprueba que el binario sea estático", BUILD,
     '  *"statically linked"*) ;;\n', '  *) ;;\n',
     "test_build_fails_when_the_binary_is_not_static"),
    ("build: no comprueba la versión que dice el binario", BUILD,
     '  if [ "$got" != "actaira $version" ]; then\n', "  if false; then\n",
     "test_build_fails_when_the_binary_prints_another_version"),
    ("build: acepta cualquier arquitectura", BUILD,
     "  amd64 | arm64) ;;\n  *) usage ;;\n", "  *) ;;\n",
     "test_build_rejects_an_unknown_architecture"),
    ("build: prueba el binario con red", BUILD,
     'docker run --rm --network none --platform', 'docker run --rm --platform',
     "test_build_passes_with_a_static_binary_that_prints_its_version"),
    ("build: enlaza en dinámico", BUILD,
     " -linkmode external -extldflags -static", "",
     "test_build_passes_with_a_static_binary_that_prints_its_version"),
    ("build: Alpine sin fijar por digest", BUILD,
     'ALPINE_IMAGE="alpine:3.24@sha256:', 'ALPINE_IMAGE="alpine:3.24" # ',
     "test_build_images_are_pinned_by_digest"),
    ("build: la versión va a otra variable", BUILD,
     'VERSION_VAR="github.com/actaira/actaira/internal/version.Version"', 'VERSION_VAR="github.com/actaira/actaira/internal/cli.Version"',
     "test_version_ldflag_of_the_script_sets_the_version"),
    ("release: un cuarto job", REL,
     "  release-publish:\n", "  release-extra:\n    runs-on: ubuntu-24.04\n    steps:\n      - run: true\n\n  release-publish:\n",
     "test_release_has_exactly_the_three_release_jobs"),
    ("release: release-build con escritura", REL,
     "    timeout-minutes: 30\n    permissions:\n      contents: read\n", "    timeout-minutes: 30\n    permissions:\n      contents: write\n",
     "test_only_the_publish_job_can_write_or_ask_for_oidc"),
    ("release: release-dry-run con token OIDC", REL,
     "    timeout-minutes: 15\n    permissions:\n      contents: read\n", "    timeout-minutes: 15\n    permissions:\n      contents: read\n      id-token: write\n",
     "test_only_the_publish_job_can_write_or_ask_for_oidc"),
    ("release: un push a main dispara la release", REL,
     '  push:\n    tags:\n      - "v*"\n', '  push:\n    branches: [main]\n    tags:\n      - "v*"\n',
     "test_publish_runs_only_on_a_version_tag"),
    ("release: release-publish sin condición de etiqueta", REL,
     "    if: github.event_name == 'push' && startsWith(github.ref, 'refs/tags/v')\n", "",
     "test_publish_runs_only_on_a_version_tag"),
    ("release: la prueba sube a Rekor", REL,
     " --tlog-upload=false --bundle", " --bundle",
     "test_dry_run_signs_with_an_ephemeral_key_and_no_transparency_log"),
    ("release: la prueba no comprueba un byte cambiado", REL,
     "          cp checksums.txt tampered.txt\n          printf 'x' >> tampered.txt\n", "",
     "test_dry_run_signs_with_an_ephemeral_key_and_no_transparency_log"),
    ("release: la prueba no mira por qué falla el byte cambiado", REL,
     '            *"could not verify message"*) ;;\n', "",
     "test_dry_run_signs_with_an_ephemeral_key_and_no_transparency_log"),
    ("release: la prueba firma con la configuración de firma de TUF", REL,
     "--key cosign.key --use-signing-config=false", "--key cosign.key",
     "test_dry_run_signs_with_an_ephemeral_key_and_no_transparency_log"),
    ("release: la prueba firma con red", REL,
     'sudo unshare -n env COSIGN_PASSWORD= "$cosign_bin" sign-blob', 'env COSIGN_PASSWORD= "$cosign_bin" sign-blob',
     "test_dry_run_signs_with_an_ephemeral_key_and_no_transparency_log"),
    # Round 1 of the review: changes the shape tests let through.
    ("release: release-build sin el script (M1 de la ronda 1)", REL,
     'scripts/release/build-static.sh "$ARCH" "$version" dist', 'mkdir -p dist && go build -o "dist/actaira-linux-$ARCH" ./cmd/actaira',
     "test_release_workflow_is_exactly_the_reviewed_one"),
    ("release: arm64 en un runner amd64 (M2)", REL,
     "            runner: ubuntu-24.04-arm\n", "            runner: ubuntu-24.04\n",
     "test_release_workflow_is_exactly_the_reviewed_one"),
    ("release: una etiqueta con versión dryrun (M3)", REL,
     'then version="$REF_NAME"', 'then version="dryrun-${SHA:0:12}"',
     "test_release_workflow_is_exactly_the_reviewed_one"),
    ("release: publica también con workflow_dispatch (M4)", REL,
     "startsWith(github.ref, 'refs/tags/v')\n", "startsWith(github.ref, 'refs/tags/v') || github.event_name == 'workflow_dispatch'\n",
     "test_release_workflow_is_exactly_the_reviewed_one"),
    ("release: la prueba no verifica la firma buena (M5)", REL,
     '          sudo unshare -n "$cosign_bin" verify-blob --key cosign.pub --insecure-ignore-tlog=true --bundle checksums.txt.sigstore.json checksums.txt\n', "",
     "test_release_workflow_is_exactly_the_reviewed_one"),
    ("go.mod pide un Go más nuevo que la imagen", "go.mod",
     "\ngo 1.27.1\n", "\ngo 1.27.2\n",
     "test_golang_image_is_the_go_of_go_mod"),
    ("build: no mira el segmento DYNAMIC", BUILD,
     "if grep -q 'DYNAMIC' <<< \"$headers\"; then\n", "if false; then\n",
     "test_build_fails_when_the_binary_has_a_dynamic_segment"),
    ("release: la identidad en minúsculas", REL,
     "https://github.com/Actaira/Actaira/.github", "https://github.com/actaira/actaira/.github",
     "test_publish_verifies_the_exact_workflow_identity"),
    ("release: no comprueba que la etiqueta esté en main", REL,
     '        run: git merge-base --is-ancestor "$GITHUB_SHA" origin/main\n', "        run: true\n",
     "test_publish_checks_main_and_publishes_a_draft_last"),
    ("release: publica sin pasar por borrador", REL,
     " --draft --verify-tag", " --verify-tag",
     "test_publish_checks_main_and_publishes_a_draft_last"),
]


def run_test(copy, name):
    env = dict(os.environ)
    env["PATH"] = os.path.expanduser("~/.local/go/bin") + ":" + os.path.expanduser("~/go/bin") + ":" + env["PATH"]
    env.pop("GOFLAGS", None)
    p = subprocess.run(["bash", T, name], cwd=copy, env=env,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=300)
    return p.returncode, p.stdout


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
    for title, path, old, new, name in MUTATIONS:
        full = os.path.join(copy, path)
        original = open(full, encoding="utf-8").read()
        if original.count(old) != 1:
            print(f"### {title}\nNO APLICABLE: el fragmento aparece {original.count(old)} veces en {path}\nresultado: MAL\n")
            ok = False
            continue
        with open(full, "w", encoding="utf-8") as fh:
            fh.write(original.replace(old, new))
        rc_mut, out_mut = run_test(copy, name)
        with open(full, "w", encoding="utf-8") as fh:
            fh.write(original)
        restored = open(full, encoding="utf-8").read() == original
        rc_ok, out_ok = run_test(copy, name)
        red = rc_mut != 0 and f"--- FAIL: {name}" in out_mut
        green = rc_ok == 0 and f"--- PASS: {name}" in out_ok
        ok = ok and red and green and restored
        print(f"### {title}")
        print(f"fichero: {path}; test: {T}::{name}")
        print(f"con la mutacion (debe ser rojo): exit {rc_mut}")
        print("\n".join(l for l in out_mut.splitlines() if l.strip())[-800:])
        print(f"restaurado byte a byte: {restored}")
        print(f"con la correccion (debe ser verde): exit {rc_ok}: {out_ok.strip().splitlines()[-1]}")
        print(f"resultado: {'OK' if red and green and restored else 'MAL'}\n")
    shutil.rmtree(work)
    live = subprocess.run(["git", "-C", REPO, "status", "--porcelain", "--", "scripts", ".github"],
                          stdout=subprocess.PIPE, text=True, check=True).stdout
    print("repo en uso sin cambios" if not live.strip() else "repo en uso CAMBIADO:\n" + live)
    ok = ok and not live.strip()
    print("TODAS OK" if ok else "HAY MUTACIONES MAL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
