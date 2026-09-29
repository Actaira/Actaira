# Vista de cobertura por agente

Qué sabe Actaira de cada agente y qué no. Lo pidió Marcos el 2026-09-29, antes del paso 1.1 de la E1. Este documento fija las definiciones. **Todavía no hay nada construido:** cada parte llegará con su épica y con el test que la fija, escrito en rojo antes de construirla (tabla final). Las invariantes que ningún cambio puede romper están también en `.claude/rules/cobertura.md`.

La vista tiene **dos partes separadas**, que nunca se combinan en una cifra:

1. **Capacidades:** qué puede hacer el agente, contado en ejes independientes.
2. **Fuentes:** de dónde lo sabe Actaira, cada una con su estado y motivo.

## Doctrina

1. **Nunca un porcentaje global ni un check verde de conjunto.** El resumen es "N de M fuentes conocidas observadas" más la lista de lo no visto.
2. **Los ejes de capacidades no son un embudo.**
   - Cada eje cuenta sobre su propia base y ninguno se divide por otro.
   - Lo efectivo puede superar a lo detectado: una credencial puede permitir más de lo que usa el código.
3. **`unseen` y `unresolved` nunca se mezclan.**
   - **`unseen`** es lo no mirado: una fuente sin observar, o una parte de una fuente que se saltó.
   - **`unresolved`** es lo mirado y no entendido.
   - Un elemento está en una lista o en la otra, nunca en las dos.
   - Si la declaración de una fuente no se entiende (un servidor MCP construido con `params=load()`), cuenta solo como `unresolved` y no crea una fuente. El resumen lo dice: "K declaraciones de fuente sin resolver", con sus ubicaciones.
4. **Un contador solo da número si se ha visto todo lo que podría cambiarlo.**
   - Si no, dice qué falta: "sin fuente", "uso desconocido" o "llamadas no mediadas: sin fuente".
   - Un eje sin fuente observada no vale 0 ni desaparece.
   - Un 0 solo significa que se miró y no hay. Si hay ubicaciones `unresolved` que podrían esconder más, el eje lo dice al lado: "0, más lo que haya detrás de 2 ubicaciones `unresolved`".
   - Solo alimenta los ejes lo que sale de fuentes `observed`. Lo que viene de una fuente con error o caducada sale en lo no visto, con su último valor y su fecha.
5. **M solo cuenta las fuentes que Actaira conoce.** Por eso el resumen dice "conocidas", y los límites conocidos se escriben junto al contador al que afectan.
6. **Cada contador tiene una definición exacta y un test que la fija** (tablas de abajo).
   - Además, dos tests recorren todas las salidas de la vista: uno falla si alguna enseña un porcentaje de cobertura, y otro si alguna da un veredicto de conjunto ("cubierto", "OK", un check verde).
   - Cada épica que añade una salida la mete en esos dos tests, también la consola (E3) y el paquete de auditoría (E7), que están en otro repo.
7. **Las proporciones con intervalo de Wilson de `evals/results/` no entran en esta vista.** Son el recall del extractor o los efectos confirmados, y miden a Actaira, no la cobertura de un agente.

## Parte 1: capacidades (ejes independientes)

| Eje | Definición exacta | Unidad | Llega en | Test que la fija |
|---|---|---|---|---|
| **detectadas** (`detected`) | Tools distintas, por `id`, que un extractor encontró para el agente en una fuente observada. Varias referencias al mismo `id` cuentan una vez. Las tools de la instantánea pública de un servidor MCP no cuentan: salen aparte, como "tools de la instantánea pública", con su capacidad potencial como cualquier otra. | tool | E1 | `TestCoverageDetectedCountsEachToolOnce` |
| **resueltas** (`resolved`) | Detectadas cuyo nombre, `schema_hash` y `description_hash` se calculan con lo que está escrito en el repo. El hash es el de la representación normalizada que da el extractor: parámetros, tipos y descripción tal como están escritos, más la definición de cada tipo o esquema al que remiten (un zod de otro módulo, un modelo Pydantic). No es el esquema que un SDK genera en ejecución. Si algo de eso no se puede leer sin ejecutar, la tool queda detectada y sin resolver. | tool | E1 | `TestCoverageResolvedNeedsTheWholeDefinition`, `TestCoverageResolvedFollowsSchemasDefinedElsewhereInTheRepo` |
| **`unresolved`** | Entradas con fichero, línea y columna de una fuente observada que el extractor leyó y no entendió. Son construcciones de agente, tool o servidor MCP que no se resuelven sin ejecutar (listas construidas en ejecución, fábricas, `**kwargs`, un esquema calculado), o que cubre un nodo de error del analizador (tree-sitter se recupera y marca `ERROR` o `MISSING`). Un fichero que no se puede decodificar va entero, como una entrada. Una tool detectada sin resolver deja aquí su entrada. Se cuentan entradas, no tools, porque no se sabe cuántas hay detrás. | entrada | E1 | `TestCoverageUnresolvedCountsLocations` |
| **efectivas** (`effective`) | Pares de acción y recurso que la API de identidad (GitHub, AWS) confirma como permitidos para la credencial del agente, con la respuesta de la API guardada. Los pares salen de una lista cerrada y versionada por conector, y el contador dice de cuál ("lista AWS v3"). Los `conditional` no cuentan: salen aparte, con el contexto que falta. El detalle de cada conector va debajo de la tabla. | par | E5 | `TestCoverageEffectiveNeedsASavedAPIResponse`, `TestCoverageEffectiveIsNotBoundedByDetected` |
| **efectivas no usadas** (`effective_unused`), **resaltadas** | Efectivas que no puede necesitar nada del agente. Es la diferencia del paso 5.5 sin IA. Solo da número si se ha visto todo lo que podría usar la credencial (condiciones debajo de la tabla). Si no, esas efectivas salen como **uso desconocido**, con la lista de lo que lo impide. Van resaltadas en toda vista. Cuando haya llamadas vistas en ejecución, el eje pasa a ser el del plan: lo efectivo menos lo usado en un periodo. | par | E5 | `TestCoverageEffectiveUnusedIsHighlighted`, `TestCoverageEffectiveUnusedIsUnknownWithAnyUnseenPart` |
| **mediadas** (`mediated`) | Su base son las tools del agente con al menos una llamada vista en el periodo; las que no tienen llamadas salen aparte, "sin llamadas vistas". Cuenta las de esa base cuyas llamadas vistas pasaron todas por el punto de decisión (`coverage: mediated` en cada evento): basta una vista sin él (`coverage: observed`) para que no cuente. Lleva siempre al lado el estado de la fuente que podría ver las llamadas no mediadas: el receptor OTLP, o la conciliación con CloudTrail y los registros de auditoría de los SaaS (E7). Mientras esa fuente no esté `observed` para el sistema, sale "llamadas no mediadas: sin fuente". No exige credencial intermediada: eso lo dice el contador de credenciales. | tool | E6 | `TestCoverageOneUnmediatedCallMakesTheCapabilityNotMediated`, `TestCoverageMediatedWithoutAnObserverOfUnmediatedCallsSaysSo`, `TestCoverageMediatedDoesNotRequireBrokeredCredential` |
| **gobernadas** (`governed`) | Mediadas cuya acción aparece de forma explícita en el ámbito de al menos una regla `permit` o `forbid` del paquete de política firmado que estaba en vigor en cada llamada: `action ==`, `action in [...]`, o `action in Action::"grupo"` si el esquema del paquete resuelve el grupo a acciones concretas. Una regla cuyo ámbito solo dice `action` vale para todas y no cuenta (sintaxis del ámbito: https://docs.cedarpolicy.com/policies/syntax-policy.html#term-parc-action). | tool | E6 | `TestCoverageGovernedNeedsAnExplicitRuleOfTheSignedPolicy` |

Cómo se leen las **efectivas** en cada conector. Lo comprobó `verificador-apis` contra la documentación oficial el 2026-09-29, y la E5 lo vuelve a comprobar antes de construir.

- **AWS**, con `SimulatePrincipalPolicy` (https://docs.aws.amazon.com/IAM/latest/APIReference/API_SimulatePrincipalPolicy.html):
  - Solo evalúa las acciones que se le pasan, y por eso hace falta la lista cerrada.
  - La decisión de cada recurso se lee en `ResourceSpecificResults` (https://docs.aws.amazon.com/IAM/latest/APIReference/API_ResourceSpecificResult.html), no en el `EvalDecision` general, que es el más restrictivo.
  - Un `allowed` con `MissingContextValues` no vacío es `conditional`.
  - Límites conocidos, que el contador enseña al lado: no evalúa las RCP, no admite una sesión de rol asumido como `CallerArn`, las SCP no devuelven el contexto que falta, y AWS avisa de que el resultado puede diferir del entorno real.
- **GitHub**, con la instalación (https://docs.github.com/en/rest/apps/apps#get-an-installation-for-the-authenticated-app):
  - Da `permissions`, por permiso y nivel (`read`, `write` y, en algunos, `admin`).
  - `repository_selection` va como atributo, para que crear un repo no cambie el número.
  - Es un techo: un token de instalación puede tener menos permisos y menos repos (https://docs.github.com/en/rest/apps/apps#create-an-installation-access-token-for-an-app). Si el agente usa uno así, se mide el token en cuanto se conoce, y mientras tanto el contador dice "techo de la instalación".
  - Leer la instalación exige el JWT de la App, no el token del agente.

Las **efectivas no usadas** solo dan número si se cumple todo esto:

- todas las tools del agente tienen capacidad potencial conocida, con los pares que necesitan de ese conector. Hoy la base de conocimiento no guarda esos pares, y añadirlos está en el backlog para antes de la E5; hasta entonces, el eje sale "uso desconocido";
- todas sus fuentes MCP están `observed`;
- ni el agente ni el bloque del repo tienen nada en lo no visto ni en `unresolved`;
- cada uso estático de la credencial está dentro de una tool detectada. Los nodos de LangGraph, los guardrails, los hooks y los clientes de memoria también la usan.

Dos aclaraciones:

- **"Resuelta" significa aquí leída entera del repo.** No significa resuelta por la base de conocimiento. La capacidad potencial de la E2 (lo que la base dice que puede hacer una tool) es un atributo de cada tool, no un eje de cobertura.
- **Contador de control de la E6: credenciales intermediadas.**
  - Se da como N de M, con la lista de las que no pasan por el runner. Nunca se da como porcentaje.
  - M son las variables de entorno referenciadas que `runner.yaml` asigna a un sistema. N son las que pasan por el runner (`credential_brokered` en sus eventos).
  - Límite conocido: las credenciales implícitas no entran en M. Son, por ejemplo, un cliente de SDK que lee su variable de entorno sin que el código la nombre, o la cadena por defecto de AWS. Por eso la vista dice "de las referenciadas por nombre", y detectarlas está en el backlog.
  - Test: `TestCoverageBrokeredCredentialsAreNOfM`.

## Parte 2: fuentes

Una fuente es algo de lo que Actaira saca capacidades de un agente. Hay de estos tipos:

- **El repo:** una sola fuente, leída por los extractores de la lista cerrada, con sus versiones. Lo que ningún extractor lee (otros frameworks, otras extensiones) no se ha mirado, y la vista lo dice.
- **Cada servidor MCP declarado:** la fuente es el listado de sus tools tal como lo ve el agente. Solo pasa a `observed` cuando el proxy MCP ve ese listado (E6). Una instantánea pública del registro no basta, porque no es lo que ve el agente.
- **Cada variable de entorno referenciada por nombre** (`env_ref`). En la E1 no se sabe si es una credencial. Pasa a serlo cuando `runner.yaml` le asigna un sistema (E5), y entonces el conector de identidad es la forma de leerla, no otra fuente. Si `runner.yaml` dice que no es una credencial, sale de M con esa declaración como motivo.
- **El punto de decisión del runner** (E6).

Cada fuente está en uno de estos estados:

| Estado | Cuándo | Lleva |
|---|---|---|
| **observada** (`observed`) | La última lectura salió bien y no está caducada. | Su antigüedad. En `actaira.lock` no hay horas, porque se exige el mismo fichero byte a byte; la vista la calcula al enseñarla. |
| **no configurada** (`not_configured`) | Actaira sabe que la fuente existe pero no tiene cómo mirarla. Le falta un conector, una credencial o una entrada en `runner.yaml`, o la versión aún no sabe leerla. En la E1, los servidores MCP y las variables de entorno. | El motivo. |
| **error** (`error`) | Se intentó mirar y falló. | El motivo, sin datos sensibles, y cuándo. |
| **caducada** (`stale`) | Se miró bien, pero la lectura ya no vale. | La antigüedad y la regla que la caduca. |

Cómo caduca cada tipo de fuente:

- **El repo, en la CLI:** está "leído ahora" si el lockfile coincide con el árbol (`actaira lock --check`), y `stale` si no. No caduca por tiempo.
- **El repo, en la nube:** vale la hora en que llegó la subida, junto con el resultado de `lock --check` que envía la Action.
- **Las fuentes con sondeo (E5):** caducan al pasar de la antigüedad máxima de su tipo.
- **Un servidor MCP visto por el proxy (E6):** caduca igual que el sondeo de su tipo.
- **El punto de decisión:** caduca con la antigüedad máxima del paquete de política firmado, o si se pierde el latido del runner.

El estado `observed` de una fuente dice que se leyó bien, aunque sea una lectura estática del repo. No implica `coverage: observed` ni `confidence: observed`, que hablan de lo visto en ejecución.

| Contador | Definición exacta | Llega en | Test que la fija |
|---|---|---|---|
| **M**, fuentes conocidas | Las fuentes del agente más las del bloque del repo, marcadas "del repo", en cualquier estado. | E1 | `TestCoverageSourcesCountObservedOfKnown` |
| **N**, fuentes observadas | Las de M en estado `observed`. | E1 | `TestCoverageSourcesCountObservedOfKnown` |
| **Lo no visto** (`unseen`) | Cada fuente de M que no está `observed`, con su estado y motivo, y cada parte saltada de una fuente observada. | E1 | `TestCoverageSourceNotObservedCarriesReason`, `TestCoverageSkippedPartsAreUnseen`, `TestCoverageMCPSourceStaysNotConfiguredWithOnlyAPublicSnapshot` |
| **Lo saltado** (`skipped`) | Los puntos de corte del recorrido del repo, con su motivo:<br>- un fichero que algún extractor leería y pasa de 1 MB;<br>- el directorio donde se llega a la profundidad máxima;<br>- un enlace simbólico que sale del repo;<br>- un directorio con una entrada `.git` (repo anidado o submódulo);<br>- cada regla de ignorado: las de serie salvo `.git`, y las de `.actairaignore`.<br>No se anota lo que hay debajo de un corte. Los enlaces simbólicos nunca se siguen: git los guarda como enlaces, y su destino dentro del repo ya se recorre.<br>Las reglas se anotan siempre, exista o no el directorio. El recorrido respeta `.gitignore` en todos los niveles, leído sin ejecutar git. Así el lockfile no depende de lo que git no versiona. | E1 | `TestLockDoesNotDependOnFilesOutsideGit` |
| **Antigüedad y caducidad** | Para cada fuente observada o caducada, el tiempo desde su última lectura correcta y la regla que la caduca. | E2 (repo), E5 (sondeo), E6 (proxy MCP y punto de decisión) | `TestCoverageRepoIsStaleWhenTheLockDoesNotMatch`, `TestCoverageSourceGoesStaleAfterMaxAge` |

Tests que valen para las dos partes, desde la E1:

- `TestCoverageUnseenAndUnresolvedNeverMix`: ningún elemento, identificado por su tipo, ubicación y nombre, está en las dos listas, y ningún `unresolved` sale de una fuente sin observar.
- `TestCoverageUnresolvedSourceDeclarationsAppearInTheSummary`.
- `TestCoverageAxisWithoutSourceIsNotZero`: un eje sin fuente sale "sin fuente", no 0 ni omitido.
- `TestCoverageRepoBlockIsShownWithoutAgents`.
- `TestNoOutputShowsACoveragePercentage` y `TestNoOutputShowsAnOverallCoverageVerdict`, sobre todas las salidas de la vista.

**La vista es por agente, más un bloque del repo.**

- El bloque del repo lleva lo que no se atribuye a ningún agente:
  - una tool que no se pasa a ningún agente;
  - un servidor de una configuración de cliente (`.mcp.json`, `.cursor/mcp.json`, `.vscode/mcp.json`);
  - una skill;
  - lo saltado;
  - una entrada `unresolved` fuera de cualquier agente.
- Tiene fuentes, `unresolved` y `skipped`.
- Sale en la vista de todos los agentes del repo, porque puede ser de cualquiera. Si no hay ningún agente, sale solo.

## El campo `coverage` del plan

- **`coverage` es un campo de cada evento y de cada tramo del mapa causal,** como en la sección 4 de `docs/PLAN.md`. Sus valores son `mediated`, `observed`, `declared` y `unseen`. La vista no define otro enumerado ni lo copia a las capacidades.
- **El eje mediadas se calcula con esos eventos,** con la regla de arriba.
- **Las capacidades de la E1 llevan solo `confidence`.** Es el enumerado del modelo que fija el paso 1.3, que incluye `unresolved`.
- **El bloque `coverage` de `actaira.lock` es la vista,** con el nombre que pidió Marcos. No es ese campo de los eventos.
- **`observed` llega con el receptor OTLP del bloque C5 del plan,** que aún no tiene épica. `mediated` llega con la E6.

## El bloque en `actaira.lock`

- **Solo lleva lo que sale del repo.**
  - Lo que se calcula en la nube o en el runner (las efectivas, las mediadas, las gobernadas y el estado de las credenciales y de los MCP en la E5 y la E6) nunca se escribe en `actaira.lock`.
  - La nube solo toma del lockfile la fuente repo y las listas estáticas, nunca el estado de una credencial o de un MCP, porque cualquiera con escritura en el repo puede editarlo.
  - En el lockfile, esos ejes salen "sin fuente".
- **Orden total:**
  - Cada lista se ordena por los bytes canónicos de sus elementos.
  - Una fuente se identifica por su tipo y su nombre, y lleva la lista ordenada de sus ubicaciones.
  - El test de determinismo de la E1 ejecuta los extractores en orden barajado.
- **Versión:** el bloque se versiona con el lockfile. `coverage.version` solo sube junto con `schema_version`, con su test de compatibilidad hacia atrás.

Esta es la forma que tendría en la E1. Es orientativa: el esquema exacto lo fija el paso 1.3.

```json
"coverage": {
  "version": 1,
  "agents": [
    {
      "agent": "support",
      "sources": [
        {"kind": "env_ref", "name": "STRIPE_API_KEY", "locations": ["support/agent.py:8:12"], "state": "not_configured", "reason": "no_runner_config"},
        {"kind": "mcp_server", "name": "stripe", "locations": ["support/agent.py:15:5"], "state": "not_configured", "reason": "mcp_tools_not_listed"}
      ],
      "axes": [
        {"axis": "detected", "value": 2},
        {"axis": "effective", "no_source": "not_from_repo"},
        {"axis": "effective_unused", "no_source": "not_from_repo"},
        {"axis": "governed", "no_source": "not_from_repo"},
        {"axis": "mediated", "no_source": "not_from_repo"},
        {"axis": "resolved", "value": 1},
        {"axis": "unresolved", "value": 2}
      ],
      "unresolved": [
        {"location": "support/agent.py:22:9", "kind": "tool_schema", "reason": "schema_built_at_runtime"},
        {"location": "support/agent.py:30:11", "kind": "tool_list", "reason": "list_built_at_runtime"}
      ]
    }
  ],
  "repo": {
    "sources": [
      {"kind": "repo", "name": ".", "state": "observed", "extractors": ["openai-agents-python/1"]}
    ],
    "unresolved": [],
    "skipped": [
      {"location": "support/prompts.py", "reason": "file_over_1mb"},
      {"rule": "node_modules/", "reason": "ignored_by_default"}
    ]
  }
}
```

En la terminal (E2), ese agente saldría así:

- "1 de 3 fuentes conocidas observadas". El repo es la fuente del bloque del repo.
- **Lo no visto:**
  - la variable `STRIPE_API_KEY`, sin `runner.yaml`;
  - el servidor MCP `stripe`, sin listado de tools;
  - `support/prompts.py`, que pasa de 1 MB;
  - la regla `node_modules/`.
- **Capacidades:** 2 detectadas, 1 resuelta y 2 entradas `unresolved`. Efectivas, efectivas no usadas, mediadas y gobernadas, "sin fuente".

## Qué entrega cada épica

| Épica | Qué añade a la vista |
|---|---|
| E1 | **Bloque `coverage` versionado en `actaira.lock`** (pasos 1.3 y 1.4), con un bloque por agente y uno del repo. Lleva:<br>- las fuentes: el repo, con sus extractores y versiones; una por servidor MCP declarado y una por variable de entorno referenciada, estas dos `not_configured`;<br>- `detected`, `resolved` y `unresolved`, con la lista de entradas `unresolved`;<br>- los demás ejes, como "sin fuente";<br>- lo saltado. Lo saltado del paso 1.4 se anota aquí y en ningún otro sitio.<br>El recorrido respeta `.gitignore`, no entra en repos anidados ni sigue enlaces simbólicos. |
| E2 | **`actaira coverage`** en la terminal y en `--json`, y una **sección plegada "Cobertura"** en el comentario del PR.<br>- Las fuentes MCP siguen `not_configured`, y las tools de su instantánea salen aparte, como tales.<br>- Lo que depende de la base de conocimiento o de las instantáneas se calcula al enseñarlo y no se guarda en el lockfile.<br>- El repo sale `stale` si el lockfile no coincide con el árbol. |
| E3 | **La vista en la consola**, en la ficha de cada agente, con la antigüedad de cada fuente, y un test en el navegador que falla con un porcentaje o un veredicto de conjunto. |
| E5 | - **Las variables que `runner.yaml` asigna a un sistema pasan a ser credenciales,** leídas con los conectores de GitHub y AWS.<br>- Llegan las **efectivas**, las **efectivas no usadas** resaltadas (o "uso desconocido") y el estado **caducada**.<br>- Los servidores MCP siguen `not_configured`. |
| E6 | **Mediadas, con la fuente que vería las llamadas no mediadas; gobernadas; y credenciales intermediadas,** como N de M. Una fuente MCP pasa a `observed` cuando el proxy MCP ve su listado (paso 6.3), y el punto de decisión es una fuente más. |
| E7 | **El paquete de auditoría** da la cobertura del periodo con esta vista, nunca como porcentaje, y un test sobre el paquete exportado falla con un porcentaje o un veredicto de conjunto. La da como:<br>- N de M tools mediadas;<br>- N de M credenciales intermediadas;<br>- N de M fuentes observadas durante todo el periodo, con las demás en lo no visto y los intervalos en que no lo estuvieron;<br>- lo no mediado y lo no visto.<br>Las gobernadas se miden con la política en vigor en cada llamada. La conciliación con CloudTrail y los registros de auditoría de los SaaS es la fuente que ve las llamadas no mediadas. |
