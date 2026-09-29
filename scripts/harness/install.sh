#!/usr/bin/env bash
# Installs the harness into a repo. Usage: scripts/harness/install.sh <package-dir> <repo-dir>
# Copies hidden files too (.claude/). Never overwrites an existing FALLOS.md or LECCIONES.md.
# Once installed, the repo is the source of truth for the harness: a package
# older than the repo lacks later fixes (env.sh, pre-push) and is refused.
set -euo pipefail
[ "$#" -eq 2 ] || { echo "uso: $0 <paquete> <repo>"; exit 2; }
pkg="$1"; repo="$2"
[ -d "$pkg/harness" ] || { echo "no encuentro $pkg/harness"; exit 1; }
# The repo root itself: not a subdirectory of a repo, not a bare repo.
top="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)" || { echo "$repo no es un repo git con árbol de trabajo"; exit 1; }
[ "$top" = "$(cd "$repo" && pwd -P)" ] || { echo "$repo no es la raíz del repo ($top)"; exit 1; }
# Check the package before touching the repo, so a failure never leaves it half installed.
for need in scripts/harness/pre-push scripts/harness/commit-msg scripts/harness/check-attribution.sh \
  scripts/harness/env.sh .claude/settings.json; do
  [ -f "$pkg/harness/$need" ] || { echo "paquete incompleto o antiguo: falta harness/$need"; exit 1; }
done
for need in PLAN.md 10_llm.md; do
  [ -f "$pkg/$need" ] || { echo "paquete incompleto: falta $need"; exit 1; }
done
[ -d "$pkg/epicas" ] || { echo "paquete incompleto: falta epicas/"; exit 1; }

# FALLOS.md and LECCIONES.md belong to the repo. The package copy overwrites
# them, so they are put back on every exit, also when the install fails halfway.
keep_dir="$(mktemp -d)"
restore_kept() {
  local keep
  for keep in FALLOS.md LECCIONES.md; do
    if [ -f "$keep_dir/$keep" ]; then cp "$keep_dir/$keep" "$repo/docs/harness/$keep"; fi
  done
}
trap 'restore_kept; rm -rf "$keep_dir"' EXIT
for keep in FALLOS.md LECCIONES.md; do
  if [ -f "$repo/docs/harness/$keep" ]; then cp "$repo/docs/harness/$keep" "$keep_dir/$keep"; fi
done

cp -a "$pkg/harness/." "$repo/"
mkdir -p "$repo/docs/estado" "$repo/docs/adr" "$repo/docs/epicas"
cp "$pkg/PLAN.md" "$repo/docs/PLAN.md"
cp "$pkg/10_llm.md" "$repo/docs/LLM.md"
cp -a "$pkg/epicas/." "$repo/docs/epicas/"
[ -f "$repo/docs/BACKLOG.md" ] || printf '# Backlog\n' > "$repo/docs/BACKLOG.md"
restore_kept

chmod +x "$repo"/scripts/harness/*.sh "$repo/scripts/harness/pre-push" "$repo/scripts/harness/commit-msg"
grep -qxF '* text=auto eol=lf' "$repo/.gitattributes" 2>/dev/null || echo '* text=auto eol=lf' >> "$repo/.gitattributes"
for ig in '.harness/' '.env' '.env.*' '.tools/' '.claude/worktrees/' '.claude/settings.local.json'; do
  grep -qxF "$ig" "$repo/.gitignore" 2>/dev/null || echo "$ig" >> "$repo/.gitignore"
done

# git hooks, same sources as `make install-hooks`:
#   pre-push   rejects pushes to main (the only protection in private free-plan repos);
#   commit-msg rejects Claude co-authorship or attribution in the message.
for name in pre-push commit-msg; do
  hook="$(cd "$repo" && git rev-parse --path-format=absolute --git-path "hooks/$name")"
  mkdir -p "$(dirname "$hook")"
  cp "$repo/scripts/harness/$name" "$hook"
  chmod +x "$hook"
done
echo "harness instalado en $repo"
