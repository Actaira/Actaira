---
name: pasada-adversarial
description: Ronda de revisión hostil sobre el paso actual con el subagente revisor-adversarial, con como mucho tres rondas y reglas estrictas de qué se corrige y qué va a backlog.
---

# Pasada adversarial

1. **Ronda 1:** commitea antes (lo que no está commiteado no sale en el diff) y llama al subagente `revisor-adversarial` con el paso, su "Listo cuando", el SHA de la cabeza, la ruta del repo principal y `docs/harness/LECCIONES.md` leído del disco (el que carga la sesión puede estar desfasado).
   - Su worktree aislado parte de `origin/main`, no del paso (https://code.claude.com/docs/en/worktrees), y su aislamiento rechaza `git -C` hacia el repo principal. Como los worktrees comparten los objetos, pídele que revise desde el suyo: `git worktree list` para ver el SHA, `git diff main...<SHA>` y `git show <SHA>:<ruta>`; y, si ejecuta `make check`, que lo haga en `git clone --branch <rama> <repo principal> "$(mktemp -d)"`, con `.tools/` copiado del repo principal, sin descargar nada.
2. **Qué se hace con cada hallazgo:**
   - **crítico o alto:** se corrige en este paso. Antes, `registrar-fallo`, con su guardia;
   - **medio:** se corrige si cuesta poco; si no, una línea en `docs/BACKLOG.md` con el motivo;
   - **bajo:** a backlog o se descarta, diciendo por qué;
   - **falso positivo:** se descarta con la prueba (comando y salida) de que no aplica.
3. **Ronda 2** solo si la 1 tuvo críticos o altos, y **ronda 3** solo si la 2 los tuvo. Cada ronda revisa el diff completo, no solo las correcciones.
4. **Si tras la ronda 3 queda algún crítico o alto:** para, deja el diagnóstico en `docs/estado/` y devuelve el control a Marcos.
5. **Deja el resumen en el PR:** rondas, hallazgos por severidad y qué se hizo con cada uno.

**Una ronda nunca produce** documentos de decisión, criterios nuevos ni puertas nuevas. Solo correcciones, entradas de fallo o líneas de backlog.
