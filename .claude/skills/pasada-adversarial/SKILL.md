---
name: pasada-adversarial
description: Ronda de revisión hostil sobre el paso actual con el subagente revisor-adversarial, con como mucho tres rondas (una en los pasos de solo documentación) y reglas estrictas de qué se corrige y qué va a backlog.
---

# Pasada adversarial

1. **Ronda 1:** commitea antes (lo que no está commiteado no sale en el diff) y llama al subagente `revisor-adversarial` con el paso, su "Listo cuando", el SHA de la cabeza, la ruta del repo principal y `docs/harness/LECCIONES.md` leído del disco (el que carga la sesión puede estar desfasado).
   - En un paso de producto, pídele que dedique la ronda al código del producto y que solo revise el harness si el paso lo cambia (L-013).
   - Su worktree aislado parte de `origin/main`, no del paso (https://code.claude.com/docs/en/worktrees), y su aislamiento rechaza `git -C` hacia el repo principal. Como los worktrees comparten los objetos, pídele que revise desde el suyo: `git worktree list` para ver el SHA, `git diff main...<SHA>` y `git show <SHA>:<ruta>`; y, si ejecuta `make check`, que lo haga en `git clone --branch <rama> <repo principal> "$(mktemp -d)"`, con `.tools/` copiado del repo principal, sin descargar nada.
2. **Qué se hace con cada hallazgo,** con la severidad calibrada según L-013. Si el revisor marca como crítico o alto algo que exige colocar a propósito un fichero, un enlace, una directiva o una orden que se ve en el diff contra una guardia local del harness, se rebaja a bajo y va al backlog: no bloquea el paso. Crítico o alto solo si puede pasar por accidente, rompe el producto, filtra datos o secretos, o engaña a un usuario de Actaira o a quien decide con el ADR o las mediciones. La corrección de este último tipo es corregir el texto o medir, no construir mecanismo nuevo (F-0026).
   - **crítico o alto:** se corrige en este paso. Antes, `registrar-fallo`, con su guardia;
   - **medio:** se corrige si cuesta poco; si no, una línea en `docs/BACKLOG.md` con el motivo;
   - **bajo:** a backlog o se descarta, diciendo por qué;
   - **falso positivo:** se descarta con la prueba (comando y salida) de que no aplica.
3. **Ronda 2** solo si la 1 tuvo críticos o altos, y **ronda 3** solo si la 2 los tuvo. Cada ronda revisa el diff completo, no solo las correcciones.
   - **Paso de solo documentación** (su diff no toca código, scripts, tests ni configuración que se ejecute): una sola ronda (L-011). Los críticos se corrigen en el paso, con `registrar-fallo`. Los altos, medios y bajos van a `docs/BACKLOG.md` o al paso de código que los implementa, escritos en su épica. No hay ronda 2.
4. **Si tras la ronda 3 queda algún crítico o alto:** para, deja el diagnóstico en `docs/estado/` y devuelve el control a Marcos.
5. **Deja el resumen en el PR:** rondas, hallazgos por severidad y qué se hizo con cada uno.

**Una ronda nunca produce** documentos de decisión, criterios nuevos ni puertas nuevas. Solo correcciones, entradas de fallo o líneas de backlog.
