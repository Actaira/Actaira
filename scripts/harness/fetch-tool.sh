#!/usr/bin/env bash
# Downloads a pinned tool release archive (.tar.gz), verifies its sha256 and
# installs one member of the archive at <dest>. Nothing is installed if the
# checksum is missing or differs.
# Usage: scripts/harness/fetch-tool.sh <url> <sha256> <member> <dest>
set -euo pipefail
if [ "$#" -ne 4 ]; then
  echo "uso: $0 <url> <sha256> <miembro> <destino>" >&2
  exit 2
fi
url="$1"; want="$2"; member="$3"; dest="$4"
if [ -z "$want" ]; then
  echo "fetch-tool: no hay checksum fijado para $url" >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL --retry 3 --connect-timeout 15 --max-time 300 -o "$tmp/archive" "$url"
if command -v sha256sum >/dev/null 2>&1; then
  got="$(sha256sum "$tmp/archive" | awk '{print $1}')"
else
  got="$(shasum -a 256 "$tmp/archive" | awk '{print $1}')"
fi
if [ "$got" != "$want" ]; then
  echo "fetch-tool: checksum distinto para $url" >&2
  echo "  esperado: $want" >&2
  echo "  obtenido: $got" >&2
  exit 1
fi

tar -xzf "$tmp/archive" -C "$tmp" "$member"
mkdir -p "$(dirname "$dest")"
# Install under a temporary name and rename, so an interrupted run never
# leaves a half-written binary at <dest>.
cp "$tmp/$member" "$dest.partial.$$"
chmod 0755 "$dest.partial.$$"
mv "$dest.partial.$$" "$dest"
