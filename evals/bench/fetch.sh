#!/usr/bin/env bash
# Fetches the public repositories that evals/bench/parse measures, each pinned
# by commit: a git fetch of that one commit, so git checks every object against
# its hash and the tree is exactly the pinned one (GitHub does not promise a
# stable checksum for the archives it generates). Nothing from those
# repositories is run: a fresh git init has no hooks, and checkout only writes
# files. They go outside this repository, so ./..., the secret scan and the
# other checks never see them. Idempotent: a repository already at its commit
# is left alone.
# Usage: evals/bench/fetch.sh [dest]  (default ${XDG_CACHE_HOME:-~/.cache}/actaira-bench)
set -euo pipefail
dest="${1:-${XDG_CACHE_HOME:-$HOME/.cache}/actaira-bench}"

# name, language, URL, commit (pinned on 2026-09-29).
repos=(
  "langchain python https://github.com/langchain-ai/langchain aaf25d0abd183a9b5978772c470a0ef11578ce3a"
  "langchainjs typescript https://github.com/langchain-ai/langchainjs 17b6bba8343bdd3f3dfc5c59578e0b72337ec740"
)

for entry in "${repos[@]}"; do
  read -r name _ url sha <<< "$entry"
  dir="$dest/$name-$sha"
  have=""
  if [ -d "$dir/.git" ]; then
    have="$(git -C "$dir" rev-parse HEAD)"
  fi
  if [ "$have" = "$sha" ]; then
    echo "fetch: $name ya está en $sha ($dir)"
    continue
  fi
  rm -rf "$dir"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" fetch -q --depth 1 "$url" "$sha"
  git -C "$dir" -c advice.detachedHead=false checkout -q FETCH_HEAD
  got="$(git -C "$dir" rev-parse HEAD)"
  if [ "$got" != "$sha" ]; then
    echo "fetch: $name está en $got, no en $sha" >&2
    exit 1
  fi
  echo "fetch: $name en $sha ($dir)"
done
