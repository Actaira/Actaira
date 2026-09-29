---
name: cierre-epica
description: Pasada de conjunto al terminar una épica: todo el sistema hasta aquí, no solo el último paso. Úsala al final de cada épica y, antes de desplegar, sobre el sistema completo.
---

# Cierre de la épica ($ARGUMENTS)

0. **Base de comparación:** `base=$(git describe --tags --abbrev=0 --match 'e*-cerrada' 2>/dev/null || git rev-list --max-parents=0 HEAD)`.
1. **`make gate` desde un clon limpio**, en otra carpeta y sin nada local, ejecutado **una sola vez por ti**; guarda la salida en `evals/sessions/`. Si falla en limpio y no en tu carpeta, es un fallo: `registrar-fallo`. Guarda también la salida de `scripts/harness/check-protection.sh`: la protección de `main` en GitHub es la frontera (ADR 0000) y tiene que seguir siendo la de `docs/estado/branch-protection.json`; si no, para y avisa a Marcos.
2. **`make e2e-completo`: pruebas de extremo a extremo de todo lo construido hasta ahora**, no solo de esta épica. Por ejemplo, en E3: CLI, Action, subida a la nube local, consola y cobro en modo test. Todo lo que funcionaba en épicas anteriores tiene que seguir funcionando.
3. **Tres subagentes en paralelo sobre la épica entera** (`git diff $base...HEAD`), pasándoles la salida de los puntos 1 y 2; ellos no vuelven a ejecutar gate ni e2e. Como en la `pasada-adversarial`, commitea antes y pásales el SHA y la ruta del repo principal: su worktree parte de `origin/main` y revisan con `git diff`, `git show <SHA>:<ruta>` y un clon temporal:
   - `revisor-adversarial`, con foco en integración entre pasos y regresiones;
   - `revisor-adversarial`, con foco en seguridad y fugas de datos;
   - `verificador-apis`, sobre todas las llamadas externas de la épica.
4. **Los críticos y altos se corrigen** con el bucle normal (registrar el fallo, poner la guardia, PR). Hasta tres rondas de conjunto; si quedan, se para y se informa.
5. **Documentación contra realidad:** README, docs y mensajes de la CLI y la consola no afirman nada que no pase los tests. Se ejecuta cada comando de la documentación y se compara con la salida.
6. **Lecciones:** repasa `FALLOS.md` de la épica. Toda regla que se haya repetido dos veces tiene que tener ya una guardia automática.
7. **`docs/estado/$ARGUMENTS.md` final:**
   - qué se construyó;
   - las cifras medidas;
   - el "Listo cuando" con la salida real de cada punto;
   - los fallos de la épica y sus guardias;
   - el backlog;
   - lo que la siguiente épica necesita de Marcos.
8. **Etiqueta `e<N>-cerrada`** en `main` actualizado: `git switch main && git pull --ff-only && git tag e<N>-cerrada && git push origin e<N>-cerrada`. El estado de esta épica se fusiona antes de la etiqueta, así que la salida de `git ls-remote --tags origin e<N>-cerrada` va a los prerrequisitos de `docs/estado/E<N+1>.md` y al informe a Marcos.
