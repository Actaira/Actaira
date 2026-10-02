#!/usr/bin/env bash
# Tests for the release pipeline of E1 step 1.2b: scripts/release/build-static.sh
# and .github/workflows/release.yml. Marcos's decision of 2026-10-02: nothing
# public is signed or tagged yet, so the pull request path signs with an
# ephemeral key and no transparency log, and only a pushed v* tag may write or
# ask for the OIDC token. These tests fix that shape: an accidental change to
# it must turn make check red.
source "$(dirname "$0")/lib.sh"

# Fixed paths: a guard never takes the file it checks from the environment.
BUILD="$REPO_DIR/scripts/release/build-static.sh"
RELEASE="$REPO_DIR/.github/workflows/release.yml"

# job_block <job>: the lines of one job of release.yml, from its id to the next job.
job_block() {
  awk -v job="  $1:" '
    /^jobs:/ { in_jobs = 1; next }
    in_jobs && /^[^ #]/ { in_jobs = 0 }
    in_jobs && /^  [^ #]/ { in_job = ($0 == job) }
    in_jobs && in_job { print }
  ' "$RELEASE"
}

# fake_tools <dir>: a docker, a file and a readelf that only record their
# calls. The fake docker "builds" by creating the binary under the -v
# <dir>:/out mount, and answers `version` with $FAKE_VERSION_OUTPUT; the fake
# file prints $FAKE_FILE_OUTPUT and the fake readelf $FAKE_READELF_OUTPUT.
fake_tools() {
  mkdir -p "$1"
  cat > "$1/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_LOG"
out=""
for a in "$@"; do
  case "$a" in *:/out | *:/out:ro) out="${a%%:/out*}" ;; esac
done
case "$*" in
  *golang:*) : > "$out/$FAKE_BIN" ;;
  *" version") printf '%s\n' "$FAKE_VERSION_OUTPUT" ;;
esac
EOF
  cat > "$1/file" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$FAKE_FILE_OUTPUT"
EOF
  cat > "$1/readelf" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${FAKE_READELF_OUTPUT:-  LOAD           0x000000 0x0000000000400000}"
EOF
  chmod +x "$1/docker" "$1/file" "$1/readelf"
}

# run_build <fake file output> <fake version output>: runs the script for amd64
# version v9.9.9 with the fake tools first in PATH; prints the exit code.
run_build() {
  fake_tools "$T/bin"
  local rc=0
  FAKE_LOG="$T/calls" FAKE_BIN=actaira-linux-amd64 FAKE_FILE_OUTPUT="$1" FAKE_VERSION_OUTPUT="$2" \
    PATH="$T/bin:$PATH" bash "$BUILD" amd64 v9.9.9 "$T/out" > "$T/stdout" 2> "$T/stderr" || rc=$?
  echo "$rc"
}

STATIC="ELF 64-bit LSB executable, x86-64, version 1 (SYSV), statically linked, stripped"

test_build_passes_with_a_static_binary_that_prints_its_version() {
  assert_eq "$(run_build "$STATIC" "actaira v9.9.9")" "0" "exit del script"
  local calls
  calls="$(cat "$T/calls")"
  assert_contains "$calls" "CGO_ENABLED=1" "la compilación con cgo"
  assert_contains "$calls" "-linkmode external -extldflags -static" "el enlazado estático"
  assert_contains "$calls" "--network none" "las pruebas del binario sin red"
  assert_contains "$calls" "alpine:3.24@sha256:" "la prueba en Alpine"
  assert_contains "$calls" "ubuntu:20.04@sha256:" "la prueba en Ubuntu 20.04"
}

test_build_fails_when_the_binary_is_not_static() {
  assert_eq "$(run_build "ELF 64-bit LSB executable, x86-64, dynamically linked, interpreter /lib/ld-musl-x86_64.so.1" "actaira v9.9.9")" "1" "exit del script"
  assert_contains "$(cat "$T/stderr")" "no es estático" "el motivo"
}

# file only looks for PT_DYNAMIC; readelf shows it too, so a static-looking
# binary with a dynamic segment still fails (verificador-apis, step 1.2b).
test_build_fails_when_the_binary_has_a_dynamic_segment() {
  local rc=0
  fake_tools "$T/bin"
  FAKE_LOG="$T/calls" FAKE_BIN=actaira-linux-amd64 FAKE_FILE_OUTPUT="$STATIC" FAKE_VERSION_OUTPUT="actaira v9.9.9" \
    FAKE_READELF_OUTPUT="  DYNAMIC        0x2d7e8 0x000000000062d7e8" \
    PATH="$T/bin:$PATH" bash "$BUILD" amd64 v9.9.9 "$T/out" > "$T/stdout" 2> "$T/stderr" || rc=$?
  assert_eq "$rc" "1" "exit del script"
  assert_contains "$(cat "$T/stderr")" "segmento DYNAMIC" "el motivo"
}

test_build_fails_when_the_binary_prints_another_version() {
  assert_eq "$(run_build "$STATIC" "actaira dev")" "1" "exit del script"
  assert_contains "$(cat "$T/stderr")" "dice [actaira dev]" "el motivo"
}

test_build_rejects_an_unknown_architecture() {
  fake_tools "$T/bin"
  local rc=0
  FAKE_LOG="$T/calls" FAKE_BIN=actaira-linux-riscv64 FAKE_FILE_OUTPUT="$STATIC" FAKE_VERSION_OUTPUT="actaira v9.9.9" \
    PATH="$T/bin:$PATH" bash "$BUILD" riscv64 v9.9.9 "$T/out" 2> "$T/stderr" || rc=$?
  assert_eq "$rc" "2" "exit del script"
  assert_contains "$(cat "$T/stderr")" "uso:" "el motivo"
  [ ! -e "$T/calls" ] || fail "con una arquitectura desconocida no se llama a docker"
}

# Every image the script runs is pinned by the digest of its index.
test_build_images_are_pinned_by_digest() {
  [ -f "$BUILD" ] || fail "no existe $BUILD"
  local images bad
  images="$(grep -E '^[A-Z]+_IMAGE=' "$BUILD")" || fail "el script no declara sus imágenes"
  assert_eq "$(wc -l <<< "$images" | tr -d ' ')" "3" "imágenes declaradas (golang, alpine y ubuntu)"
  bad="$(grep -vE '^[A-Z]+_IMAGE="[a-z0-9.-]+:[A-Za-z0-9._-]+@sha256:[0-9a-f]{64}"$' <<< "$images")" || bad=""
  assert_eq "$bad" "" "imágenes sin fijar por digest"
}

# The -X path of the script is the variable that `actaira version` prints: a
# binary built with it says the version it was given.
test_version_ldflag_of_the_script_sets_the_version() {
  [ -f "$BUILD" ] || fail "no existe $BUILD"
  local var out
  var="$(sed -n 's/^VERSION_VAR="\(.*\)"$/\1/p' "$BUILD")"
  [ -n "$var" ] || fail "el script no declara VERSION_VAR"
  # GOTOOLCHAIN=local: the test never downloads a Go toolchain.
  (cd "$REPO_DIR" && GOTOOLCHAIN=local go build -o "$T/actaira" -ldflags "-X $var=v9.9.9-test" ./cmd/actaira)
  out="$("$T/actaira" version)"
  assert_eq "$out" "actaira v9.9.9-test" "salida de actaira version"
}

test_release_has_exactly_the_three_release_jobs() {
  [ -f "$RELEASE" ] || fail "no existe $RELEASE"
  local jobs
  jobs="$(awk '/^jobs:/ {in_jobs = 1; next} /^[^ #]/ {in_jobs = 0} in_jobs && /^  [^ #]/' "$RELEASE")"
  assert_eq "$jobs" "$(printf '  release-build:\n  release-dry-run:\n  release-publish:')" "jobs de release.yml"
}

# Write permissions and the OIDC token exist only in release-publish, and the
# workflow default is read-only.
test_only_the_publish_job_can_write_or_ask_for_oidc() {
  [ -f "$RELEASE" ] || fail "no existe $RELEASE"
  local top job writes
  top="$(awk '/^jobs:/ {exit} {print}' "$RELEASE")"
  assert_contains "$top" "$(printf 'permissions:\n  contents: read')" "permisos por defecto del workflow"
  assert_not_contains "$top" "write" "permisos por defecto del workflow"
  for job in release-build release-dry-run; do
    writes="$(job_block "$job" | grep -E '(:|-)[[:space:]]*write|id-token')" || writes=""
    assert_eq "$writes" "" "permisos de escritura u OIDC en $job"
  done
  assert_contains "$(job_block release-publish)" "id-token: write" "OIDC en release-publish"
  assert_contains "$(job_block release-publish)" "contents: write" "escritura en release-publish"
}

# release-publish runs only for a pushed v* tag; no push to a branch runs it.
test_publish_runs_only_on_a_version_tag() {
  [ -f "$RELEASE" ] || fail "no existe $RELEASE"
  local on
  on="$(awk '/^on:/ {p = 1; next} /^[^ #]/ {p = 0} p' "$RELEASE")"
  assert_contains "$on" "$(printf '  push:\n    tags:\n      - "v*"')" "disparo por etiqueta"
  assert_not_contains "$on" "branches" "un push a una rama no debe disparar la release"
  assert_contains "$(job_block release-publish)" "if: github.event_name == 'push' && startsWith(github.ref, 'refs/tags/v')" "condición de release-publish"
  assert_contains "$(job_block release-dry-run)" "if: github.event_name != 'push'" "condición de release-dry-run"
}

# The dry run signs with an ephemeral key and no transparency log, verifies, and
# checks that a changed byte fails verification.
test_dry_run_signs_with_an_ephemeral_key_and_no_transparency_log() {
  [ -f "$RELEASE" ] || fail "no existe $RELEASE"
  local block
  block="$(job_block release-dry-run)"
  assert_contains "$block" "generate-key-pair" "clave efímera"
  assert_contains "$block" "--use-signing-config=false --tlog-upload=false" "firma sin configuración de firma ni Rekor (cosign v3.1.3)"
  local calls offline
  calls="$(grep -F '"$cosign_bin" ' <<< "$block")" || fail "release-dry-run no llama a cosign por \$cosign_bin"
  offline="$(grep -vF 'sudo unshare -n ' <<< "$calls")" || offline=""
  assert_eq "$offline" "" "llamadas a cosign fuera de un espacio de red sin red"
  local direct
  direct="$(grep -E '(^[[:space:]]+|\$\(|; )cosign [a-z]' <<< "$block")" || direct=""
  assert_eq "$direct" "" "llamadas directas a cosign, sin unshare"
  assert_contains "$block" "--key cosign.key" "firma con la clave efímera"
  assert_contains "$block" "--key cosign.pub" "verificación con la clave efímera"
  assert_contains "$block" "$(printf "cp checksums.txt tampered.txt\n          printf 'x' >> tampered.txt")" "copia con un byte cambiado"
  assert_contains "$block" "verify-blob --key cosign.pub --insecure-ignore-tlog=true --bundle checksums.txt.sigstore.json tampered.txt" "verificación de la copia cambiada"
  assert_contains "$block" "could not verify message" "el motivo del fallo con un byte cambiado"
  assert_not_contains "$block" "certificate-identity" "la prueba no usa identidad de Fulcio"
}

# Verification of the real release uses the exact workflow identity, with the
# repository's capitals (cosign compares it as a string), never a regexp.
test_publish_verifies_the_exact_workflow_identity() {
  [ -f "$RELEASE" ] || fail "no existe $RELEASE"
  local block
  block="$(job_block release-publish)"
  assert_contains "$block" '--certificate-identity "https://github.com/Actaira/Actaira/.github/workflows/release.yml@refs/tags/${VERSION}"' "identidad exacta"
  assert_contains "$block" "--certificate-oidc-issuer https://token.actions.githubusercontent.com" "emisor OIDC"
  assert_not_contains "$(cat "$RELEASE")" "regexp" "identidad por expresión regular"
}

# A tag that is not on main never becomes a release, and the release is
# published only after its assets are up (immutable releases).
test_publish_checks_main_and_publishes_a_draft_last() {
  [ -f "$RELEASE" ] || fail "no existe $RELEASE"
  local block
  block="$(job_block release-publish)"
  assert_contains "$block" "git merge-base --is-ancestor" "la etiqueta está en main"
  assert_contains "$block" "gh release create" "creación de la release"
  assert_contains "$block" "--draft --verify-tag" "borrador sobre una etiqueta que ya existe"
  assert_contains "$block" "gh release edit" "publicación al final"
  assert_contains "$block" "--draft=false" "publicación al final"
}

# The whole workflow, compared exactly (L-006), as ci_test.sh does with ci.yml:
# round 1 of step 1.2b found changes the shape tests let through (release-build
# without the script, arm64 on an amd64 runner, a dryrun version on a tag,
# publish on workflow_dispatch, signing before the main check, a dry run that
# never verifies the good signature). A deliberate change updates this test in
# the same PR, where the diff shows it.
test_release_workflow_is_exactly_the_reviewed_one() {
  [ -f "$RELEASE" ] || fail "no existe $RELEASE"
  local expected
  expected="$(cat <<'EOF'
name: release
on:
  pull_request:
  workflow_dispatch:
  push:
    tags:
      - "v*"
permissions:
  contents: read
jobs:
  release-build:
    strategy:
      matrix:
        include:
          - arch: amd64
            runner: ubuntu-24.04
          - arch: arm64
            runner: ubuntu-24.04-arm
    runs-on: ${{ matrix.runner }}
    timeout-minutes: 30
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - name: Build and check the static binary
        env:
          ARCH: ${{ matrix.arch }}
          REF_TYPE: ${{ github.ref_type }}
          REF_NAME: ${{ github.ref_name }}
          SHA: ${{ github.sha }}
        run: |
          if [ "$REF_TYPE" = tag ]; then version="$REF_NAME"; else version="dryrun-${SHA:0:12}"; fi
          scripts/release/build-static.sh "$ARCH" "$version" dist
      - uses: actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a # v7.0.1
        with:
          name: actaira-linux-${{ matrix.arch }}
          path: dist/actaira-linux-${{ matrix.arch }}
          if-no-files-found: error
  release-dry-run:
    if: github.event_name != 'push'
    needs: release-build
    runs-on: ubuntu-24.04
    timeout-minutes: 15
    permissions:
      contents: read
    steps:
      - uses: actions/download-artifact@3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c # v8.0.1
        with:
          path: dist
          merge-multiple: true
      - uses: sigstore/cosign-installer@6f9f17788090df1f26f669e9d70d6ae9567deba6 # v4.1.2
        with:
          cosign-release: "v3.1.3"
      - name: Sign and verify with an ephemeral key, without network
        working-directory: dist
        run: |
          sha256sum actaira-linux-amd64 actaira-linux-arm64 > checksums.txt
          cosign_bin="$(command -v cosign)"
          sudo unshare -n env COSIGN_PASSWORD= "$cosign_bin" generate-key-pair
          sudo unshare -n env COSIGN_PASSWORD= "$cosign_bin" sign-blob --yes --key cosign.key --use-signing-config=false --tlog-upload=false --bundle checksums.txt.sigstore.json checksums.txt
          sudo unshare -n "$cosign_bin" verify-blob --key cosign.pub --insecure-ignore-tlog=true --bundle checksums.txt.sigstore.json checksums.txt
          sha256sum -c checksums.txt
          cp checksums.txt tampered.txt
          printf 'x' >> tampered.txt
          rc=0
          out="$(sudo unshare -n "$cosign_bin" verify-blob --key cosign.pub --insecure-ignore-tlog=true --bundle checksums.txt.sigstore.json tampered.txt 2>&1)" || rc=$?
          printf '%s\n' "$out"
          if [ "$rc" -eq 0 ]; then
            echo "release-dry-run: the signature verifies a changed file" >&2
            exit 1
          fi
          case "$out" in
            *"could not verify message"*) ;;
            *)
              echo "release-dry-run: verification of a changed file failed for another reason" >&2
              exit 1
              ;;
          esac
  release-publish:
    if: github.event_name == 'push' && startsWith(github.ref, 'refs/tags/v')
    needs: release-build
    runs-on: ubuntu-24.04
    timeout-minutes: 15
    permissions:
      contents: write
      id-token: write
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          fetch-depth: 0
          persist-credentials: false
      - name: The tag must be on main
        run: git merge-base --is-ancestor "$GITHUB_SHA" origin/main
      - uses: actions/download-artifact@3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c # v8.0.1
        with:
          path: dist
          merge-multiple: true
      - uses: sigstore/cosign-installer@6f9f17788090df1f26f669e9d70d6ae9567deba6 # v4.1.2
        with:
          cosign-release: "v3.1.3"
      - name: Sign checksums.txt with the identity of this workflow and verify it
        working-directory: dist
        env:
          VERSION: ${{ github.ref_name }}
        run: |
          sha256sum actaira-linux-amd64 actaira-linux-arm64 > checksums.txt
          cosign sign-blob --yes --bundle checksums.txt.sigstore.json checksums.txt
          cosign verify-blob --bundle checksums.txt.sigstore.json --certificate-identity "https://github.com/Actaira/Actaira/.github/workflows/release.yml@refs/tags/${VERSION}" --certificate-oidc-issuer https://token.actions.githubusercontent.com checksums.txt
      - name: Publish the release, as a draft until its assets are up
        working-directory: dist
        env:
          GH_TOKEN: ${{ github.token }}
          REPO: ${{ github.repository }}
          VERSION: ${{ github.ref_name }}
        run: |
          gh release create "$VERSION" --repo "$REPO" --draft --verify-tag --title "$VERSION" --notes "Static Linux binaries of actaira $VERSION. Verify checksums.txt with cosign (docs/epicas/E1.md, step 1.2), then sha256sum -c checksums.txt."
          gh release upload "$VERSION" --repo "$REPO" actaira-linux-amd64 actaira-linux-arm64 checksums.txt checksums.txt.sigstore.json
          gh release edit "$VERSION" --repo "$REPO" --draft=false
EOF
)"
  assert_eq "$(grep -vE '^[[:space:]]*(#|$)' "$RELEASE")" "$expected" \
    "release.yml no es el revisado: un cambio en lo que compila, firma o publica tiene que verse en este test"
}

# The image builds with the Go of go.mod: with GOTOOLCHAIN=local, a go line
# newer than the image fails the release build, and check (setup-go with
# go-version-file) would not see it (round 1 of step 1.2b).
test_golang_image_is_the_go_of_go_mod() {
  [ -f "$BUILD" ] || fail "no existe $BUILD"
  local want toolchain image
  want="$(sed -n 's/^go \([0-9.]*\)$/\1/p' "$REPO_DIR/go.mod")"
  [ -n "$want" ] || fail "go.mod sin línea go"
  toolchain="$(sed -n 's/^toolchain go\([0-9.]*\)$/\1/p' "$REPO_DIR/go.mod")"
  if [ -n "$toolchain" ]; then want="$toolchain"; fi
  image="$(sed -n 's/^GOLANG_IMAGE="golang:\([0-9.]*\)-alpine@.*$/\1/p' "$BUILD")"
  assert_eq "$image" "$want" "versión de Go de GOLANG_IMAGE frente a go.mod"
}

run_tests "$@"
