# Registro de fallos

Cada fallo encontrado (test en rojo que no era esperado, bug, hallazgo crítico o alto de una pasada adversarial, error en despliegue) se registra aquí **antes** de corregirlo, con la skill `registrar-fallo`. `scripts/harness/check-fallos.sh` corre dentro de `make check` y falla si una entrada no tiene una guardia que exista en el repo.

## Formato

```
## F-0001 Título corto
- fecha: AAAA-MM-DD
- épica y paso: E1 / 1.4
- síntoma: qué se vio (salida real, recortada)
- causa raíz: por qué pasó, no solo dónde
- corrección: qué se cambió (commit)
- guardia: test:pkg/lock/canonical_test.go::TestCanonicalNFC
- lección: la regla general que se saca (va también a LECCIONES.md si aplica a más sitios)
```

**Regla:** el test de la guardia se escribe primero, se comprueba que **falla** sin la corrección y que pasa con ella. La salida de las dos ejecuciones se pega en el PR.

## Entradas

## F-0001 post-edit.sh no formatea: los hooks heredan un PATH sin Go
- fecha: 2026-09-28
- épica y paso: E0 / 0.1 (comprobación en vivo), corregido en 0.2
- síntoma: al crear `probe.go` con Write, el hook PostToolUse devolvió `gofmt failed on .../probe.go: .../post-edit.sh: line 18: gofmt: command not found` y el fichero quedó sin formatear. El mismo PATH habría hecho fallar `make check` dentro de `stop-gate.sh` (`make: go: No such file or directory`, exit 2).
- causa raíz: los hooks heredan el entorno del proceso que lanzó Claude Code (aquí el servidor de VS Code en WSL), no el de una terminal que ha leído `~/.bashrc`. Go está instalado sin sudo en `~/.local/go`, y ese directorio solo entra en el PATH desde `~/.bashrc`. Ningún hook fijaba su propio PATH, así que dependían de cómo se hubiera arrancado el editor.
- corrección: `scripts/harness/env.sh` antepone `~/.local/go/bin` y `~/go/bin` (si existen) al PATH; `post-edit.sh`, `stop-gate.sh` y `guard-git.sh` lo cargan al empezar. `post-edit.sh` avisa de forma explícita si sigue sin encontrar `gofmt`. Rama `e0/paso-2-make-check`.
- guardia: test:scripts/harness/tests/post-edit_test.sh::test_gofmt_found_when_path_lacks_go
- guardia: test:scripts/harness/tests/stop-gate_test.sh::test_make_check_finds_go_when_path_lacks_go
- guardia: test:scripts/harness/tests/settings_test.sh::test_every_hook_script_sources_env_first
- lección: L-001

## F-0002 secrets-scan.sh escanea repos anidadas enteras, con sus ficheros ignorados
- fecha: 2026-09-28
- épica y paso: E0 / 0.2
- síntoma: con la worktree de un subagente en `.claude/worktrees/agent-x` (repo anidada, sin ignorar) y un `.env` ignorado dentro, el escaneo dio `WRN leaks found: 1`, exit 1. Ese `.env` nunca se commitearía.
- causa raíz: `git ls-files --others` lista una repo anidada (y un submódulo en `--cached`) como una entrada de directorio. El filtro `[ -e "$f" ]` la dejaba pasar y `tar` copia los directorios de forma recursiva, así que entraba todo su contenido, ignorados incluidos. Además `.claude/worktrees/` no estaba en `.gitignore`.
- corrección: solo se copian ficheros y enlaces (`-f` o `-L`), `tar --no-recursion`, y `.claude/worktrees/` en `.gitignore` (también en `install.sh`). Rama `e0/paso-2-make-check`, ronda 1.
- guardia: test:scripts/harness/tests/secrets-scan_test.sh::test_nested_repo_is_not_scanned
- lección: copiar "lo que git commitearía" exige filtrar por tipo de entrada, no solo por existencia.

## F-0003 make fallos ejecuta las guardias de shell sin el entorno de test-harness
- fecha: 2026-09-28
- épica y paso: E0 / 0.2 (pasada adversarial, ronda 1, hallazgo alto)
- síntoma: `env -u GITLEAKS bash scripts/harness/tests/secrets-scan_test.sh test_untracked_sentinel_fails` da `GITLEAKS debe apuntar al gitleaks fijado` y ninguna línea `--- PASS`. Con una guardia en ese fichero, `make check` quedaría en rojo para siempre con `no existe o no pasa`, mientras `make test-harness` da verde.
- causa raíz: el Makefile solo pasaba `GITLEAKS` en la receta de `test-harness`. `check-fallos.sh` ejecuta las mismas guardias desde otra receta, sin esa variable ni la dependencia del binario. Además `check-fallos` no enseñaba la salida de la guardia, así que el motivo quedaba oculto.
- corrección: `export GITLEAKS` en el Makefile y `fallos: $(GITLEAKS)`. `check-fallos.sh` enseña la cola de la salida de una guardia en rojo, exige exit 0 y que el nombre sea `test_*`.
- guardia: test:scripts/harness/tests/secrets-scan_test.sh::test_nested_repo_is_not_scanned
- nota de la guardia: la de F-0002 solo pasa en `make fallos` si el Makefile le exporta `GITLEAKS`, así que también guarda este fallo.
- guardia: test:scripts/harness/tests/check-fallos_test.sh::test_failing_guard_shows_its_output
- lección: una guardia se ejecuta igual en `test-harness` que en `check-fallos`: el entorno que necesita va exportado en el Makefile, no en una sola receta.

## F-0004 La caché de stop-gate.sh ignora el contenido de los ficheros sin seguir
- fecha: 2026-09-28
- épica y paso: E0 / 0.2 (pasada adversarial, ronda 1, hallazgo alto; el código es del 0.1)
- síntoma: un fichero nuevo sin `git add` (un `_test.go` en TDD) pasa `make check`; se rompe después y el hook deja terminar con `make check` en rojo, porque la clave de caché no cambia.
- causa raíz: la clave era `HEAD` más el hash de `git diff`, `git diff --cached` y los **nombres** de `git ls-files --others`. El contenido de los ficheros sin seguir no entraba. El fallo no se veía en el 0.1 porque, sin F-0001 corregido, el hook nunca llegaba a un verde que cachear.
- corrección: la clave es `HEAD` más `git write-tree` de un índice temporal con `git add -A`, que cubre el contenido exacto de todo lo que git commitearía. Si no se puede calcular, no se usa la caché.
- guardia: test:scripts/harness/tests/stop-gate_test.sh::test_untracked_file_change_invalidates_cache
- lección: una caché por estado del árbol se calcula sobre contenido, nunca sobre nombres.

## F-0005 Dos tests de la ronda 1 no podían fallar
- fecha: 2026-09-28
- épica y paso: E0 / 0.2 (pasada adversarial, ronda 2, hallazgos medios 1 y 2)
- síntoma: el revisor quitó el `unset GITLEAKS_CONFIG GITLEAKS_CONFIG_TOML` de `secrets-scan.sh` y `test_environment_cannot_replace_the_config` siguió en `--- PASS`. Cambió el escaneo del árbol a rutas absolutas (`File: /tmp/tmp.9Xhw5io8L5/new.txt`) y el test de rutas relativas también pasó.
- causa raíz: el script pasaba siempre `--config` (también con el `.gitleaks.toml` del repo), y en gitleaks `--config` gana a las variables de entorno, así que el `unset` nunca era lo que protegía. El test de rutas comparaba con el directorio temporal del test, no con el del escaneo. Por debajo: las correcciones de severidad media de la ronda 1 no se probaron en rojo quitando la corrección, solo las altas.
- corrección: sin `--config`, gitleaks descubre el `.gitleaks.toml` del repo por su ruta, y el `unset` es lo único que impide que el entorno lo sustituya. El test de rutas fija `TMPDIR` a un directorio conocido y exige la huella exacta `new.txt:actaira-test-sentinel:1`. Las dos mutaciones del revisor ponen ahora los tests en rojo (salidas en el PR #2).
- guardia: test:scripts/harness/tests/secrets-scan_test.sh::test_environment_cannot_replace_the_config
- guardia: test:scripts/harness/tests/secrets-scan_test.sh::test_untracked_sentinel_fails_with_repo_relative_path
- guardia: regla:.claude/rules/tests.md
- lección: L-002

## F-0006 Los ficheros de excepción de gitleaks apagaban el escaneo sin revisión
- fecha: 2026-09-28
- épica y paso: E0 / 0.2 (pasada adversarial, ronda 2, hallazgo medio 3)
- síntoma: un `.gitleaks.toml` sin `[extend] useDefault = true` sustituye todas las reglas por defecto, y el escaneo queda en verde con cualquier secreto. Una línea de `.gitleaksignore` o un comentario allow en línea de gitleaks ocultan un hallazgo. Nada lo comprobaba.
- causa raíz: `secrets-scan.sh` trataba los mecanismos de excepción de gitleaks como entrada de confianza, y `check-weakeners.sh` solo mira el Makefile, los workflows y los scripts del proyecto.
- corrección: `.gitleaks.toml` y `.gitleaksignore` tienen que estar en git; `.gitleaks.toml` tiene que extender las reglas por defecto; cada entrada de `.gitleaksignore` lleva encima un comentario con un `F-NNNN` que exista en FALLOS.md, y cada comentario allow en línea cita en la misma línea un `F-NNNN` que exista. Si no, `make check` falla.
- guardia: test:scripts/harness/tests/secrets-scan_test.sh::test_repo_config_without_default_rules_fails
- guardia: test:scripts/harness/tests/secrets-scan_test.sh::test_gitleaksignore_entry_without_fallo_fails
- guardia: test:scripts/harness/tests/secrets-scan_test.sh::test_allow_comment_without_fallo_fails
- lección: L-003

## F-0007 guard-git.sh dejaba pasar pushes a main escritos con sintaxis de shell
- fecha: 2026-09-28
- épica y paso: E0 / 0.3
- síntoma: con la rama `e0/paso-2-x`, el hook salió con 0 (no bloqueó) para `git push origin 'main'`, `git push origin "main"`, `git push origin main;`, `git push origin main&& echo ok`, `git push -uf origin x` y `git push -fu origin x`.
- causa raíz: el hook buscaba `main` y `-f` con una expresión regular sobre el texto crudo, que exigía palabras separadas por espacios. La sintaxis de shell (comillas, `\`, operadores `;` `&&` `|`, `$( )`, grupos de opciones cortas como `-uf`) cambia el texto sin cambiar lo que git recibe. Tampoco miraba `--all` ni `--mirror`, que también suben `main`.
- corrección: el hook quita las comillas y las barras, parte el comando en órdenes simples por los operadores, y en cada orden que tiene `git` seguido de `push` revisa los argumentos: `--force*`, `--no-verify`, `--all`, `--mirror`, grupos cortos con `f`, refspecs con `+` y cualquier destino `main`, `*:main` o `*/main`. Es conservador a propósito: un falso positivo solo obliga a reescribir el comando.
- guardia: test:scripts/harness/tests/guard-git_test.sh::test_blocks_quoted_or_chained_main
- lección: un hook que protege comandos de shell compara palabras ya separadas y sin comillas, nunca el texto crudo con una expresión regular.

## F-0008 La evidencia de mutación de settings.json salió en rojo por otro motivo y dejó ficheros en el repo
- fecha: 2026-09-28
- épica y paso: E0 / 0.3
- síntoma: en `evals/sessions/2026-09-28-e0-paso-3-mutaciones.txt` las ocho ejecuciones de settings dieron `jq: error: Could not open file evals/sessions/settings.mut.json` (también la copia sin mutar), y `settings.mut.json` y `settings.ok.json` entraron en el commit `c6bb97c`.
- causa raíz: el script de mutación guardaba sus copias en `dirname $0`, que al copiarlo a `evals/sessions/` pasó a ser el repo, con ruta relativa; y `settings_test.sh` usaba `SETTINGS_FILE` tal cual, aunque cada test se ejecuta en su propio directorio temporal. El script no validaba su propio resultado, así que un rojo por error pasó por un rojo por mutación.
- corrección: `settings_test.sh` convierte `SETTINGS_FILE` en ruta absoluta; el script de mutación trabaja en un `mktemp -d`, comprueba rojo con la mutación y verde sin ella, y sale con 1 si alguna falla; los dos JSON se borran del repo y la evidencia se rehace. En el paso 0.4 (ronda 2, que encontró lo mismo con `CI_FILE` y `PROTECTION_FILE` en `ci_test.sh`), las variables desaparecen: los tests usan rutas fijas del repo, las pruebas de mutación trabajan sobre una copia del árbol entero, y la guardia pasa a ser un test que falla si algún test toma del entorno el fichero que comprueba.
- guardia: test:scripts/harness/tests/lib_test.sh::test_no_test_takes_its_target_from_the_environment
- guardia: regla:.claude/rules/tests.md
- lección: un script que genera evidencia escribe sus temporales en `mktemp` y valida su propio resultado antes de guardarlo.

## F-0009 El control de atribución podía dejar main en rojo para siempre
- fecha: 2026-09-28
- épica y paso: E0 / 0.3 (pasada adversarial, ronda 1, hallazgo crítico)
- síntoma: en un sandbox del revisor, un squash en `main` cuyo cuerpo citaba la línea "Generated with Claude Code" dejó `check-attribution: commits con atribución de Claude ...: 1ae1305 E0 step 0.3 ...`, exit 1, también en una rama limpia posterior. Y `--message` rechazaba texto normal del producto: "Parse .mcp.json files generated with claude mcp add".
- causa raíz: el control recorría toda la historia alcanzable desde HEAD, sin excepciones posibles, y su patrón (`generated with .*claude`) era mucho más ancho que las formas reales de atribución. El cuerpo del squash lo escribe GitHub en el momento de fusionar, y ni el hook `commit-msg` ni la CI lo ven antes de que entre en `main`.
- corrección: el patrón se limita a las formas reales (trailer `Co-authored-by` que nombra a Claude o Anthropic, cualquier trailer con `noreply@anthropic.com`, la línea `Generated with [Claude Code]`) y a la identidad de autor o committer; `make check` revisa solo `origin/main..HEAD` y falla en un clon superficial; `scripts/harness/merge-pr.sh` valida título, cuerpo del PR y mensaje del squash antes de fusionar, con `--match-head-commit`.
- guardia: test:scripts/harness/tests/attribution_test.sh::test_attribution_already_in_main_does_not_block_branches
- guardia: test:scripts/harness/tests/attribution_test.sh::test_product_text_mentioning_claude_passes
- guardia: test:scripts/harness/tests/merge-pr_test.sh::test_refuses_a_squash_message_with_attribution
- lección: un control que no admite excepciones solo revisa lo que todavía se puede corregir (la rama), y lo que entra en `main` sin pasar por la CI se valida antes de fusionar.

## F-0010 guard-git.sh no veía un push partido con una continuación de línea
- fecha: 2026-09-28
- épica y paso: E0 / 0.3 (pasada adversarial, ronda 1, hallazgo alto)
- síntoma: en vivo, con el hook de la sesión, `git -C <sandbox>/repo push \` + salto de línea + `--no-verify origin main` pasó, el `pre-push` no se ejecutó y el remoto del sandbox quedó en `79a44a1..37fd005  main -> main`.
- causa raíz: el hook borraba las barras y después partía por líneas, así que veía dos órdenes inocuas; bash une `\` + salto de línea antes de ejecutar.
- corrección: el hook une las continuaciones antes de nada, como bash.
- guardia: test:scripts/harness/tests/guard-git_test.sh::test_blocks_line_continuations
- lección: L-004

## F-0011 guard-git.sh bloqueaba la etiqueta de cierre de épica
- fecha: 2026-09-28
- épica y paso: E0 / 0.3 (pasada adversarial, ronda 1, hallazgo alto; el conflicto viene del harness del 0.1)
- síntoma: con el proyecto en `main`, la orden del cierre (`git switch main && git pull --ff-only && git tag e0-cerrada && git push origin e0-cerrada`) salía con 2, aunque `.claude/settings.json` permite `Bash(git push origin e*-cerrada)` y la skill `cierre-epica` la manda ejecutar.
- causa raíz: la regla "ningún push desde main" no distinguía entre mover `main` y subir una etiqueta, y nada probaba la orden del cierre contra el guard.
- corrección: desde `main` se permite solo `git push <remoto> e<N>-cerrada` (sin opciones y sin más refspecs); cualquier otra cosa sigue bloqueada.
- guardia: test:scripts/harness/tests/guard-git_test.sh::test_allows_only_the_closing_tag_from_main
- guardia: test:scripts/harness/tests/guard-git_test.sh::test_orders_in_claude_md_and_skills_pass_the_guard
- lección: L-007; toda orden que una skill manda ejecutar tiene un test contra los hooks que la van a revisar.

## F-0012 settings_test.sh daba rojo sin motivo al crecer guard-git.sh
- fecha: 2026-09-28
- épica y paso: E0 / 0.3 (al cubrir con el hook la herramienta Monitor)
- síntoma: `--- FAIL: test_every_hook_script_sources_env_first` sin ninguna aserción en la salida, en cuanto `guard-git.sh` pasó de unos 4 KB.
- causa raíz: el test hacía `grep -vE ... "$fichero" | head -n 2` dentro de `$(...)` con `set -e` y `pipefail`. Con un fichero grande, `head` sale tras dos líneas, `grep` recibe SIGPIPE al seguir escribiendo y el pipeline devuelve 141: un rojo falso. Es el patrón de L-000e, que solo tenía guardia en `check-fallos.sh`, no en el resto de scripts del harness.
- corrección: el test lee las líneas con here-strings, sin tubería; `scripts/harness/check-pipes.sh` (dentro de `make check`) rechaza cualquier tubería hacia `head` o `grep -q/-m/-l` en los scripts, los hooks de git y el Makefile.
- guardia: lint:scripts/harness/check-pipes.sh
- guardia: test:scripts/harness/tests/check-pipes_test.sh::test_pipe_into_head_fails
- lección: L-000e (ahora con guardia automática en todo el harness)

## F-0013 Un valor entre comillas en una opción global de git ocultaba el push al guard
- fecha: 2026-09-28
- épica y paso: E0 / 0.3 (pasada adversarial, ronda 2, hallazgo alto)
- síntoma: en un sandbox del revisor, la misma orden de push con `--no-verify` hacia main salía con 2 si el valor de `-c` no llevaba espacios y con 0 si los llevaba (`-c "user.name=a b"`); git recibe ese valor como un solo argumento.
- causa raíz: el guard quitaba las comillas y partía por espacios y operadores sin respetarlas, así que un espacio o un `;` dentro de un valor citado de `-c`, `-C` o `--git-dir` desplazaba la palabra que tomaba como subcomando, y los argumentos del push no se revisaban.
- corrección: además de la lectura aplanada (que sigue viendo `sh -c '...'`), el guard tokeniza el comando respetando las comillas (`shlex` de python, modo POSIX) cuando hay un push, y aplica las mismas reglas a esa lectura; si no puede tokenizarlo, bloquea.
- guardia: test:scripts/harness/tests/guard-git_test.sh::test_blocks_quoted_values_in_global_options
- lección: L-004

## F-0014 El check obligatorio podía salir en verde sin ejecutar make check
- fecha: 2026-09-28
- épica y paso: E0 / 0.4 (pasada adversarial, ronda 1, hallazgos 1, 3 y 4)
- síntoma: en un sandbox del revisor, con un `if:` en el job `check` de `ci.yml` (por ejemplo `if: github.event.pull_request.draft == false`), un paso con `if: false`, `continue-on-error: ${{ true }}`, `shell: bash -c true {0}` o un paso previo que escribe un `GNUmakefile`, `ci_test.sh` y `check-weakeners.sh` seguían en verde. GitHub da por bueno un job saltado aunque su check sea obligatorio ("A job that is skipped will report its status as "Success". It will not prevent a pull request from merging, even if it is a required check.", https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-jobs-with-conditions). Lo mismo con otro workflow que tuviera un job `check`, y con un `check:` del Makefile sin `test-harness` ni `secrets`: `make check` imprimía `check: OK` con 0 tests del harness.
- causa raíz: los tests de la CI comprobaban que estuvieran las líneas buenas, no que no hubiera nada más. Y lo que significa `check` en verde lo define el propio PR (`ci.yml` y el objetivo `check` del Makefile), que ningún test fijaba, mientras que la frontera del servidor (ADR 0000) solo exige que `check` esté en verde.
- corrección: `ci.yml` se compara línea a línea con el contenido revisado; ningún otro workflow puede tener un job `check`; las acciones de todos los workflows van fijadas por SHA, también en estilo flujo; los prerrequisitos de `check` y `gate` quedan fijados; `check-weakeners.sh` rechaza cualquier `continue-on-error`. Rama `e0/paso-4-ci-proteccion`.
- guardia: test:scripts/harness/tests/ci_test.sh::test_workflow_is_exactly_the_reviewed_one
- guardia: test:scripts/harness/tests/ci_test.sh::test_no_other_workflow_publishes_a_check_job
- guardia: test:scripts/harness/tests/makefile_test.sh::test_check_runs_every_harness_check
- guardia: test:scripts/harness/tests/check-weakeners_test.sh::test_continue_on_error_with_expression_fails
- lección: L-006

## F-0015 Datos personales de Marcos en el repo público
- fecha: 2026-09-29
- épica y paso: E0 / cierre (revisión de seguridad de conjunto, ronda 1, hallazgo alto)
- síntoma: `docs/PLAN.md` y las épicas E3 y E4, copiados del paquete en el paso 0.1, contenían datos personales de Marcos (situación laboral, planes personales, gestoría, el nombre de su cuenta personal y la mención de su correo); un test del harness usaba su nombre completo como coautor de ejemplo, y los commits de las ramas llevaban su identidad de git. El repo es público desde el paso 0.1.
- causa raíz: nada buscaba datos personales: el escaneo de secretos busca credenciales, no datos de una persona; `install.sh` copió el plan tal cual; y ninguna regla decía que el repo no puede llevar nada personal.
- corrección: regla 4 de `CLAUDE.md` (nada personal en el repo); `scripts/harness/check-personal.sh` en `make check`, que busca correos de proveedores personales y los términos de una lista privada que vive fuera de git (publicar incluso su hash dejaría comprobar adivinanzas), en los ficheros, sus nombres, el índice y los commits de la rama, nunca otra vez en `main` (F-0009), y que `merge-pr.sh` pasa también por el mensaje del squash y el texto del PR; la CI no tiene la lista privada y solo busca correos; documentos nuevos del paquete sin esos datos, con tres restos neutralizados; un nombre ficticio en el test; y, por decisión de Marcos, el repo recreado con un único commit con autor Actaira (noreply), con la historia antigua guardada en `~/actaira-ws/privado/`. GitHub firma cada fusión y el commit de prueba de cada PR con el correo principal de la cuenta, que es de un proveedor personal: Marcos activa el correo privado de la cuenta Actaira antes de recrear el repo, y `merge-pr.sh` fusiona con el correo noreply de la cuenta y comprueba después el autor del commit que entró en `main`.
- guardia: lint:scripts/harness/check-personal.sh
- guardia: test:scripts/harness/tests/personal_test.sh::test_term_in_a_tracked_file_fails_without_printing_it
- guardia: test:scripts/harness/tests/personal_test.sh::test_commit_message_and_identity_fail
- guardia: test:scripts/harness/tests/personal_test.sh::test_term_only_in_the_index_or_in_an_earlier_commit_fails
- guardia: test:scripts/harness/tests/personal_test.sh::test_only_the_commits_of_the_branch_are_scanned
- guardia: test:scripts/harness/tests/personal_test.sh::test_default_private_list_is_used
- guardia: test:scripts/harness/tests/merge-pr_test.sh::test_refuses_a_squash_message_with_personal_data
- guardia: test:scripts/harness/tests/merge-pr_test.sh::test_checks_the_author_of_the_commit_that_entered_main
- lección: L-008

## F-0016 Los permisos dejaban traer y ejecutar el código de un PR ajeno sin preguntar
- fecha: 2026-09-29
- épica y paso: E0 / cierre (revisión de seguridad de conjunto, ronda 1, hallazgo alto)
- síntoma: `.claude/settings.json` permitía sin preguntar `gh pr *`, que incluye `gh pr checkout`, y `git fetch *`. Los tres hooks ejecutan los scripts del árbol de trabajo, así que el `guard-git.sh`, el `env.sh` y el `make check` de un PR hostil correrían en esta máquina, donde `gh` guarda los tokens en claro, entre ellos el de la cuenta dueña del repo.
- causa raíz: los permisos se escribieron pensando en los PR propios; nada trataba el código de un PR de un repo público como código no confiable, y las denegaciones cubrían los ficheros de secretos del proyecto pero no los almacenes de credenciales del sistema.
- corrección: denegados `gh pr checkout` y su alias `gh co`, `git fetch` y `git pull` de cualquier ref `pull/` (también `refs/pull/` y `+pull/`), `gh auth status` y la lectura de `~/.config/gh`, `~/.ssh` y `~/.azure`; `gh pr` queda permitido sin preguntar solo para `create`, `view`, `checks` y `diff` (decisión de Marcos del 2026-09-29). Un PR ajeno se revisa con `gh pr diff` y `gh pr view`. Siguen sin denegar un `git fetch` de la URL de un fork, `bash -c` y una ruta absoluta al binario: las reglas de permisos no son una frontera (https://code.claude.com/docs/en/permissions), como el guard (ADR 0000).
- guardia: test:scripts/harness/tests/settings_test.sh::test_settings_keep_foreign_pr_code_and_credentials_out
- lección: un PR ajeno es código no confiable: se lee, no se trae al árbol de trabajo, porque los hooks ejecutan ese árbol.

## F-0017 La vista de cobertura daba números y estados sin haber visto lo que podía cambiarlos
- fecha: 2026-09-29
- épica y paso: E1 / 0 (vista de cobertura, solo documentación), rondas adversariales 1 y 2
- síntoma: la especificación de `docs/cobertura.md` tenía siete hallazgos altos.
  - "Efectivas no usadas" daba número con tools de efecto desconocido, servidores MCP sin listar o partes sin ver.
  - "Mediadas" tomaba el valor más fuerte de una capacidad y, sin nada que vea las llamadas no mediadas, se cumplía por construcción.
  - Una instantánea pública del registro dejaba `observed` una fuente MCP.
  - Un agente con credenciales conocidas salía "1 de 1", y los ejes sin fuente se omitían.
  - Al alinear con el plan, `mediated` pasó a exigir credencial intermediada, que en el plan es otro campo (`credential_brokered`).
- causa raíz: las definiciones se escribieron desde lo que cada fuente dice, no desde lo que falta para poder decirlo. Ningún contador listaba antes qué podía cambiar su número, así que una parte sin ver acababa contada como vista. Es la doctrina "nunca inferir lo no observado" de `CLAUDE.md` sin aplicar a los contadores.
- corrección:
  - un contador solo da número si se ha visto todo lo que podría cambiarlo; si no, dice qué falta ("sin fuente", "uso desconocido", "llamadas no mediadas: sin fuente");
  - una fuente MCP solo pasa a `observed` con el listado que ve el agente;
  - cada variable de entorno referenciada es una fuente;
  - `mediated` vuelve a ser el del plan, y basta una llamada no mediada para no contar.
  - Cada punto tiene su test con nombre en `docs/cobertura.md`, que la épica que lo construye escribe en rojo antes de construir. Rama `e1/paso-0-cobertura`.
- guardia: regla:.claude/rules/cobertura.md
- lección: L-009

## F-0018 El lockfile dependía de ficheros que git no versiona
- fecha: 2026-09-29
- épica y paso: E1 / 0 (vista de cobertura, solo documentación), rondas adversariales 1, 2 y 3
- síntoma: `coverage.skipped` anotaba los directorios ignorados que hubiera en disco (`node_modules`, `.venv`). Además, el recorrido de la E1 no respetaba `.gitignore` y entraba en repos anidados, como `.claude/worktrees/` en este mismo repo. Un `actaira lock` en local y un `actaira lock --check` en la CI, sobre un clon limpio, darían ficheros distintos.
- causa raíz: el determinismo se especificó como "el mismo fichero en 10 ejecuciones sobre el mismo árbol". Ese test no puede ver la diferencia entre el árbol de un desarrollador y el checkout de la CI, que es donde se compara.
- corrección:
  - La ronda 3 mostró que el mecanismo propuesto en la ronda 2 tampoco bastaba. Respetar `.gitignore` no es leer lo que git versiona: un submódulo sin inicializar en la CI o un fichero excluido solo en local cambian el lockfile. Además, lo versionado que no se lee no dejaba rastro.
  - Por decisión de Marcos (opción B), la documentación fija solo la regla: todo lo versionado que un extractor leería se lee o deja una entrada con su motivo, y lo no versionado no deja ninguna.
  - El mecanismo lo decide y lo prueba el paso 1.4 de la E1, con cinco tests obligatorios: el índice de git, los submódulos, los enlaces simbólicos, los ficheros ignorados solo en local y la regla misma.
  - Rama `e1/paso-0-cobertura`.
- guardia: regla:.claude/rules/go.md
- guardia: regla:.claude/rules/cobertura.md
- lección: L-010
