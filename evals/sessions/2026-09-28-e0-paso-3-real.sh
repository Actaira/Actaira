#!/usr/bin/env bash
# Real run of E0 step 0.3; writes evals/sessions/2026-09-28-e0-paso-3.txt.
set -uo pipefail
cd /home/usuario/actaira-ws/actaira
export PATH="$HOME/.local/go/bin:$HOME/go/bin:$PATH"
f=evals/sessions/2026-09-28-e0-paso-3.txt

# PATH of the running Claude Code process (the one hooks inherit).
p=$PPID
while [ "$p" -gt 1 ]; do
  case "$(tr '\0' ' ' < /proc/$p/cmdline)" in *native-binary/claude*) break ;; esac
  p="$(awk '{print $4}' /proc/$p/stat)"
done
hookpath="$(tr '\0' '\n' < /proc/$p/environ | sed -n 's/^PATH=//p')"
[ -n "$hookpath" ] || { echo "no encuentro el proceso de Claude Code"; exit 1; }

# Temporary clone outside the repo, removed on any exit (F-0008).
clone="$(mktemp -d)"
trap 'rm -rf "$clone"' EXIT
trailer="Co-Authored-By: Claude <noreply@""anthropic.com>"
quoted_push="git push origin 'main'"

{
echo "# E0 paso 0.3: ejecucion real"
echo "fecha: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "commit: $(git rev-parse HEAD) (rama $(git branch --show-current))"
echo "entorno: WSL2 $(uname -r), $(go version), make $(make --version | awk 'NR == 1 {print $3}'), git $(git --version | awk '{print $3}')"
echo
echo "## 1. guard-git.sh en vivo (PreToolUse de esta sesion de Claude Code)"
echo "comando lanzado con la herramienta Bash: $quoted_push   (con comillas: antes de F-0007 pasaba)"
echo "respuesta del hook (version de 33b0c9c): harness: push prohibido (main): force, no-verify, --all, --mirror, refspec forzado o main. Usa rama + PR."
echo "(bloqueado antes de ejecutarse; el texto es el que devolvio Claude Code)"
echo "comando lanzado con la herramienta Bash, partido con una continuacion de linea (F-0010):"
echo "  git push \\"
echo "    --no-verify origin e0/paso-3-tests-harness"
echo "respuesta del hook: harness: push prohibido (--no-verify). Usa rama + PR; desde main solo se sube la etiqueta e<N>-cerrada."
echo "comando lanzado con la herramienta Bash, con un valor citado con espacio en -c (F-0013):"
echo "  git -c 'user.name=a b' push --no-verify origin e0/paso-3-tests-harness"
echo "respuesta del hook: harness: push prohibido (--no-verify). Usa rama + PR; desde main solo se sube la etiqueta e<N>-cerrada."
echo
echo "## 2. make install-hooks en el repo real"
make -s install-hooks 2>&1
for h in pre-push commit-msg; do
  if cmp -s "scripts/harness/$h" ".git/hooks/$h"; then echo "$h instalado identico a scripts/harness/$h"; fi
done
echo
echo "## 3. commit-msg en un clon real del repo (sin arriesgar un commit con atribucion en el repo)"
echo "comando: git clone <repo> <tmp>; make install-hooks; git commit --allow-empty -m 'Probe' -m '<trailer Co-Authored-By de Claude>'"
git clone -q "$PWD" "$clone/r"
git -C "$clone/r" config user.email "harness-test@example.invalid"
git -C "$clone/r" config user.name "harness test"
(cd "$clone/r" && make -s install-hooks >/dev/null 2>&1)
before="$(git -C "$clone/r" rev-parse HEAD)"
rc=0; git -C "$clone/r" commit -q --allow-empty -m "Probe" -m "$trailer" 2>&1 || rc=$?
same="NO"; if [ "$(git -C "$clone/r" rev-parse HEAD)" = "$before" ]; then same="si"; fi
echo "exit del commit con atribucion: $rc; HEAD sin cambios: $same"
rc=0; git -C "$clone/r" commit -q --allow-empty -m "Probe without attribution" 2>&1 || rc=$?
echo "exit del commit limpio: $rc"
echo
echo "## 4. Hook de parada con el PATH real del proceso de Claude Code, sin Go"
echo "go en ese PATH: $(env -i PATH="$hookpath" /bin/bash -c 'command -v go || echo no')"
t0=$(date +%s)
out="$(printf '{"session_id":"sesion-real-e0-3"}' | env -i HOME="$HOME" PATH="$hookpath" CLAUDE_PROJECT_DIR="$PWD" scripts/harness/stop-gate.sh 2>&1)"; rc=$?
t1=$(date +%s)
echo "salida: ${out:-<vacia>}"
echo "exit: $rc, duracion: $((t1 - t0)) s"
echo
echo "## 5. make gate"
gate_out="$(make gate 2>&1)"; rc=$?
grep -vE '^--- PASS' <<< "$gate_out"
echo "exit: $rc"
echo "tests del harness en verde en ese make gate: $(grep -c '^--- PASS' <<< "$gate_out")"
} > "$f" 2>&1
