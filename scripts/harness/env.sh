# Sourced by the hooks (not executed). Claude Code hooks inherit the PATH of
# the process that launched Claude Code (the VS Code server, a desktop app),
# which often lacks toolchains installed in the user's home without sudo.
# Prepend the user-level Go directories when they exist, in the same order as
# ~/.bashrc, so gofmt and `make check` behave as in a terminal (F-0001).
# Must never fail: hooks run with `set -u`, and a PreToolUse hook that
# crashes (exit 1) does not block.
if [ -n "${HOME:-}" ]; then
  for _harness_dir in "$HOME/go/bin" "$HOME/.local/go/bin"; do
    case ":${PATH:-}:" in
      *":$_harness_dir:"*) ;;
      *) if [ -d "$_harness_dir" ]; then PATH="$_harness_dir:${PATH:-}"; fi ;;
    esac
  done
  unset _harness_dir
fi
export PATH
