#!/usr/bin/env bash
# Formats the file Claude Code just edited. PostToolUse cannot block, so problems
# are reported back to Claude as additionalContext (JSON on stdout, exit 0).
set -u
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
root="${CLAUDE_PROJECT_DIR:-$PWD}"
input="$(cat)"
file="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')"
[ -z "$file" ] && exit 0
[ -f "$file" ] || exit 0

report() {
  jq -n --arg m "$1" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$m}}'
  exit 0
}

case "$file" in
  *.go)
    if ! command -v gofmt >/dev/null 2>&1; then
      report "gofmt not found (not in PATH nor in ~/.local/go/bin): $file was NOT formatted"
    fi
    if ! out="$(gofmt -l -w "$file" 2>&1)"; then
      report "gofmt failed on $file: $out"
    fi
    ;;
  *.ts|*.tsx|*.js|*.jsx|*.json|*.css)
    if [ -x "$root/node_modules/.bin/prettier" ]; then
      if ! out="$("$root/node_modules/.bin/prettier" --write "$file" 2>&1)"; then
        report "prettier failed on $file: $out"
      fi
    fi
    ;;
  *.py)
    if command -v ruff >/dev/null 2>&1; then
      if ! out="$(ruff format "$file" 2>&1)"; then
        report "ruff format failed on $file: $out"
      fi
    fi
    ;;
esac
exit 0
