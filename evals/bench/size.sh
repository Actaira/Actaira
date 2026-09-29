#!/usr/bin/env bash
# Measures what tree-sitter adds to the actaira binary (ADR 0003): builds
# ./cmd/actaira from the committed tree twice, with the flags of
# evals/bench/startup.py (go build -trimpath): as it is, and with a blank
# import of pkg/extract/treesitter added to cmd/actaira/main.go, so the parser
# and its three grammars are linked in. Prints JSON with the date, commit,
# environment, command and both sizes. Works on a copy (git archive) in a
# temporary directory: the repository is never touched.
# Usage: bash evals/bench/size.sh > evals/results/<date>-tamano-cli.json
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git -C "$repo" archive HEAD | tar -x -C "$tmp"
cd "$tmp"
go build -trimpath -o "$tmp/plain" ./cmd/actaira
sed -i 's#"github.com/actaira/actaira/internal/cli"#"github.com/actaira/actaira/internal/cli"\n\t_ "github.com/actaira/actaira/pkg/extract/treesitter"#' cmd/actaira/main.go
main="$(cat cmd/actaira/main.go)"
if [[ "$main" != *'_ "github.com/actaira/actaira/pkg/extract/treesitter"'* ]]; then
  echo "size.sh: no se pudo añadir el import a cmd/actaira/main.go" >&2
  exit 1
fi
go build -trimpath -o "$tmp/with" ./cmd/actaira
plain="$(stat -c %s "$tmp/plain")"
with="$(stat -c %s "$tmp/with")"
cc_version="$(cc --version)"
jq -n --arg date "$(date -u +%FT%TZ)" --arg commit "$(git -C "$repo" rev-parse HEAD)" \
  --arg go "$(go version)" --arg os "$(uname -sr)" --arg cc "${cc_version%%$'\n'*}" \
  --argjson plain "$plain" --argjson with "$with" \
  '{date: $date, commit: $commit, environment: {go: $go, os: $os, cc: $cc},
    command: "go build -trimpath ./cmd/actaira, as it is and with a blank import of pkg/extract/treesitter",
    cli_bytes: $plain, cli_with_treesitter_bytes: $with, added_bytes: ($with - $plain)}'
