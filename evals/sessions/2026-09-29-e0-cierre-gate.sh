#!/usr/bin/env bash
# Epic closing, point 1 of the cierre-epica skill: `make gate` from a clean
# clone of the remote, in a temporary folder with nothing local (no .tools,
# no installed git hooks, no .harness state), run once. The folder is removed
# at the end. Go comes from ~/.local/go, as for the hooks (env.sh).
# Usage: bash evals/sessions/2026-09-29-e0-cierre-gate.sh [url] [ref]
set -euo pipefail
url="${1:-https://github.com/Actaira/Actaira.git}"
ref="${2:-main}"
export PATH="$HOME/.local/go/bin:$HOME/go/bin:$PATH"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git clone -q --branch "$ref" "$url" "$tmp/repo"
cd "$tmp/repo"
echo "clon limpio de $url ($ref) en un directorio temporal: $(git rev-parse HEAD)"
echo "sin nada local: .tools $( [ -e .tools ] && echo existe || echo no existe ), hooks instalados: $(find .git/hooks -type f ! -name '*.sample' | wc -l)"
echo "entorno: $(uname -sr), $(go version), $(git --version), $(jq --version), $(python3 --version)"
echo "comando: make gate"
make gate
echo "comando: make e2e-completo"
make e2e-completo
