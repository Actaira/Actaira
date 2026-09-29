#!/usr/bin/env bash
# Stop gate: Claude Code cannot finish a turn while the fast gate is red.
# - Skips repos without a `check` target (harness not fully installed yet).
# - Skips when paused on purpose for Marcos (.harness/pausa-marcos).
# - Caches green results per exact tree state, so repeated stops are cheap.
# - Also runs when the tree is clean but there are commits not yet on origin/main.
# - Anti-loop: on the 3rd consecutive red it sends the escalation message;
#   the next stop attempt is allowed. The escalation flag is cleared on any green.
set -u
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
input="$(cat)"
session="$(printf '%s' "$input" | jq -r '.session_id // "nosession"')"
root="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$root" || exit 0

[ -f Makefile ] && grep -q '^check:' Makefile || exit 0

state_dir="$root/.harness"
mkdir -p "$state_dir"
grep -qxF '.harness/' .git/info/exclude 2>/dev/null || echo '.harness/' >> .git/info/exclude
counter_file="$state_dir/stop-blocks-$session"
escalated_file="$state_dir/stop-escalated-$session"
pause_file="$state_dir/pausa-marcos"

clear_state() { rm -f "$counter_file" "$escalated_file"; }
# tell_marcos <text>: when the hook lets Claude stop (exit 0), only a JSON
# systemMessage on stdout reaches the user; stderr goes to the debug log only
# (https://code.claude.com/docs/en/hooks, "Exit code 0").
tell_marcos() { jq -n --arg m "$1" '{systemMessage: $m}'; }

if [ -s "$pause_file" ]; then
  tell_marcos "Pausa para Marcos: $(cat "$pause_file")"
  rm -f "$pause_file"
  clear_state
  exit 0
fi

unpushed="$(git rev-list --count origin/main..HEAD 2>/dev/null || echo 1)"
if [ -z "$(git status --porcelain)" ] && [ "$unpushed" = "0" ]; then
  clear_state
  exit 0
fi

# Cache key: HEAD plus the tree of a throwaway index holding every tracked and
# untracked (not ignored) file, i.e. the exact content git would commit.
# Names alone are not enough: an untracked file can change after a green (F-0004).
tree_key() {
  local idx_dir tree
  idx_dir="$(mktemp -d)"
  if [ -f "$(git rev-parse --git-path index)" ]; then
    # -p keeps the mtime, so git still detects "racily clean" entries.
    cp -p "$(git rev-parse --git-path index)" "$idx_dir/index"
  fi
  if GIT_INDEX_FILE="$idx_dir/index" git add -A >/dev/null 2>&1; then
    tree="$(GIT_INDEX_FILE="$idx_dir/index" git write-tree 2>/dev/null)"
  fi
  rm -rf "$idx_dir"
  printf '%s' "${tree:-}"
}
tree="$(tree_key)"
key="$(git rev-parse HEAD 2>/dev/null)-$tree"
if [ -n "$tree" ] && [ -f "$state_dir/ok-$key" ]; then
  clear_state
  exit 0
fi

if out="$(timeout 540 make check 2>&1)"; then
  if [ -n "$tree" ]; then touch "$state_dir/ok-$key"; fi
  clear_state
  exit 0
fi

if [ -f "$escalated_file" ]; then
  # Claude already got the escalation message: let it stop now, and say so.
  clear_state
  tell_marcos "make check sigue en rojo: Claude para tras 3 intentos; el diagnóstico debe quedar en docs/estado."
  exit 0
fi

blocks=0
[ -f "$counter_file" ] && blocks="$(cat "$counter_file")"
blocks=$((blocks + 1))
echo "$blocks" > "$counter_file"

if [ "$blocks" -ge 3 ]; then
  touch "$escalated_file"
  {
    echo "STOP GATE: make check sigue en rojo tras 3 intentos."
    echo "No sigas probando a ciegas: registra el fallo con la skill registrar-fallo,"
    echo "deja el diagnostico en docs/estado y devuelve el control a Marcos."
    echo "Tu proximo intento de terminar se permitira."
  } >&2
  exit 2
fi

{
  echo "STOP GATE ($blocks/3): make check falla (o supera 540 s). Corrige antes de terminar."
  echo "Ultimas lineas de la salida:"
  printf '%s\n' "$out" | tail -n 60
} >&2
exit 2
