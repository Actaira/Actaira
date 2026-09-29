# Vista de cobertura por agente

Qué sabe Actaira de cada agente y qué no. Lo pidió Marcos el 2026-09-29, antes del paso 1.1 de la E1. Este documento fija las definiciones. **Todavía no hay nada construido:** cada parte llegará con su épica y con el test que la fija, escrito en rojo antes de construirla (tabla final).

La vista tiene **dos partes separadas**, que nunca se combinan en una cifra:

1. **Capacidades:** qué puede hacer el agente, contado en ejes independientes.
2. **Fuentes:** de dónde lo sabe Actaira, cada una con su estado y motivo.

## Doctrina

1. **Nunca un porcentaje global ni un check verde de conjunto.** El resumen es "N de M fuentes observadas" más la lista de lo no visto.
2. **Los ejes de capacidades no son un embudo.**
   - Cada eje cuenta sobre su propia base y ninguno se divide por otro.
   - Lo efectivo puede superar a lo detectado: una credencial puede permitir más de lo que usa el código.
3. **`unseen` y `unresolved` nunca se mezclan.**
   - **`unseen`** es lo no mirado: una fuente sin observar, o una parte de una fuente que se saltó.
   - **`unresolved`** es lo mirado y no entendido.
   - Un elemento está en una lista o en la otra, nunca en las dos. Si la declaración de una fuente no se entiende (un servidor MCP construido con `params=load()`), cuenta solo como `unresolved` y no crea una fuente.
4. **Un eje sin fuente observada no vale 0 ni desaparece.**
   - Sale "sin fuente", con el motivo.
   - Un 0 solo significa que se miró y no hay.
   - Solo alimenta los ejes lo que sale de fuentes `observed`. Lo que viene de una fuente con error o caducada sale en lo no visto, con su último valor y su fecha.
5. **Si no se sabe, el contador no da número.** Sale lo que falta para saberlo, como el "uso desconocido" de las efectivas no usadas.
6. **M solo cuenta las fuentes que Actaira conoce.**
   - Por eso el resumen dice "de las fuentes conocidas".
   - Los límites conocidos se escriben junto al contador al que afectan, como las credenciales implícitas.
7. **Cada contador tiene una definición exacta y un test que la fija** (tablas de abajo).
   - Además, dos tests recorren todas las salidas de la vista: uno falla si alguna enseña un porcentaje de cobertura, y otro si alguna da un veredicto de conjunto ("cubierto", "OK", un check verde).
   - Cada épica que añade una salida la mete en esos dos tests, también la consola (E3) y el paquete de auditoría (E7), que están en otro repo.
8. **Las proporciones con intervalo de Wilson de `evals/results/` no entran en esta vista.** Son el recall del extractor o los efectos confirmados, y miden a Actaira, no la cobertura de un agente.

## Parte 1: capacidades (ejes independientes)

| Eje | Definición exacta | Unidad | Llega en | Test que la fija |
|---|---|---|---|---|
| **detectadas** (`detected`) | Tools distintas, por `id`, que un extractor encontró para el agente en una fuente observada. Varias referencias al mismo `id` cuentan una vez. Las tools de la instantánea pública de un servidor MCP no cuentan: son capacidad potencial (E2), no algo encontrado en una fuente del agente. | tool | E1 | `TestCoverageDetectedCountsEachToolOnce` |
| **resueltas** (`resolved`) | Detectadas cuyo nombre, `schema_hash` y `description_hash` se calculan con lo que está escrito en la fuente que las detectó. El hash es el de la representación normalizada que da el extractor (parámetros, tipos y descripción tal como están escritos), no el del esquema que un SDK genera en ejecución a partir de ellos (`@function_tool`, zod). | tool | E1 | `TestCoverageResolvedNeedsTheWholeDefinition` |
| **`unresolved`** | Ubicaciones (fichero y línea) de una fuente observada que el extractor leyó y no entendió. Son la construcción de un agente, una tool o un servidor MCP que no se puede resolver sin ejecutar (listas construidas en ejecución, fábricas, `**kwargs`, un esquema calculado), o un fichero que no pudo analizar (sintaxis o codificación). Se cuentan ubicaciones, no tools, porque no se sabe cuántas hay detrás. Una tool detectada sin resolver deja aquí su ubicación. | ubicación | E1 | `TestCoverageUnresolvedCountsLocations` |
| **efectivas** (`effective`) | Pares de acción y recurso que la API de identidad (GitHub, AWS) confirma como permitidos para la credencial del agente, con la respuesta de la API guardada. Los pares salen de una lista cerrada y versionada por conector, y el contador dice de cuál ("lista AWS v3"), porque `SimulatePrincipalPolicy` solo responde a lo que se le pregunta. En GitHub, el par es permiso y nivel, con `repository_selection` como atributo, para que crear un repo no cambie el número. Los `conditional` (a AWS le falta contexto) no cuentan: salen aparte, con el contexto que falta. | par | E5 | `TestCoverageEffectiveNeedsASavedAPIResponse`, `TestCoverageEffectiveIsNotBoundedByDetected` |
| **efectivas no usadas** (`effective_unused`), **resaltadas** | Efectivas que no puede necesitar ninguna tool del agente según su capacidad potencial en la base de conocimiento: es la diferencia del paso 5.5 sin IA. Solo da número si todas las tools del agente tienen capacidad potencial conocida y el agente no tiene ubicaciones `unresolved`. Si no, esas efectivas salen como **uso desconocido**, con las tools que lo impiden. Van resaltadas en toda vista. Cuando haya llamadas vistas en ejecución (E6), el eje pasa a ser el del plan: lo efectivo menos lo usado en un periodo. | par | E5 | `TestCoverageEffectiveUnusedIsHighlighted`, `TestCoverageEffectiveUnusedNeedsEveryToolKnown` |
| **mediadas** (`mediated`) | Capacidades del agente cuyas llamadas vistas en el periodo pasaron todas por el punto de decisión (`coverage: mediated` en cada evento). Basta una llamada vista sin punto de decisión (`coverage: observed`) para que no cuente. No exige credencial intermediada: eso lo dice el contador de credenciales. | capacidad | E6 | `TestCoverageOneUnmediatedCallMakesTheCapabilityNotMediated` |
| **gobernadas** (`governed`) | Mediadas cuya acción aparece de forma explícita en el ámbito de al menos una regla `permit` o `forbid` del paquete de política firmado en vigor (`action ==` o `action in [...]`). Una regla cuyo ámbito no nombra acciones vale para todas y no cuenta. | capacidad | E6 | `TestCoverageGovernedNeedsAnExplicitRuleOfTheSignedPolicy` |

Dos aclaraciones:

- **"Resuelta" significa aquí leída entera de la fuente.** No significa resuelta por la base de conocimiento. La capacidad potencial de la E2 (lo que la base dice que puede hacer una tool) es un atributo de cada capacidad, no un eje de cobertura.
- **Contador de control de la E6: credenciales intermediadas.**
  - Se da como N de M: de las M credenciales que el agente referencia por nombre, N pasan por el runner (`credential_brokered` en sus eventos). Va con la lista de las que no.
  - Nunca se da como porcentaje.
  - Límite conocido: las credenciales implícitas no entran en M. Son, por ejemplo, un cliente de SDK que lee su variable de entorno sin que el código la nombre, o la cadena por defecto de AWS. Por eso la vista dice "de las referenciadas por nombre", y detectarlas está en el backlog.
  - Test: `TestCoverageBrokeredCredentialsAreNOfM`.

## Parte 2: fuentes

Una fuente es algo de lo que Actaira saca capacidades de un agente. Hay de estos tipos:

- **El repo:** una sola fuente, leída por los extractores de la lista cerrada, con sus versiones. Lo que ningún extractor lee (otros frameworks, otras extensiones) no se ha mirado, y la vista lo dice.
- **Cada servidor MCP declarado:** la fuente es el listado de sus tools tal como lo ve el agente.
- **Cada credencial referenciada por nombre:** una fuente por credencial. El conector de identidad (E5) es la forma de leerla, no otra fuente.
- **El punto de decisión del runner** (E6).

Cada fuente está en uno de estos estados:

| Estado | Cuándo | Lleva |
|---|---|---|
| **observada** (`observed`) | La última lectura salió bien y no está caducada. | Su antigüedad. En `actaira.lock` no hay horas, porque se exige el mismo fichero byte a byte; la vista la calcula al enseñarla. |
| **no configurada** (`not_configured`) | Actaira sabe que la fuente existe pero no tiene cómo mirarla. Le falta un conector, una credencial o una entrada en `runner.yaml`, o la versión aún no sabe leerla. En la E1, los servidores MCP y las credenciales. | El motivo. |
| **error** (`error`) | Se intentó mirar y falló. | El motivo, sin datos sensibles, y cuándo. |
| **caducada** (`stale`) | Se miró bien, pero la lectura ya no vale. | La antigüedad y la regla que la caduca. |

Una lectura caduca así:

- **Una fuente con sondeo (E5):** cuando pasa de la antigüedad máxima de su tipo.
- **El repo:** cuando el lockfile ya no coincide con el árbol (`actaira lock --check` falla). No caduca por tiempo.
- **La instantánea de una versión fijada:** no caduca.

El estado `observed` de una fuente dice que se leyó bien, aunque sea una lectura estática del repo. No implica `coverage: observed` ni `confidence: observed`, que hablan de lo visto en ejecución.

| Contador | Definición exacta | Llega en | Test que la fija |
|---|---|---|---|
| **M**, fuentes conocidas | Las fuentes del agente que Actaira conoce, en cualquier estado. | E1 | `TestCoverageSourcesCountObservedOfKnown` |
| **N**, fuentes observadas | Las de M en estado `observed`. | E1 | `TestCoverageSourcesCountObservedOfKnown` |
| **Lo no visto** (`unseen`) | Cada fuente de M que no está `observed`, con su estado y motivo, y cada parte saltada de una fuente observada. | E1 | `TestCoverageSourceNotObservedCarriesReason`, `TestCoverageSkippedPartsAreUnseen` |
| **Lo saltado** (`skipped`) | Los ficheros que algún extractor leería (por nombre o extensión) y que se saltan por un límite: más de 1 MB, un enlace que sale del repo o la profundidad máxima. También cada regla de ignorado: las de serie salvo `.git`, y las de `.actairaignore`. Las reglas se anotan siempre, como reglas, exista o no el directorio en disco, para que el lockfile no dependa de lo que no está en git. | E1 | `TestCoverageSkippedDoesNotDependOnIgnoredDirectories` |
| **Antigüedad y caducidad** | Para cada fuente observada o caducada, el tiempo desde su última lectura correcta, y la regla que la caduca. | E2 (repo e instantáneas), E5 (fuentes con sondeo) | `TestCoverageRepoIsStaleWhenTheLockDoesNotMatch`, `TestCoverageSourceGoesStaleAfterMaxAge` |

Tests que valen para las dos partes, desde la E1:

- `TestCoverageUnseenAndUnresolvedNeverMix`: ninguna ubicación está en las dos listas, y ningún `unresolved` sale de una fuente sin observar.
- `TestCoverageAxisWithoutSourceIsNotZero`: un eje sin fuente sale "sin fuente", no 0 ni omitido.
- `TestNoOutputShowsACoveragePercentage` y `TestNoOutputShowsAnOverallCoverageVerdict`, sobre todas las salidas de la vista.

**La vista es por agente.** Lo que no se atribuye a ningún agente va en un bloque del repo y sale en la vista de todos los agentes del repo, porque puede ser de cualquiera. Por ejemplo:

- una tool que no se pasa a ningún agente;
- un servidor de una configuración de cliente (`.mcp.json`, `.cursor/mcp.json`, `.vscode/mcp.json`);
- una skill;
- un fichero saltado;
- una ubicación `unresolved` fuera de cualquier agente.

## El campo `coverage` del plan

- **`coverage` es un campo de cada evento y de cada tramo del mapa causal,** como en la sección 4 de `docs/PLAN.md`. Sus valores son `mediated`, `observed`, `declared` y `unseen`. La vista no define otro enumerado ni lo copia a las capacidades.
- **El eje mediadas se calcula con esos eventos,** con la regla de arriba: el valor más débil de las llamadas vistas en el periodo.
- **Las capacidades de la E1 llevan solo `confidence`.** Es el enumerado del modelo que fija el paso 1.3, que incluye `unresolved`.
- **El bloque `coverage` de `actaira.lock` es la vista,** con el nombre que pidió Marcos. No es ese campo de los eventos.
- **`observed` llega con el receptor OTLP del bloque C5 del plan,** que aún no tiene épica. `mediated` llega con la E6.

## Qué entrega cada épica

| Épica | Qué añade a la vista |
|---|---|
| E1 | **Bloque `coverage` versionado en `actaira.lock`** (paso 1.3), con un bloque por agente y uno del repo. Lleva:<br>- las fuentes: el repo, con sus extractores y versiones; una por servidor MCP declarado y una por credencial referenciada por nombre, estas dos `not_configured`;<br>- los contadores `detected`, `resolved` y `unresolved`, con la lista de ubicaciones `unresolved`;<br>- los ejes que la E1 no mide, como "sin fuente";<br>- lo saltado. Lo saltado del paso 1.4 se anota aquí y en ningún otro sitio.<br>El bloque no lleva horas y sus listas van ordenadas. |
| E2 | **`actaira coverage`** en la terminal y en `--json`, y una **sección plegada "Cobertura"** en el comentario del PR.<br>- Las fuentes MCP siguen `not_configured` (`public_snapshot_only`): la instantánea da capacidad potencial, no el listado que ve el agente.<br>- Lo que depende de la base de conocimiento o de las instantáneas se calcula al enseñarlo y no se guarda en el lockfile.<br>- El repo sale `stale` si el lockfile no coincide con el árbol. |
| E3 | **La vista en la consola**, en la ficha de cada agente, con la antigüedad de cada fuente, y un test en el navegador que falla con un porcentaje o un veredicto de conjunto. |
| E5 | - **Las credenciales pasan a leerse** con los conectores de GitHub y AWS.<br>- Llegan las **efectivas**, las **efectivas no usadas** resaltadas y el estado **caducada**.<br>- Lo que no está en `runner.yaml` sale `not_configured`.<br>- Una fuente MCP pasa a `observed` cuando el runner lista sus tools con la identidad del agente (vigilantes del bloque C3 del plan). |
| E6 | **Mediadas, gobernadas y credenciales intermediadas** (N de M). Una fuente MCP también pasa a `observed` cuando el proxy MCP ve su listado. |
| E7 | **El paquete de auditoría** da la cobertura del periodo con esta vista, nunca como porcentaje, y un test sobre el paquete exportado falla con un porcentaje o un veredicto de conjunto. La da como:<br>- N de M capacidades mediadas;<br>- N de M credenciales intermediadas;<br>- N de M fuentes observadas;<br>- lo no mediado y lo no visto. |

En la E1, el bloque del lockfile tendría esta forma. Es orientativa: el esquema exacto y su test de compatibilidad los fija el paso 1.3.

```json
"coverage": {
  "version": 1,
  "agents": [
    {
      "agent": "support",
      "sources": [
        {"kind": "credential", "name": "STRIPE_API_KEY", "location": "support/agent.py:8", "state": "not_configured", "reason": "no_identity_connector"},
        {"kind": "mcp_server", "name": "stripe", "location": "support/agent.py:15", "state": "not_configured", "reason": "mcp_tools_not_listed"},
        {"kind": "repo", "location": ".", "state": "observed", "extractors": ["openai-agents-python/1"]}
      ],
      "axes": [
        {"axis": "detected", "value": 2},
        {"axis": "resolved", "value": 1},
        {"axis": "unresolved", "value": 2},
        {"axis": "effective", "no_source": "no_identity_connector"},
        {"axis": "effective_unused", "no_source": "no_identity_connector"},
        {"axis": "mediated", "no_source": "no_decision_point"},
        {"axis": "governed", "no_source": "no_decision_point"}
      ],
      "unresolved": [
        {"location": "support/agent.py:22", "kind": "tool_schema", "reason": "schema_built_at_runtime"},
        {"location": "support/agent.py:30", "kind": "tool_list", "reason": "list_built_at_runtime"}
      ]
    }
  ],
  "repo": {
    "skipped": [
      {"rule": "node_modules/", "reason": "ignored_by_default"},
      {"location": "support/prompts.py", "reason": "file_over_1mb"}
    ]
  }
}
```

En la terminal (E2), ese agente saldría así:

- "1 de 3 fuentes conocidas observadas".
- **Lo no visto:**
  - la credencial `STRIPE_API_KEY`, sin conector de identidad;
  - el servidor MCP `stripe`, sin listado de tools;
  - la regla `node_modules/`;
  - `support/prompts.py`, que pasa de 1 MB.
- **Capacidades:** 2 detectadas, 1 resuelta y 2 ubicaciones `unresolved`. Efectivas, mediadas y gobernadas, "sin fuente".

**Orden y versiones:**

- Las fuentes van ordenadas por `kind` y `location`, y el resto de listas por `location`.
- `coverage.version` sube cuando una épica añade ejes o fuentes. Cada versión es un cambio del esquema del lockfile, con su test de compatibilidad hacia atrás.
