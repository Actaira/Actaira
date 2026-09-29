# Lecciones

Reglas generales que salen de los fallos. Claude Code lee este fichero **al empezar cada paso**. Cada lección apunta al fallo del que nace y a dónde se ha convertido en norma: una regla de `.claude/rules/`, una comprobación de `make check` o un hook.

Una lección que no se ha convertido en algo que se comprueba solo sigue siendo un riesgo, y se marca como `pendiente de guardia`.

## Formato

```
## L-001 Título
- nace de: F-0003, F-0007
- regla: enunciado corto y comprobable
- dónde se comprueba: .claude/rules/go.md, o lint:scripts/harness/check-xyz.sh
```

## Lecciones heredadas (de proyectos anteriores de Marcos, ya convertidas en norma)

## L-000a Una sesión real encuentra lo que los tests no ven
- nace de: seamark, fase 1 (una sesión de tres llamadas encontró cuatro bugs que 1.905 tests no vieron)
- regla: cada paso con comportamiento visible termina con una ejecución real guardada en `evals/sessions/`
- dónde se comprueba: skill `epica`, paso 7

## L-000b Los debilitadores de la CI no pasan
- nace de: Actaira orden 00 (un `-` en una receta y un filtro en `addopts` dejaban la CI en verde con tests fallando)
- regla: ni `|| true`, ni prefijos `-`, ni `-k`, ni `continue-on-error`, ni filtros de tests
- dónde se comprueba: lint:scripts/harness/check-weakeners.sh

## L-000c El bucle de autoauditoría no produce producto
- nace de: Actaira, julio de 2026 (3,4 M de tokens de revisión y cero líneas de producto)
- regla: como mucho 3 rondas adversariales por paso; una ronda solo produce correcciones o líneas de backlog, nunca documentos de decisión en cadena
- dónde se comprueba: skill `pasada-adversarial` y `scripts/harness/stop-gate.sh`

## L-000d Un presupuesto que solo vive en el chat no existe
- nace de: seamark, fase 0.1
- regla: toda ampliación de alcance se escribe en el mensaje del commit o en `docs/estado/`
- dónde se comprueba: skill `cierre-epica`

## L-000e Con `pipefail`, `cmd | grep -q` da falso rojo
- nace de: la prueba del propio harness v3 (check-fallos marcaba como fallido un test Go que pasaba)
- regla: en scripts con `set -o pipefail`, se captura la salida en una variable y luego se hace `grep`; nunca `cmd | grep -q`
- dónde se comprueba: test de `check-fallos.sh` con un test Go que pasa, en `make test-harness`; y lint:scripts/harness/check-pipes.sh en todos los scripts del harness, los hooks de git y el Makefile (F-0012)

## Lecciones de Actaira

## L-001 Un hook no hereda el PATH de la terminal
- nace de: F-0001
- regla: todo script de hook de `.claude/settings.json` carga `scripts/harness/env.sh` antes de nada, y ningún hook depende de que `~/.bashrc` se haya leído
- dónde se comprueba: test:scripts/harness/tests/settings_test.sh::test_every_hook_script_sources_env_first, en `make test-harness`

## L-002 Un test se da por bueno cuando se ha visto en rojo sin la corrección
- nace de: F-0005
- regla: todo test nuevo o corregido, de cualquier severidad, se ejecuta con la corrección quitada (mutación) y tiene que salir en rojo; la salida va al PR
- dónde se comprueba: regla:.claude/rules/tests.md (pendiente de guardia automática: no hay pruebas de mutación en `make check`)

## L-003 Toda excepción que apaga una comprobación cita una entrada de FALLOS.md
- nace de: F-0006
- regla: un mecanismo que apaga una comprobación (ficheros de excepción de gitleaks, comentarios allow, `t.Skip`, `//nolint`, configuraciones que quitan reglas) solo vale si está en git y cita un `F-NNNN` que exista en FALLOS.md
- dónde se comprueba: lint:scripts/harness/secrets-scan.sh (excepciones de gitleaks) y lint:scripts/harness/check-skips.sh (`t.Skip`, restricciones de compilación en los tests y, desde el paso 1.1 de la E1, `//nolint` en todas sus formas, F-0020, con una lista blanca de lo que la vista de git esconde, F-0021); golangci-lint con nolintlint y sin excluir los ficheros generados, con `.golangci.yml` fijado por `makefile_test.sh::test_golangci_config_is_the_reviewed_one`. Pendiente de guardia: las formas de `.gitleaks.toml` que quitan reglas aunque extiendan las de serie (`disabledRules`, `[[allowlists]]`, `extend.path`) y los comentarios allow que solo están en la historia (backlog). El correo de contacto que permite `check-personal.sh` no cita un F-NNNN sino la decisión de Marcos del 2026-09-29, y está en git (`config/contact.env`) con su contenido fijado por `personal_test.sh::test_contact_config_is_the_reviewed_one`

## L-004 Un hook de shell lee palabras de órdenes simples, y ante lo que no puede evaluar, bloquea
- nace de: F-0007, F-0010, F-0013
- regla: un hook que protege comandos une continuaciones, lee el comando dos veces (aplanado, para ver lo que va entre comillas, y tokenizado respetando las comillas, para no desplazar el subcomando), parte en órdenes simples por los operadores y busca el subcomando real; si el comando expande texto (`$`, backticks, llaves), define funciones o alias, o lo alimenta `xargs`, bloquea en vez de adivinar
- dónde se comprueba: test:scripts/harness/tests/guard-git_test.sh

## L-005 No pelear contra el parseo de shell: los controles que importan van en el servidor
- nace de: F-0007, F-0010, F-0013 y la ronda 3 del paso 0.3 (órdenes anidadas y estado en `.git/config`); decisión de Marcos del 2026-09-28, ADR 0000
- regla: un hook local que lee el texto de un comando es una red best-effort contra errores accidentales, no una frontera. No se amplía para perseguir variantes de parseo de shell: una variante nueva se anota en los límites conocidos del ADR 0000. Lo que tiene que aguantar un error o un rodeo va en el servidor: `main` solo cambia por PR, con el check `check` en verde y `enforce_admins`. Acota L-004
- dónde se comprueba: test:scripts/harness/tests/ci_test.sh::test_branch_protection_requires_pr_check_and_binds_admins (lo que se pide al servidor), test:scripts/harness/tests/check-protection_test.sh (la comparación con lo que hay puesto) y scripts/harness/check-protection.sh contra GitHub en el paso 0.4 de la E0 y en cada cierre de épica (skill `cierre-epica`, punto 1)

## L-006 Lo que significa `check` en verde se fija con tests exactos
- nace de: F-0014
- regla: la frontera del servidor (ADR 0000) solo exige que `check` salga en verde, y lo que ejecuta `check` lo define el propio PR. Los ficheros que lo definen (`ci.yml`, los prerrequisitos de `check` y `gate` en el Makefile y, desde el paso 1.1 de la E1, `.golangci.yml`) se comparan con su contenido exacto, y ningún otro workflow puede publicar un check con el mismo nombre. Un cambio legítimo, como el job de macOS de la E1, actualiza el test en el mismo PR, a la vista en el diff
- dónde se comprueba: test:scripts/harness/tests/ci_test.sh::test_workflow_is_exactly_the_reviewed_one, test:scripts/harness/tests/ci_test.sh::test_no_other_workflow_publishes_a_check_job, test:scripts/harness/tests/makefile_test.sh::test_check_runs_every_harness_check, test:scripts/harness/tests/makefile_test.sh::test_golangci_config_is_the_reviewed_one y test:scripts/harness/tests/makefile_test.sh::test_lint_runs_golangci_lint_with_the_repo_config (solo cuenta `.golangci.yml`), en `make check`

## L-007 Toda orden que CLAUDE.md o una skill manda ejecutar pasa los hooks
- nace de: F-0011 y el cierre de la E0 (`CLAUDE.md` mandaba cerrar un paso con una fusión que el guard bloquea)
- regla: las órdenes de git y gh que `CLAUDE.md` y las skills dan entre comillas invertidas se ejecutan en un test contra `guard-git.sh`, en una rama de paso o, la etiqueta de cierre, en `main`; lo que solo describe lo que hace un script no va entre comillas invertidas
- dónde se comprueba: test:scripts/harness/tests/guard-git_test.sh::test_orders_in_claude_md_and_skills_pass_the_guard

## L-008 Los datos personales se buscan como los secretos, sin publicar la lista ni su hash
- nace de: F-0015
- regla: nada personal en el repo (`CLAUDE.md`, regla 4). `make check` busca correos de proveedores personales y los términos de una lista privada que vive en `~/actaira-ws/privado/`, fuera de git: publicar incluso el hash de un término corto deja comprobar adivinanzas. La CI no tiene la lista y solo busca correos; los términos se comprueban en local (`make check`, el hook de parada, `make gate`) y en `merge-pr.sh`. Un hallazgo nunca enseña el texto, porque los logs de la CI son públicos, y `main` no se vuelve a escanear, porque ahí un hallazgo sería para siempre (F-0009). El correo de contacto del proyecto, el de `config/contact.env`, se permite fuera de los ficheros de código (decisión de Marcos del 2026-09-29)
- dónde se comprueba: lint:scripts/harness/check-personal.sh, test:scripts/harness/tests/personal_test.sh (el correo de contacto, en `test_project_contact_email_passes_outside_code`, `test_other_personal_email_fails_next_to_the_contact_email`, `test_contact_email_fixed_in_code_fails` y `test_contact_email_without_its_config_fails`) y test:scripts/harness/tests/merge-pr_test.sh::test_refuses_a_squash_message_with_personal_data

## L-009 Un contador solo da número si se ha visto todo lo que podría cambiarlo
- nace de: F-0017
- regla: es la doctrina "nunca inferir lo no observado" de `CLAUDE.md`, aplicada a los contadores. Antes de dar un número o un estado se lista lo que podría cambiarlo: fuentes, partes saltadas, entradas `unresolved`, llamadas que nada ve. Si algo de eso no está observado, se dice qué falta en vez del número
- dónde se comprueba: regla:.claude/rules/cobertura.md (pendiente de guardia automática: los tests con nombre de `docs/cobertura.md`, que escribe cada épica)

## L-010 Un fichero generado que la CI comprueba se prueba contra el árbol de la CI
- nace de: F-0018
- regla: un fichero que se genera, se commitea y la CI vuelve a comprobar (`actaira.lock`, salidas doradas) solo depende de lo que git versiona. Sus tests comparan el lockfile de un clon limpio con el de un árbol con submódulos inicializados, ficheros sin seguimiento o excluidos solo en local, no solo varias ejecuciones sobre el mismo árbol
- dónde se comprueba: regla:.claude/rules/go.md (pendiente de guardia automática: los tests obligatorios del paso 1.4 de la E1)

## L-011 Un paso de solo documentación tiene una ronda adversarial
- nace de: el paso 0 de la E1, que dio tres rondas y 60 hallazgos sobre una especificación sin código y paró con dos altos abiertos; decisión de Marcos del 2026-09-29. Acota L-000c
- regla: un paso cuyo diff no toca código, scripts, tests ni configuración que se ejecute tiene como mucho una ronda adversarial. Los críticos se corrigen en el paso; los altos, medios y bajos van a `docs/BACKLOG.md` o al paso de código que los implementa, escritos en su épica. Las tres rondas quedan para los pasos con código y los cierres
- dónde se comprueba: `CLAUDE.md` (anti-bucle) y skill `pasada-adversarial`, punto 3 (pendiente de guardia automática)

## L-012 Una guardia que imita la sintaxis de una herramienta se prueba contra la herramienta
- nace de: F-0020
- regla: si una comprobación decide qué acepta otra herramienta (qué comentario apaga un linter, qué excepción lee gitleaks, qué etiqueta de compilación ve Go), su test ejecuta esa herramienta sobre cada variante y exige que la comprobación rechace todo lo que la herramienta aplica. No vale solo la sintaxis documentada. Cada parte de la comprobación se prueba por separado: si una variante ya falla por otro motivo (la falta de cita), no prueba la parte que mira la forma
- dónde se comprueba: test:scripts/harness/tests/check-skips_test.sh::test_every_nolint_form_that_golangci_lint_applies_is_flagged. Pendiente de guardia: los comentarios allow de gitleaks (backlog)

## L-013 La severidad de lo que esquiva una guardia local depende de si puede pasar por accidente
- nace de: F-0020, F-0021 y las tres rondas del paso 1.1 de la E1, dedicadas casi enteras a variantes construidas a propósito contra `check-skips.sh`; decisión de Marcos del 2026-09-29. Generaliza L-005
- regla: las guardias locales del harness (`guard-git`, `check-skips`, `check-weakeners`, `check-personal` y similares) son redes contra errores accidentales (ADR 0000, decisión 6). Un hallazgo que exige colocar a propósito un fichero, un enlace, una directiva o una orden que se ve en el diff del PR es como mucho bajo y va al backlog; no bloquea el paso. Alto o crítico, solo si puede pasar por accidente, rompe el producto, filtra datos o secretos, o engaña a un usuario de Actaira. En un paso de producto, las rondas son para el código del producto, y el harness solo se revisa si el paso lo cambia
- dónde se comprueba: agente `revisor-adversarial` (severidad), skill `pasada-adversarial` (puntos 1 y 2) y ADR 0000 (decisión 6). Pendiente de guardia automática
