---
name: epica
description: Construye una épica de Actaira paso a paso con el bucle completo de construir, verificar, pasada adversarial, corregir y registrar fallos. Úsala con el número de épica, por ejemplo /epica E1.
---

# Bucle de construcción de una épica ($ARGUMENTS)

Trabaja de forma **continua**: termina un paso y empieza el siguiente sin pedir permiso. Solo paras en tres casos: una acción que exige a Marcos, una condición de parada de este bucle, o el final de la épica.

## Antes de empezar

1. Lee `docs/epicas/$ARGUMENTS.md`, `docs/estado/$ARGUMENTS.md` (si existe), `docs/harness/LECCIONES.md` y los últimos 10 fallos de `docs/harness/FALLOS.md`.
2. Comprueba los prerrequisitos de la épica. Si falta alguno que depende de Marcos, prepara sus comandos exactos y para.

## Para cada paso de la épica

1. **Rama:** `git switch main && git pull --ff-only && git switch -c e<N>/paso-<M>-<nombre>`. Relee `docs/harness/LECCIONES.md` del disco: se lee al empezar cada paso, no solo al empezar la épica.
2. **Plan corto** en `docs/estado/$ARGUMENTS.md`: qué se hace, qué ficheros se tocan y cómo se comprueba cada punto del "Listo cuando".
3. **APIs externas:** si el paso usa un servicio externo nuevo, llama al subagente `verificador-apis` **antes** de escribir código. Nada `sin confirmar` se construye sin probarlo antes en una cuenta de prueba.
4. **Tests primero.** Escribe los tests que codifican el "Listo cuando" del paso y comprueba que **fallan**.
5. **Construye** lo mínimo que los hace pasar, con calidad de producción: errores manejados, límites y logs sin datos sensibles.
6. **`make check`** en verde. El hook de parada no te deja terminar en rojo.
7. **Ejecución real** del comportamiento sobre un caso real (repo del corpus, repo de demo o entorno local), con la salida guardada en `evals/sessions/`.
8. **Pasada adversarial:** skill `pasada-adversarial`.
9. **Cada fallo encontrado en los puntos 4 a 8 que no fuera esperado** pasa por la skill `registrar-fallo`: causa raíz, guardia, y test que falla antes y pasa después.
10. **`make gate`** en verde (`check`, `evals-paso` y `e2e-rapido`). Solo la ejecutas tú, nunca el revisor.
11. **PR y fusión:** `git push -u origin <rama>`, `gh pr create --fill` y `scripts/harness/merge-pr.sh <pr> "<asunto>" <fichero con el cuerpo>`. El script comprueba que ni el mensaje del squash ni el PR llevan atribución de Claude (F-0009) ni secretos, espera a que los checks terminen en verde y fusiona con squash, borrando la rama, sobre el mismo commit que se comprobó. Una fusión directa con gh la bloquea el guard. Si `main` ha avanzado (la protección exige la rama al día), se trae con un merge local de `origin/main` en la rama y un push normal, nunca con el botón de la web, que firma con el correo principal de la cuenta (F-0015). Si un commit con atribución de Claude ya está subido en la rama, no se reescribe (el push forzado está prohibido): se abre una rama nueva desde `main` con el trabajo sin ese commit, un PR nuevo, y el anterior se cierra sin fusionar.
12. **Actualiza `docs/estado/$ARGUMENTS.md`:** hecho, cifras medidas, siguiente paso y backlog.

## Condiciones de parada (anti-bucle)

- **Tres intentos distintos** sin arreglar lo mismo: registra el fallo, deja el diagnóstico y para.
- **Tres rondas adversariales** en un paso con críticos o altos todavía abiertos: para y reporta.
- **Una API que no se comporta como su documentación:** para, registra y propone alternativa.
- **Una acción que exige a Marcos:** para en un punto limpio con los comandos exactos; si `make check` queda en rojo por ello, escribe el motivo en `.harness/pausa-marcos` antes de parar.

## Al terminar el último paso

Ejecuta la skill `cierre-epica`.
