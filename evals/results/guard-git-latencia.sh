#!/usr/bin/env bash
# Measures how long guard-git.sh (PreToolUse hook) adds to each shell command.
# Runs the hook N times per case against a throwaway repo on a step branch and
# prints min, median, p90 and max in milliseconds. Never touches this repo.
# Usage: bash evals/results/guard-git-latencia.sh [N]
set -euo pipefail
n="${1:-50}"
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
guard="$repo_dir/scripts/harness/guard-git.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git init -q -b main "$tmp/repo"
git -C "$tmp/repo" -c user.name=x -c user.email=x@example.invalid commit -q --allow-empty -m seed
git -C "$tmp/repo" switch -q -c e0/paso-9-latencia

measure() {
  local label="$1" command="$2" payload i start end ms=()
  payload="$(jq -n --arg c "$command" '{tool_name:"Bash",tool_input:{command:$c}}')"
  for ((i = 0; i < n; i++)); do
    start="$(date +%s%N)"
    CLAUDE_PROJECT_DIR="$tmp/repo" "$guard" <<< "$payload" >/dev/null 2>&1
    end="$(date +%s%N)"
    ms+=("$(( (end - start) / 1000000 ))")
  done
  mapfile -t ms < <(printf '%s\n' "${ms[@]}" | sort -n)
  printf '%-40s n=%d  min=%dms  mediana=%dms  p90=%dms  max=%dms\n' "$label" "$n" \
    "${ms[0]}" "${ms[$((n / 2))]}" "${ms[$((n * 9 / 10))]}" "${ms[$((n - 1))]}"
}

measure "orden sin push (git status)" "git status"
measure "push de una rama de paso (con python3)" "git push -u origin e0/paso-9-latencia"
