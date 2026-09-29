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
- dónde se comprueba: lint:scripts/harness/secrets-scan.sh (excepciones de gitleaks) y lint:scripts/harness/check-skips.sh (`t.Skip` y restricciones de compilación en los tests). Pendiente de guardia: `//nolint` (E1, con golangci-lint), y las formas de `.gitleaks.toml` que quitan reglas aunque extiendan las de serie (`disabledRules`, `[[allowlists]]`, `extend.path`) y los comentarios allow que solo están en la historia (backlog)

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
- regla: la frontera del servidor (ADR 0000) solo exige que `check` salga en verde, y lo que ejecuta `check` lo define el propio PR. Los ficheros que lo definen (`ci.yml` y los prerrequisitos de `check` y `gate` en el Makefile) se comparan con su contenido exacto, y ningún otro workflow puede publicar un check con el mismo nombre. Un cambio legítimo, como el job de macOS de la E1, actualiza el test en el mismo PR, a la vista en el diff
- dónde se comprueba: test:scripts/harness/tests/ci_test.sh::test_workflow_is_exactly_the_reviewed_one, test:scripts/harness/tests/ci_test.sh::test_no_other_workflow_publishes_a_check_job y test:scripts/harness/tests/makefile_test.sh::test_check_runs_every_harness_check, en `make check`

## L-007 Toda orden que CLAUDE.md o una skill manda ejecutar pasa los hooks
- nace de: F-0011 y el cierre de la E0 (`CLAUDE.md` mandaba cerrar un paso con una fusión que el guard bloquea)
- regla: las órdenes de git y gh que `CLAUDE.md` y las skills dan entre comillas invertidas se ejecutan en un test contra `guard-git.sh`, en una rama de paso o, la etiqueta de cierre, en `main`; lo que solo describe lo que hace un script no va entre comillas invertidas
- dónde se comprueba: test:scripts/harness/tests/guard-git_test.sh::test_orders_in_claude_md_and_skills_pass_the_guard

## L-008 Los datos personales se buscan como los secretos, sin publicar la lista ni su hash
- nace de: F-0015
- regla: nada personal en el repo (`CLAUDE.md`, regla 4). `make check` busca correos de proveedores personales y los términos de una lista privada que vive en `~/actaira-ws/privado/`, fuera de git: publicar incluso el hash de un término corto deja comprobar adivinanzas. La CI no tiene la lista y solo busca correos; los términos se comprueban en local (`make check`, el hook de parada, `make gate`) y en `merge-pr.sh`. Un hallazgo nunca enseña el texto, porque los logs de la CI son públicos, y `main` no se vuelve a escanear, porque ahí un hallazgo sería para siempre (F-0009)
- dónde se comprueba: lint:scripts/harness/check-personal.sh, test:scripts/harness/tests/personal_test.sh y test:scripts/harness/tests/merge-pr_test.sh::test_refuses_a_squash_message_with_personal_data
