# Minimal test framework for the harness scripts (sourced, not executed).
# A test file defines functions named test_*, sources this file and ends with
# `run_tests "$@"`. With no arguments every test runs; with names, only those.
# Each test runs in a subshell with `set -e`, inside its own `mktemp -d`
# directory ($T), and never touches the repo. Output per test:
#   --- PASS: test_name   or   --- FAIL: test_name
set -uo pipefail

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "$HARNESS_DIR/../.." && pwd)"
export HARNESS_DIR REPO_DIR

fail() {
  echo "    $*" >&2
  return 1
}

assert_eq() { # actual expected [message]
  [ "$1" = "$2" ] || fail "${3:-valor}: esperado [$2], obtenido [$1]"
}

assert_contains() { # haystack needle [message]
  case "$1" in
    *"$2"*) return 0 ;;
  esac
  fail "${3:-salida}: no contiene [$2]; salida: [$1]"
}

assert_not_contains() { # haystack needle [message]
  case "$1" in
    *"$2"*) fail "${3:-salida}: contiene [$2]; salida: [$1]" ;;
  esac
  return 0
}

# init_repo <dir>: a throwaway git repo with one commit on branch main.
init_repo() {
  git init -q -b main "$1"
  git -C "$1" config user.email "harness-test@example.invalid"
  git -C "$1" config user.name "harness test"
  git -C "$1" config commit.gpgsign false
  printf 'seed\n' > "$1/README.md"
  git -C "$1" add README.md
  git -C "$1" commit -q -m seed
}

# bare_path <dir>: prints a PATH made only of symlinks to the system tools the
# hooks use, never go or gofmt: the kind of PATH Claude Code hooks inherit
# (F-0001). Independent of where this machine or the CI keeps its tools.
bare_path() {
  local t p
  mkdir -p "$1"
  for t in bash sh env cat jq git make grep sed awk sort uniq cut tr head tail wc \
    mkdir rm mv cp touch timeout sha256sum dirname basename mktemp tar date; do
    p="$(command -v "$t")" || continue
    ln -sf "$p" "$1/$t"
  done
  echo "$1"
}

run_tests() {
  local names=("$@") failed=0 t tmp rc
  if [ "${#names[@]}" -eq 0 ]; then
    mapfile -t names < <(declare -F | awk '$3 ~ /^test_/ {print $3}')
  fi
  if [ "${#names[@]}" -eq 0 ]; then
    echo "--- FAIL: no hay tests en $0"
    return 1
  fi
  for t in "${names[@]}"; do
    # Only test_* functions are tests: a helper must never count as a passing guard.
    if [[ ! "$t" =~ ^test_[A-Za-z0-9_]+$ ]]; then
      echo "--- FAIL: $t (no es un test: los tests se llaman test_*)"
      failed=1
      continue
    fi
    if ! declare -F "$t" >/dev/null; then
      echo "--- FAIL: $t (no existe)"
      failed=1
      continue
    fi
    tmp="$(mktemp -d)"
    # Not inside `if`: set -e would be ignored in a condition context.
    (
      set -e
      export T="$tmp"
      cd "$tmp"
      "$t"
    )
    rc=$?
    rm -rf "$tmp"
    if [ "$rc" -eq 0 ]; then
      echo "--- PASS: $t"
    else
      echo "--- FAIL: $t"
      failed=1
    fi
  done
  return "$failed"
}
