#!/usr/bin/env bash
# Builds a static Linux binary of actaira and checks it (E1 step 1.2b, ADR 0003).
# Usage: scripts/release/build-static.sh <amd64|arm64> <version> <out-dir>
#
# The build runs in golang:<go>-alpine, pinned by the digest of its index, with
# cgo (tree-sitter) against musl and linked statically, so the binary runs on
# any Linux whatever its glibc. Then `file` must say "statically linked" and
# `actaira version` must print the version in Alpine and in Ubuntu 20.04, both
# pinned and without network. The architecture must be the host's: the release
# workflow builds each one on its native runner.
# Exit 0 if every check passes, 1 with the reason if one fails, 2 on usage.
set -euo pipefail

# Images by index digest (verificador-apis, E1 step 1.2b).
GOLANG_IMAGE="golang:1.27.1-alpine@sha256:8a5910f31396cd4d89662f56c68b3ae31d374308270a1c3bd96672ee5ed43414"
ALPINE_IMAGE="alpine:3.24@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6"
UBUNTU_IMAGE="ubuntu:20.04@sha256:8feb4d8ca5354def3d8fce243717141ce31e2c428701f6682bd2fafe15388214"
# The variable that `actaira version` prints.
VERSION_VAR="github.com/actaira/actaira/internal/version.Version"

usage() {
  echo "uso: $0 <amd64|arm64> <versión> <carpeta de salida>" >&2
  exit 2
}
[ "$#" -eq 3 ] || usage
arch="$1" version="$2" out="$3"
case "$arch" in
  amd64 | arm64) ;;
  *) usage ;;
esac
# The version goes into -ldflags and a file name: only plain characters.
if [[ ! "$version" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]]; then
  echo "build-static: versión no válida: $version" >&2
  exit 2
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
bin="actaira-linux-$arch"
platform="linux/$arch"

# The source is mounted read-only. Modules come from the Go proxy (go.sum
# verifies them). The binary is handed back to the host user, not root.
docker run --rm --platform "$platform" \
  -v "$root:/src:ro" -v "$out:/out" -w /src \
  -e CGO_ENABLED=1 -e GOTOOLCHAIN=local -e GOFLAGS=-mod=readonly \
  -e BIN="$bin" -e LDFLAGS="-s -w -X $VERSION_VAR=$version -linkmode external -extldflags -static" \
  -e OWNER="$(id -u):$(id -g)" \
  "$GOLANG_IMAGE" \
  sh -euc 'apk add --no-cache gcc musl-dev > /dev/null && go build -trimpath -buildvcs=false -ldflags "$LDFLAGS" -o "/out/$BIN" ./cmd/actaira && chown "$OWNER" "/out/$BIN"'

info="$(file "$out/$bin")"
case "$info" in
  *"statically linked"*) ;;
  *)
    echo "build-static: $bin no es estático: $info" >&2
    exit 1
    ;;
esac

for image in "$ALPINE_IMAGE" "$UBUNTU_IMAGE"; do
  got=""
  if ! got="$(docker run --rm --network none --platform "$platform" -v "$out:/out:ro" "$image" "/out/$bin" version)"; then
    echo "build-static: $bin version falla en ${image%%@*}" >&2
    exit 1
  fi
  if [ "$got" != "actaira $version" ]; then
    echo "build-static: en ${image%%@*}, $bin version dice [$got], no [actaira $version]" >&2
    exit 1
  fi
done

echo "build-static: $out/$bin, estático; dice \"actaira $version\" en ${ALPINE_IMAGE%%@*} y en ${UBUNTU_IMAGE%%@*}"
