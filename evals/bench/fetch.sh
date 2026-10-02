#!/usr/bin/env bash
# Fetches the public repositories that evals/bench/parse measures, each pinned
# by commit: a git fetch of that one commit, so git checks every object against
# its hash and the tree is exactly the pinned one (GitHub does not promise a
# stable checksum for the archives it generates). Nothing from those
# repositories is run: a fresh git init has no hooks, and checkout only writes
# files, with git run without the user's global or system configuration, so
# no autocrlf, filter or hook of this machine changes the bytes. They go
# outside this repository, so ./..., the secret scan and the other checks never
# see them. Idempotent: a repository already at its commit, with a clean tree,
# is left alone.
# Usage: evals/bench/fetch.sh [dest]  (default ${XDG_CACHE_HOME:-~/.cache}/actaira-bench)
set -euo pipefail
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
dest="${1:-${XDG_CACHE_HOME:-$HOME/.cache}/actaira-bench}"

# name, language, URL, commit (pinned on 2026-09-29).
repos=(
  "langchain python https://github.com/langchain-ai/langchain aaf25d0abd183a9b5978772c470a0ef11578ce3a"
  "langchainjs typescript https://github.com/langchain-ai/langchainjs 17b6bba8343bdd3f3dfc5c59578e0b72337ec740"
  "vercel-ai tsx https://github.com/vercel/ai 4556206a2d4385eb1be698e365fa1660d6ca98b8"
)

for entry in "${repos[@]}"; do
  read -r name _ url sha <<< "$entry"
  dir="$dest/$name-$sha"
  have=""
  if [ -d "$dir/.git" ]; then
    have="$(git -C "$dir" rev-parse HEAD)"
  fi
  if [ "$have" = "$sha" ] && [ -z "$(git -C "$dir" status --porcelain)" ]; then
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
