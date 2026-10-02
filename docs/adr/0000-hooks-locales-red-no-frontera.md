# ADR 0000: los hooks de git locales son una red; la frontera es la protección de `main`

- **Estado:** aceptado.
- **Fecha:** 2026-09-28.
- **Decide:** Marcos, tras la ronda 3 de la pasada adversarial del paso 0.3 de la E0 (`docs/estado/E0.md`).
- **Número:** 0000, porque es una decisión del harness, anterior al producto; la E1 ya reserva del 0001 al 0003.
- **Ampliado:** por Marcos el 2026-09-29, tras la ronda 3 del paso 1.1 de la E1, con la decisión 6: todas las guardias locales del harness son redes, y así se califica la severidad de lo que las esquiva (L-013).

## Contexto

El harness tiene tres piezas locales que paran un cambio indebido antes de que llegue a GitHub:

- `scripts/harness/guard-git.sh`, hook PreToolUse de Claude Code: lee el texto de cada comando de shell antes de que se ejecute y bloquea los push peligrosos y las fusiones directas de PR;
- `scripts/harness/pre-push`, hook de git: rechaza cualquier push a `main` desde el clon local;
- `scripts/harness/commit-msg`, hook de git: rechaza la atribución de Claude en el mensaje del commit.

En las tres rondas adversariales del paso 0.3, cada ronda encontró otra forma de que el shell ejecute algo distinto de lo que lee el guard: comillas y operadores (F-0007), continuaciones de línea (F-0010), un valor citado con espacio en `-c` (F-0013) y, en la ronda 3, órdenes anidadas, un `#` en mitad de palabra, cuerpos de heredoc y configuración que una orden escribe en `.git/config` y la siguiente usa. Un hook que lee el texto antes de que el shell lo expanda no puede saber qué va a ejecutar el shell: cada corrección abre otra variante. El `pre-push`, además, se salta con `--no-verify` o con `core.hooksPath`, y un clon nuevo no lo tiene hasta `make install-hooks`.

## Decisión

1. **`guard-git.sh`, `pre-push` y `commit-msg` son una red contra errores accidentales, best-effort, y no una frontera de seguridad.** Paran los errores habituales al escribir un comando (push forzado, `--no-verify`, destino `main`, push desde `main`, fusión directa de un PR) y dicen por qué. No se garantiza que paren una orden construida para esquivarlos.
2. **La frontera es la protección de `main` en GitHub** (paso 0.4, `docs/estado/branch-protection.json`): PR obligatorio con 0 aprobaciones, check `check` de GitHub Actions obligatorio y al día con `main`, `enforce_admins`, sin push forzado y sin borrado. La aplica el servidor a todo push y a toda fusión, venga de donde venga, también a los administradores (https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches; API: https://docs.github.com/en/rest/branches/branch-protection). `scripts/harness/check-protection.sh` compara la protección real con el JSON.
3. **No se persiguen más variantes de parseo de shell en el guard.** Una variante nueva se anota en "Límites conocidos" (L-005).
4. **Las fusiones que no pasan por `scripts/harness/merge-pr.sh`** (`env gh pr merge`, `sh -c "gh pr merge ..."`, la API) **las cubre el check obligatorio**: GitHub no fusiona hasta que `check` está en verde en la cabeza del PR y al día con `main`, y `check` pasa `check-attribution.sh` por los commits del PR. En este repo, el mensaje del squash que GitHub compone por defecto sale de esos mismos commits (`squash_merge_commit_message: COMMIT_MESSAGES`, https://docs.github.com/en/rest/repos/repos#update-a-repository). Eso cubre la fusión sin mensaje propio: un asunto o un cuerpo propios (`--subject`, `--body`, o `commit_title` y `commit_message` en la API) entran en `main` sin que `check` los haya visto. `merge-pr.sh` los revisa antes de fusionar (atribución y secretos) y el commit que entró, después; en la CI de `main`, el escaneo de secretos lee también los mensajes de commit. La regla del guard sobre `gh pr merge` se queda como está, sin más expresiones regulares.
5. **`check` en verde tiene que significar `make check` ejecutado** (F-0014, L-006). El servidor solo exige que `check` salga en verde, y lo que ejecuta `check` lo define el propio PR. Por eso `ci.yml` y los prerrequisitos de `check` y `gate` se comparan con su contenido exacto en `make check`, ningún otro workflow puede tener un job `check`, el check tiene que venir de GitHub Actions (app 15368) y nadie tiene excepción al PR obligatorio.
6. **Todas las guardias locales del harness son redes contra errores accidentales,** no solo los hooks de git: `guard-git.sh`, `pre-push`, `commit-msg`, `check-skips.sh`, `check-weakeners.sh`, `check-pipes.sh`, `check-personal.sh`, `check-attribution.sh`, `secrets-scan.sh` y las que vengan.
   - En una revisión adversarial, un hallazgo que exige colocar a propósito un fichero, un enlace, una directiva o una orden que se ve en el diff del PR es como mucho bajo, va al backlog y no bloquea el paso.
   - Alto o crítico, solo lo que puede pasar por accidente, rompe el producto, filtra datos o secretos, o engaña a un usuario de Actaira o a quien decide con el ADR o las mediciones. La corrección de este último tipo es corregir el texto o medir, no construir mecanismo nuevo (decisión de Marcos del 2026-10-02, F-0026).
   - Lo construido a propósito lo para la revisión del diff, que es parte de la frontera junto con la protección de `main`.
   - En un paso de producto, la revisión se dedica al código del producto, y el harness solo se revisa si el paso lo cambia (L-013).

## Opciones

| Opción | A favor | En contra |
|---|---|---|
| A. Seguir cerrando variantes en el guard: tokenizar de forma recursiva `sh -c`, backticks y `$(...)`, y guardar el estado de `.git/config` | Caza más errores antes de ejecutarse | No termina: bash tiene más formas de construir un comando de las que un hook puede leer sin ejecutarlo, y tres rondas lo demuestran. Cada corrección añade código y falsos positivos |
| B. Bloquear todo comando que el guard no entienda del todo | Cierra las variantes | Bloquea trabajo normal (`sh -c`, `$(...)`, heredocs) y empuja a escribir scripts, que el guard tampoco lee |
| C. **Elegida:** red local best-effort y frontera en el servidor | La garantía no depende de leer bien el shell: el servidor ve la actualización real de la rama, no el texto del comando | Donde el servidor no protege la rama no hay frontera (ver "Errores") |

## Por qué esta

Lo que importa es que nada entre en `main` sin PR y sin `check` en verde, y eso solo lo puede garantizar quien recibe el push. El guard sigue siendo útil como red: responde antes de ejecutar, le explica el motivo a Claude y evita los errores habituales sin esperar al servidor.

## Coste

- **Dinero:** ninguno; las ramas protegidas están incluidas en GitHub Free para repos públicos (https://docs.github.com/en/rest/branches/branch-protection).
- **Proceso:** todo cambio en `main` pasa por PR y por la CI, también los de Marcos como administrador. Un arreglo urgente en `main` exige quitar la protección (ver "Reversión").
- **Mantenimiento:** el guard se queda con sus tests actuales (24 en `guard-git_test.sh`) y deja de crecer.

## Latencia

- El guard añade a cada comando de shell una mediana de 9 ms (p90 de 10 ms), y a cada push una de 25 ms (p90 de 26 ms), porque entonces ejecuta python3 (`evals/results/2026-09-28-guard-git-latencia.txt`).
- La protección no añade latencia local; cada fusión espera a que `check` termine en la CI.

## Errores

- **El guard no ve un push peligroso** (límites de abajo): si va a `main`, lo rechaza el `pre-push` cuando está instalado y no se ha desactivado, y en cualquier caso lo rechaza el servidor. Nada entra en `main` sin PR y sin `check` en verde.
- **Falta jq o python3:** sin jq, el guard bloquea todos los comandos; sin python3, todos los push (`guard-git_test.sh::test_blocks_everything_without_jq`, `::test_blocks_a_push_without_python3`).
- **Un cambio en lo que ejecuta `check`:** GitHub da por bueno un job saltado aunque su check sea obligatorio (https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-jobs-with-conditions), y un paso puede saltarse o fallar sin que el job falle. Un cambio accidental en `ci.yml` o en los prerrequisitos de `check` pone `make check` en rojo en local y en el hook de parada (F-0014); uno deliberado queda a la vista en el diff del PR, junto con el test que lo acompaña. Las recetas de cada prerrequisito no están fijadas línea a línea (backlog).
- **Alguien quita o cambia la protección en GitHub:** la frontera desaparece sin aviso local. `scripts/harness/check-protection.sh` compara la protección real con `docs/estado/branch-protection.json` en el paso 0.4 y en cada cierre de épica (skill `cierre-epica`).
- **Repos donde GitHub no protege la rama:** con GitHub Free, un repo privado no tiene ramas protegidas (misma página de la API), así que ahí no hay frontera, solo la red. Si un repo así llega a guardar algo que importe, decide Marcos si pasa a público o a un plan con protección de ramas.

## Límites conocidos del guard

No son fallos abiertos: los cubre la protección de `main`.

1. **Órdenes anidadas:** la lectura tokenizada no entra en `sh -c "..."`, `bash -c "..."`, backticks ni `$(...)`, y ahí la lectura aplanada se desplaza con un valor citado con espacio. Por ejemplo, `sh -c "git -c 'x.y=a b' push --no-verify origin main"` pasa.
2. **`#` en mitad de una palabra:** `shlex` lo toma como comentario; bash, no.
3. **Heredocs:** la expresión que aparta los cuerpos de heredoc de la lectura tokenizada puede apartar líneas de más (tras `<<<`, o con un `<<EOF` entre comillas o en un comentario).
4. **Sin estado entre órdenes:** una orden escribe en `.git/config` (`core.hooksPath`, o `remote.origin.push = +HEAD:refs/heads/main`) y la siguiente, un `git push origin` inocuo, sube a `main` forzado y sin `pre-push`.
5. **Fusión directa de un PR con un prefijo:** `env gh pr merge ...`, `command gh ...`, `timeout 120 gh ...` o `sh -c "gh pr merge ..."`. La cubre el check obligatorio cuando se usa el mensaje por defecto; un mensaje propio entra sin revisar la atribución, y un secreto en él lo ve el escaneo de la CI de `main` cuando ya está dentro (decisión 4).
6. **Scripts:** el guard lee el comando, no los ficheros que ese comando ejecuta (`bash script.sh`).
7. **`pre-push`:** se salta con `--no-verify` o `core.hooksPath` cuando el guard no lo ve, y un clon nuevo no lo tiene hasta `make install-hooks`.
8. **Tiempo máximo:** si el guard supera los 10 s que le da `.claude/settings.json`, Claude Code deja pasar la orden ("A timed-out `command`, `http`, or `mcp_tool` hook doesn't block the tool call", https://code.claude.com/docs/en/hooks). La mediana medida es de 25 ms por push.

## Reversión

- La protección se quita con `gh api -X DELETE repos/Actaira/Actaira/branches/main/protection` y se vuelve a poner con el PUT del paso 0.4 (`docs/estado/branch-protection.json`). Mientras está quitada, no hay frontera.
- Volver a tratar el guard como frontera exige reabrir, en un paso propio y con sus rondas, los hallazgos de la ronda 3 del paso 0.3 (`docs/estado/E0.md`).
