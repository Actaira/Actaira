# Vista de cobertura por agente

Qué sabe Actaira de cada agente y qué no. Lo pidió Marcos el 2026-09-29, antes del paso 1.1 de la E1. Este documento fija las definiciones. **Todavía no hay nada construido:** cada parte llega con su épica y con el test que la fija, escrito en rojo antes de construirla (tabla final).

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
   - **`unresolved`** es lo mirado y no entendido: una lista de tools que se construye en ejecución, una fábrica, `**kwargs` o un esquema calculado.
   - Un elemento está en una lista o en la otra, nunca en las dos.
4. **Un eje sin fuente observada no vale 0.**
   - Sale "sin fuente", con el motivo.
   - Un 0 solo significa que se miró y no hay.
5. **M solo cuenta las fuentes que Actaira conoce.** Por eso el resumen dice "de las fuentes conocidas": una fuente que Actaira no conoce no puede salir en la lista de lo no visto.
6. **Cada contador tiene una definición exacta y un test que la fija** (tablas de abajo).
   - Además, dos tests recorren todas las salidas de la vista: uno falla si alguna enseña un porcentaje de cobertura, y otro si alguna da un veredicto de conjunto ("cubierto", "OK", un check verde).
   - Cada épica que añade una salida la mete en esos dos tests.
7. **Las proporciones con intervalo de Wilson de `evals/results/` no entran en esta vista.** Son el recall del extractor o los efectos confirmados, y miden a Actaira, no la cobertura de un agente.

## Parte 1: capacidades (ejes independientes)

| Eje | Definición exacta | Unidad | Llega en | Test que la fija |
|---|---|---|---|---|
| **detectadas** (`detected`) | Tools distintas, por `id`, que un extractor encontró para el agente en una fuente observada. Una tool que aparece en dos sitios cuenta una vez. | tool | E1 | `TestCoverageDetectedCountsEachToolOnce` |
| **resueltas** (`resolved`) | Detectadas cuyo nombre, `schema_hash` y `description_hash` salen enteros del código o de la configuración, sin ejecutar nada. | tool | E1 | `TestCoverageResolvedNeedsTheWholeDefinition` |
| **`unresolved`** | Ubicaciones (fichero y línea) de una fuente observada donde el extractor vio la construcción de un agente o de una tool y no pudo saber qué contiene. Se cuentan ubicaciones, no tools, porque no se sabe cuántas hay detrás de cada una. Una tool detectada sin resolver deja una ubicación aquí. | ubicación | E1 | `TestCoverageUnresolvedCountsLocations` |
| **efectivas** (`effective`) | Pares de acción y recurso que la API de identidad del proveedor (GitHub, AWS) confirma como permitidos para la credencial del agente, con la respuesta de la API guardada. Los `conditional` (a AWS le falta contexto) no cuentan: salen aparte, con el contexto que falta. | permiso | E5 | `TestCoverageEffectiveNeedsASavedAPIResponse`, `TestCoverageEffectiveCanExceedDetected` |
| **efectivas no usadas** (`effective_unused`), **resaltadas** | Efectivas que no necesita ninguna tool detectada del agente, según su capacidad potencial en la base de conocimiento: es la diferencia del paso 5.5 sin IA. Si el agente tiene tools con efecto `unknown` o ubicaciones `unresolved`, el contador sale con ese aviso al lado, porque alguna podría usar el permiso. Van resaltadas en toda vista. | permiso | E5 | `TestCoverageEffectiveUnusedIsHighlighted`, `TestCoverageEffectiveUnusedWarnsWithUnresolvedTools` |
| **mediadas** (`mediated`) | Capacidades del agente cuyas llamadas pasan por el punto de decisión del runner con la credencial intermediada: las que llevan `coverage: mediated`. | capacidad | E6 | `TestCoverageMediatedCountsCallsThroughTheDecisionPoint` |
| **gobernadas** (`governed`) | Mediadas a las que se aplica al menos una regla del paquete de política firmado en vigor. Una mediada que ninguna regla nombra no está gobernada: la decide solo el comportamiento por defecto. | capacidad | E6 | `TestCoverageGovernedNeedsARuleOfTheSignedPolicy` |

Dos aclaraciones:

- **"Resuelta" significa aquí leída entera del código.** No significa resuelta por la base de conocimiento. La capacidad potencial de la E2 (lo que la base dice que puede hacer una tool) es un atributo de cada capacidad detectada, no un eje de cobertura.
- **Contador de control de la E6: credenciales intermediadas.** Se da como N de M credenciales que referencia el agente, con la lista de las que no pasan por el runner. Nunca se da como porcentaje. La E1 ya detecta esas credenciales por nombre. Test: `TestCoverageBrokeredCredentialsAreNOfM`.

## Parte 2: fuentes

Una fuente es algo de lo que Actaira saca capacidades de un agente. Son de estos tipos, según la épica que los añade:

- el repo;
- cada servidor MCP declarado (listar sus tools);
- cada credencial referenciada y cada conector de identidad (E5);
- el punto de decisión del runner (E6).

Cada fuente está en uno de estos estados:

| Estado | Cuándo | Lleva |
|---|---|---|
| **observada** (`observed`) | La última lectura salió bien y no supera la antigüedad máxima de su tipo. | Su antigüedad. En `actaira.lock` no hay horas, porque se exige el mismo fichero byte a byte: la antigüedad del repo es la del commit, y las vistas la calculan al enseñarla. |
| **no configurada** (`not_configured`) | Actaira sabe que la fuente existe pero no tiene cómo mirarla. Le falta un conector, una credencial o una entrada en `runner.yaml`, o la versión aún no sabe leerla. | El motivo. |
| **error** (`error`) | Se intentó mirar y falló. | El motivo, sin datos sensibles, y cuándo. |
| **caducada** (`stale`) | Se miró bien, pero hace más tiempo que la antigüedad máxima de su tipo. | Su antigüedad y ese máximo. La E5 lo fija por tipo a partir del sondeo de 15 minutos. |

| Contador | Definición exacta | Llega en | Test que la fija |
|---|---|---|---|
| **M**, fuentes conocidas | Las fuentes del agente que Actaira conoce, en cualquier estado. | E1 | `TestCoverageSourcesCountObservedOfKnown` |
| **N**, fuentes observadas | Las de M en estado `observed`. | E1 | `TestCoverageSourcesCountObservedOfKnown` |
| **Lo no visto** (`unseen`) | Cada fuente de M que no está `observed`, con su estado y motivo. También cada parte de una fuente observada que se saltó a propósito, con su ubicación y motivo: un fichero de más de 1 MB, un enlace que sale del repo, la profundidad máxima o un directorio ignorado. | E1 | `TestCoverageSourceNotObservedCarriesReason`, `TestCoverageSkippedPartsAreUnseen` |
| **Antigüedad y caducidad** | Para cada fuente observada o caducada, el tiempo desde su última lectura correcta. Pasa a `stale` al superar el máximo de su tipo. | E5 | `TestCoverageSourceGoesStaleAfterMaxAge` |

Tests que valen para las dos partes, desde la E1:

- `TestCoverageUnseenAndUnresolvedNeverMix`: ninguna ubicación está en las dos listas, y ningún `unresolved` sale de una fuente sin observar.
- `TestCoverageAxisWithoutSourceIsNotZero`: un eje sin fuente no sale como 0.
- `TestNoOutputShowsACoveragePercentage` y `TestNoOutputShowsAnOverallCoverageVerdict`, sobre todas las salidas de la vista.

**Lo que no se puede atribuir a un agente sale en la vista de todos los agentes del repo,** porque puede ser de cualquiera de ellos. Por ejemplo, un fichero saltado o una ubicación `unresolved` fuera de cualquier agente.

## El campo `coverage` del plan

La sección 4 de `docs/PLAN.md` define `coverage` con cuatro valores: `mediated`, `observed`, `declared` y `unseen`. La vista usa ese campo tal cual y no define otro.

| Valor | Qué dice de una capacidad | Llega en |
|---|---|---|
| `declared` | Se vio solo en el repo. | E1 |
| `observed` | Se vio en ejecución con OTel, sin punto de decisión. | Con el receptor OTLP del bloque C5 del plan, que aún no tiene épica. |
| `mediated` | Su llamada pasa por el punto de decisión con la credencial intermediada. | E6 |
| `unseen` | No se ha visto. | E1 |

- **Una capacidad lleva el valor más fuerte que tenga respaldado:** `mediated`, luego `observed` y luego `declared`. El eje **mediadas** cuenta las que llevan `mediated`.
- **El estado de una fuente es otro campo (`state`).** Dice si la fuente se ha mirado, no cómo se ve una capacidad. En los dos campos, `observed` significa "visto".
- **`unresolved` ya es un valor de `Confidence`** en el modelo de la E1, así que tampoco es un enumerado nuevo.

## Qué entrega cada épica

| Épica | Qué añade a la vista |
|---|---|
| E1 | **Bloque `coverage` versionado en `actaira.lock`** (paso 1.3), con dos fuentes: el repo, y una por servidor MCP declarado en el código o en la configuración. Las MCP salen `not_configured`, porque la E1 no lista sus tools (`tools_source: none`). Lleva los contadores `detected`, `resolved` y `unresolved`, y lo no visto. Lo saltado del paso 1.4 se anota aquí y en ningún otro sitio. El bloque no lleva horas. |
| E2 | **`actaira coverage`** en la terminal y en `--json`, y una **sección plegada "Cobertura"** en el comentario del PR. Las fuentes MCP con listado de tools (`tools_source` distinto de `none`) pasan a `observed`, con la antigüedad de su instantánea. |
| E3 | **La vista en la consola**, en la ficha de cada agente, con la antigüedad de cada fuente. |
| E5 | **Fuentes de identidad de GitHub y AWS** (una por credencial y conector), **efectivas**, **efectivas no usadas** resaltadas, y el estado **caducada**. Lo que no está en `runner.yaml` sale `not_configured`, dentro de lo no visto. |
| E6 | **Mediadas y gobernadas**, y el contador de control de credenciales intermediadas, como N de M. |
| E7 | **El paquete de auditoría** da la cobertura del periodo con esta vista: N de M fuentes observadas y lo no visto, nunca un porcentaje. |

En la E1, el bloque del lockfile tendría esta forma (orientativa: el esquema exacto y su test de compatibilidad los fija el paso 1.3):

```json
"coverage": {
  "version": 1,
  "sources": [
    {"kind": "repo", "location": ".", "state": "observed"},
    {"kind": "mcp_server", "location": ".mcp.json:4", "name": "stripe", "state": "not_configured", "reason": "mcp_tools_not_listed"}
  ],
  "capabilities": {"detected": 7, "resolved": 5, "unresolved": 3},
  "skipped": [
    {"location": "data/export.json", "reason": "file_over_1mb"}
  ]
}
```

Lo no visto de la vista son las fuentes que no están `observed` más `skipped`. Los ejes que la E1 no mide (`effective` y los siguientes) no aparecen: no valen 0.
