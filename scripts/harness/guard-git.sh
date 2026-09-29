#!/usr/bin/env bash
# PreToolUse guard for shell commands (Bash, Monitor, PowerShell): blocks the
# git operations that could move main or switch the git hooks off, which
# permission rules cannot catch reliably. Blocked (exit 2; the reason goes to Claude):
#   - a push with --force*, --no-verify, --all, --branches, --mirror (or their
#     abbreviations), a short option cluster with f, a + refspec, the matching
#     refspec ":", a wildcard refspec, or any destination main;
#   - any push while the project, the directory Claude works in (input field
#     cwd), the hook's directory or the repo the push acts on (after cd, pushd
#     or git -C) is on main, except the epic closing tag:
#     `git push <remote> e<N>-cerrada`;
#   - git send-pack, which skips the pre-push hook, and the dashed git-push;
#   - a push decided at run time: shell expansions ($, backticks, braces) in
#     its words, git behind a variable, a function, a shell alias or xargs;
#   - git configuration that turns a command into a push or disables the git
#     hooks: alias.*, push.*, remote.*, include*, core.hooksPath (with -c,
#     --config-env, `git config`, GIT_CONFIG_* variables or another HOME), and
#     an unknown git subcommand in a command that writes the git config;
#   - a direct pull request merge: merges go through scripts/harness/merge-pr.sh,
#     which checks the squash message that enters main (F-0009);
#   - anything at all when jq (or, for a push, python3) is missing.
# The command is read twice (L-004): flattened, with quotes dropped and split
# at every shell operator, which sees commands inside quotes (`sh -c '...'`),
# and tokenized with shlex in POSIX mode, which keeps quoted values whole so a
# space or ; inside them cannot shift the subcommand (F-0013). Continuations
# are joined first (F-0010). Conservative on purpose: a false positive only
# makes Claude reword the command.
# Threat model (docs/adr/0000-hooks-locales-red-no-frontera.md): this hook and
# pre-push are a best-effort net against accidental mistakes, not a security
# boundary. The boundary is the branch protection of main on GitHub. The known
# limits (nested command strings, config written to .git/config by an earlier
# command, scripts run from files...) are listed in that ADR and are not
# chased here with more shell parsing (L-005).
set -u
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
# Without jq the command cannot be read: block rather than let it run.
if ! command -v jq >/dev/null 2>&1; then
  echo "harness: falta jq; guard-git no puede leer el comando y lo bloquea. Instala jq." >&2
  exit 2
fi
input="$(cat)"
cmd="$(jq -r '.tool_input.command // empty' <<< "$input")"
# cwd follows Claude (cd, worktrees); CLAUDE_PROJECT_DIR stays at the project
# root (https://code.claude.com/docs/en/hooks).
session_cwd="$(jq -r '.cwd // empty' <<< "$input")"
[ -z "$cmd" ] && exit 0

block() {
  echo "harness: $1. Usa rama + PR; desde main solo se sube la etiqueta e<N>-cerrada." >&2
  exit 2
}

project="${CLAUDE_PROJECT_DIR:-$PWD}"
cmd="${cmd//\\$'\n'/}"                          # line continuations, joined as bash does (F-0010)
cmd="$(sed -E 's/[0-9]+([<>])/\1/g' <<< "$cmd")" # in 2>&1 the descriptor number is not an argument

# Facts about the whole command.
pushy=0
if [[ "$cmd" =~ (^|[^[:alnum:]_-])(git-)?(push|send-pack)([^[:alnum:]_-]|$) ]]; then pushy=1; fi
touches_config=0
case "$cmd" in *.git/config* | *.gitconfig*) touches_config=1 ;; esac
# A function definition (name() {); function, alias and eval as command words
# are noted while reading, so a message that only mentions them is not code.
defines_code=0
if [[ "$cmd" =~ [A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\)[[:space:]]*\{ ]]; then defines_code=1; fi

any_push=0
all_closing=1 # every push seen is `git push <remote> e<N>-cerrada`
push_dirs=()  # directories the pushes act on
has_git=0
env_config=0 # GIT_CONFIG_*, HOME and similar set for this command
cur_dir=""

is_builtin() {
  case "$1" in
    add | am | annotate | apply | archive | bisect | blame | branch | bundle | cat-file | check-attr | \
      check-ignore | checkout | cherry | cherry-pick | clean | clone | commit | commit-tree | config | \
      count-objects | describe | diff | diff-files | diff-index | diff-tree | difftool | fetch | \
      for-each-ref | format-patch | fsck | gc | grep | hash-object | help | init | log | ls-files | \
      ls-remote | ls-tree | merge | merge-base | merge-file | mv | notes | prune | pull | push | \
      range-diff | read-tree | rebase | reflog | remote | repack | replace | reset | restore | revert | \
      rev-list | rev-parse | rm | send-pack | shortlog | show | show-ref | sparse-checkout | stash | status | \
      submodule | switch | symbolic-ref | tag | update-index | update-ref | var | version | worktree | \
      write-tree) return 0 ;;
  esac
  return 1
}

# check_config_key <key>: config that could make a push or switch hooks off.
check_config_key() {
  local key="${1,,}"
  if [[ "$key" =~ ^(alias|push|remote|include|includeif)\. ]] || [ "$key" = core.hookspath ]; then
    block "configuración de git que puede convertir un comando en push o apagar los hooks ($1)"
  fi
}

# check_git_config <args...>: a read only if the read action comes before the
# first key; otherwise every key is checked (git config k v --get writes).
check_git_config() {
  local a
  for a in "$@"; do
    case "$a" in
      --get | --get-all | --get-regexp | --get-urlmatch | --list | -l | get | list) return 0 ;;
      -*) ;;
      *) break ;;
    esac
  done
  for a in "$@"; do
    case "$a" in -*) ;; *) check_config_key "$a" ;; esac
  done
}

# note_assignment <NAME=value>: variables that change git's configuration.
note_assignment() {
  if [[ "${1%%=*}" =~ ^(GIT_CONFIG[A-Z0-9_]*|GIT_DIR|GIT_WORK_TREE|GIT_EXEC_PATH|HOME|XDG_CONFIG_HOME)$ ]]; then
    env_config=1
  fi
}

# resolve_dir <base> <path>: the directory a cd or -C leads to, or ? if it
# depends on run time.
resolve_dir() {
  case "$2" in
    *'$'* | *'`'* | -) echo "?" ;;
    '~') echo "${HOME:-?}" ;;
    '~/'*) echo "${HOME:-?}/${2#\~/}" ;;
    /*) echo "$2" ;;
    *) if [ "$1" = "?" ]; then echo "?"; else echo "$1/$2"; fi ;;
  esac
}

# record_push_dir [git -C value]: the directory this push acts on.
record_push_dir() {
  local d="$cur_dir"
  if [ -n "${1:-}" ]; then d="$(resolve_dir "$cur_dir" "$1")"; fi
  [ "$d" != "?" ] || block "push en un directorio que no se conoce antes de ejecutarse"
  push_dirs+=("$d")
}

# check_push_args <args after push...>: what no push may carry; also records
# whether this push is exactly the epic closing tag.
check_push_args() {
  local a words=() options=0 closing=0 t
  for a in "$@"; do
    case "$a" in
      *'$'* | *'`'* | *'{'* | *'}'*) block "push con expansión de shell ($a): no se puede comprobar antes de ejecutarse" ;;
      --force* | --no-v* | --al* | --b* | --m*) block "push prohibido ($a)" ;;
      --*) options=1 ;;
      -*f*) block "push forzado ($a)" ;;
      -*) options=1 ;;
      +*) block "refspec forzado ($a)" ;;
      : | *'*'* | *'?'* | *'['*) block "refspec de varias ramas ($a)" ;;
      main | *:main | */main) block "push hacia main ($a)" ;;
      *) words+=("$a") ;;
    esac
  done
  if [ "$options" -eq 0 ] && [ "${#words[@]}" -ge 2 ] && [[ "${words[0]}" =~ ^[A-Za-z0-9._-]+$ ]]; then
    closing=1
    for t in "${words[@]:1}"; do
      [[ "$t" =~ ^e[0-9]+-cerrada$ ]] || closing=0
    done
  fi
  [ "$closing" -eq 1 ] || all_closing=0
}

# has_push_word: the current simple command mentions a push.
has_push_word() {
  local x
  for x in "${w[@]}"; do
    case "$x" in push | send-pack | *git-push | *git-send-pack) return 0 ;; esac
  done
  return 1
}

# analyze_words: every rule, on one simple command already split into w.
analyze_words() {
  local n="${#w[@]}" i j k word cmdword cmd_index cdir v sub expansion saw_pr
  local rest=() alias_words=()
  [ "$n" -gt 0 ] || return 0
  i=0
  while [ "$i" -lt "$n" ] && [[ "${w[$i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do
    note_assignment "${w[$i]}"
    i=$((i + 1))
  done
  [ "$i" -lt "$n" ] || return 0
  cmd_index="$i"
  cmdword="${w[$i]}"
  case "$cmdword" in
    export | declare | typeset | readonly | local | env)
      for ((k = i + 1; k < n; k++)); do
        if [[ "${w[$k]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then note_assignment "${w[$k]}"; fi
      done ;;
    cd | pushd) cur_dir="$(resolve_dir "$cur_dir" "${w[$((i + 1))]:-~}")" ;;
    popd) cur_dir="?" ;;
    function | alias | eval) defines_code=1 ;;
  esac
  # A command word decided at run time ($g, `...`) that pushes.
  if [[ "$cmdword" == *'$'* || "$cmdword" == *'`'* ]] && has_push_word; then
    block "orden que se decide al ejecutarse ($cmdword) y hace push"
  fi
  # git produced by an expansion right before this simple command: `$(...) push`.
  if [ "$cmdword" = push ]; then
    any_push=1
    record_push_dir ""
    check_push_args "${w[@]:$((i + 1))}"
  fi
  # A pull request merge that skips merge-pr.sh.
  if [ "$cmdword" = gh ] || [[ "$cmdword" == */gh ]]; then
    saw_pr=0
    for ((k = i + 1; k < n; k++)); do
      case "${w[$k]}" in
        pr) saw_pr=1 ;;
        merge) if [ "$saw_pr" -eq 1 ]; then block "fusión directa de un PR: usa scripts/harness/merge-pr.sh (revisa el mensaje del squash, F-0009)"; fi ;;
        *pulls/*/merge*) block "fusión de un PR por la API: usa scripts/harness/merge-pr.sh" ;;
      esac
    done
  fi
  for ((i = 0; i < n; i++)); do
    word="${w[$i]}"
    if [ "$word" = xargs ]; then
      for ((k = i + 1; k < n; k++)); do
        case "${w[$k]}" in git | */git | *git-*) block "git detrás de xargs: sus argumentos no se pueden comprobar" ;; esac
      done
    fi
    case "$word" in
      git-send-pack | */git-send-pack | git-push | */git-push)
        # In the flattened reading the words of a quoted message are loose, so
        # only a command word counts there; tokens are exact.
        if [ "$pass" = tokens ] || [ "$i" -eq "$cmd_index" ]; then
          block "$word: usa git push (send-pack no pasa por el hook pre-push)"
        fi
        continue ;;
      git | */git) ;;
      *'$'*) [[ "${word,,}" == *git* ]] || continue ;;
      *) continue ;;
    esac
    has_git=1
    # git's global options, then the subcommand.
    j=$((i + 1))
    cdir=""
    while [ "$j" -lt "$n" ]; do
      case "${w[$j]}" in
        -C) cdir="${w[$((j + 1))]:-}"; j=$((j + 2)) ;;
        -c) v="${w[$((j + 1))]:-}"; check_config_key "${v%%=*}"; j=$((j + 2)) ;;
        --config-env=*) v="${w[$j]#--config-env=}"; check_config_key "${v%%=*}"; j=$((j + 1)) ;;
        --config-env) v="${w[$((j + 1))]:-}"; check_config_key "${v%%=*}"; j=$((j + 2)) ;;
        --git-dir | --work-tree | --namespace | --super-prefix) j=$((j + 2)) ;;
        -*) j=$((j + 1)) ;;
        *) break ;;
      esac
    done
    sub="${w[$j]:-}"
    rest=("${w[@]:$((j + 1))}")
    [ -n "$sub" ] || continue
    case "$sub" in
      send-pack) block "git send-pack no pasa por el hook pre-push" ;;
      config)
        check_git_config "${rest[@]}"
        continue ;;
    esac
    if ! is_builtin "$sub"; then
      if [ "$touches_config" -eq 1 ]; then
        block "subcomando de git desconocido ($sub) en un comando que escribe la configuración de git"
      fi
      expansion="$(git -C "$project" config --get "alias.$sub" 2>/dev/null)"
      case "$expansion" in
        '!'*push*) block "alias de shell de git que hace push (git $sub)" ;;
        push | push' '*)
          read -r -a alias_words <<< "${expansion#push}"
          sub=push
          rest=("${alias_words[@]}" "${rest[@]}") ;;
      esac
    fi
    [ "$sub" = push ] || continue
    any_push=1
    record_push_dir "$cdir"
    check_push_args "${rest[@]}"
  done
}

# start_pass <name>: each reading starts in the directory Claude works in.
start_pass() {
  pass="$1"
  cur_dir="${session_cwd:-$PWD}"
}

# Flattened reading: quotes and backslashes dropped, every shell operator
# (backticks included) ends a command. The tokenized reading below keeps a
# backtick inside its word, where a push refuses it.
start_pass flat
while IFS= read -r segment; do
  read -r -a w <<< "$segment"
  analyze_words
done <<< "$(printf '%s' "$cmd" | tr -d "\"'\\\\" | tr ';&|()`<>' '\n\n\n\n\n\n\n\n')"

# Tokenized reading, only for commands that push (F-0013).
if [ "$pushy" -eq 1 ]; then
  command -v python3 >/dev/null 2>&1 || block "falta python3; guard-git no puede leer las comillas de un push"
  tokens="$(GUARD_CMD="$cmd" python3 -c '
import os, re, shlex
# Heredoc bodies are data here: an apostrophe in them must not make the
# command unreadable. The flattened reading still sees them.
lines = os.environ["GUARD_CMD"].split("\n")
kept, i = [], 0
while i < len(lines):
    kept.append(lines[i])
    delimiters = re.findall(r"<<-?[ \t]*([\x27\x22]?)([A-Za-z_][A-Za-z0-9_]*)\1", lines[i])
    i += 1
    for _, delimiter in delimiters:
        while i < len(lines) and lines[i].strip() != delimiter:
            i += 1
        i += 1
try:
    lex = shlex.shlex("\n".join(kept), posix=True, punctuation_chars=";&|()<>")
    lex.whitespace_split = True
    tokens = list(lex)
except ValueError:
    print("\x1e")
    raise SystemExit(0)
segment = []
for token in tokens:
    if token and set(token) <= set(";&|()<>"):
        print("\x1f".join(segment))
        segment = []
    else:
        segment.append(token.replace("\n", " "))
print("\x1f".join(segment))
')"
  [ "$tokens" != $'\x1e' ] || block "push con comillas sin cerrar: no se puede leer"
  start_pass tokens
  while IFS= read -r segment; do
    IFS=$'\x1f' read -r -a w <<< "$segment"
    analyze_words
  done <<< "$tokens"
fi

if [ "$env_config" -eq 1 ] && [ "$has_git" -eq 1 ]; then
  block "git con configuración cambiada por variables de entorno (GIT_CONFIG_*, HOME...)"
fi
if [ "$defines_code" -eq 1 ] && [ "$pushy" -eq 1 ]; then
  block "push en un comando que define funciones, alias o usa eval: no se puede comprobar antes de ejecutarse"
fi

[ "$any_push" -eq 1 ] || exit 0
[ "$all_closing" -eq 1 ] && exit 0
# push_dirs already holds the directory each push acts on (cwd, cd, -C).
for d in "$project" "$PWD" "${push_dirs[@]}"; do
  if [ "$(git -C "$d" branch --show-current 2>/dev/null)" = main ]; then
    block "push desde main ($d). Crea una rama e<N>/paso-<M>-<nombre>"
  fi
done
exit 0
