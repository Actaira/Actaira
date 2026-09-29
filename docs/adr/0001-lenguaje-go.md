# ADR 0001: Go para la CLI, la Action, el runner, el proxy y la nube

- **Estado:** aceptado.
- **Fecha:** 2026-09-29.
- **Decide:** el plan (`docs/PLAN.md`, sección 3, ADR 1). Se copia aquí en el paso 1.1 de la E1 con la primera medición.

## Contexto

Actaira tiene cinco piezas que se ejecutan en sitios distintos:

- la CLI `actaira`, en el portátil de quien construye agentes;
- la GitHub Action, en runners de Linux;
- el runner, en la infraestructura del cliente;
- el proxy MCP, en esa misma infraestructura;
- la nube, en Azure Container Apps.

Las tres primeras se distribuyen a terceros. El runner y el proxy evalúan políticas Cedar en el camino de cada llamada de un agente, y tienen que ser rápidos y fáciles de instalar.

## Decisión

1. **Go en las cinco piezas**, con un solo módulo abierto, `github.com/actaira/actaira`, y el repo `actaira-cloud` para la nube.
2. **API pública en `pkg/`** (modelo, extractores, lockfile, diff, base de conocimiento), porque `actaira-cloud` la importa y Go prohíbe importar `internal/` desde otro módulo. Lo que solo usa la CLI va en `internal/`. `internal/repotest` comprueba que ningún paquete de `pkg/` importa `internal/`.
3. **La versión de Go la fija `go.mod`** (`go 1.27.1`). Una herramienta que analiza el código, como golangci-lint, tiene que estar compilada con una versión de Go que la acepte (`Makefile`).

## Opciones

| Opción | A favor | En contra |
|---|---|---|
| A. Go | Un binario por sistema, sin intérprete; `cedar-go` es el SDK oficial de Cedar en Go (https://github.com/cedar-policy/cedar-go); arranque de milisegundos; un solo lenguaje para CLI, runner, proxy y nube | tree-sitter exige cgo, así que el binario deja de ser estático y se compila en runners nativos (ADR 0003, paso 1.2) |
| B. Python, reutilizando el antiguo seamark | Ya existe código | Resuelve otro problema (configuración de agentes de código); lo reutilizable es la verificación y la criptografía, que no hacen falta hasta la fase 5; distribuir un intérprete en el runner y en la Action es más frágil |
| C. Rust | Binario pequeño; la CLI oficial de Cedar está en Rust | Más lento de escribir para un equipo de una persona con Claude Code; la nube y los SDK de los clientes siguen en otros lenguajes |
| D. TypeScript | Los SDK de agentes en TS | Un runtime de Node en el runner y en la Action; peor arranque y distribución |

## Por qué esta

Por el runner y el proxy de las fases 3 y 4, por un solo lenguaje en todas las piezas y por la distribución en un binario. En una Action de CI el arranque en milisegundos no importa, pero en el proxy, que está en el camino de cada llamada, sí. Reescribir en Go no tira el producto de la fase 1, porque ese producto no existía todavía.

## Coste

- **cgo por tree-sitter:** si lo exige, el binario se compila en runners nativos de la matriz de GitHub Actions y, para que sea estático, dentro de Alpine (paso 1.2, ADR 0003).
- **Dos toolchains en la CI de la fase 4:** la validación de políticas usa la CLI oficial de Cedar en Rust (plan, ADR 4).
- **Las herramientas de análisis van detrás de Go:** subir la versión de `go.mod` exige que golangci-lint esté compilado con esa versión o una posterior.

## Latencia

La primera medición, en el paso 1.1, es de `actaira version`: 200 ejecuciones en WSL2 con go1.27.1, contando el arranque del proceso desde Python, dan una mediana de 1,02 ms y un p95 de 1,22 ms, con un binario de 2,4 MB (`evals/results/2026-09-29-arranque-cli.json`, con el commit y el comando). Se vuelve a medir con los extractores (paso 1.2) y con el runner (fase 3).

## Errores

- **Si cgo no compila en macOS:** la E1 y la E2 salen solo para Linux, porque la Action corre en Linux, y macOS pasa al backlog con el error documentado (ADR 0003).
- **Si una herramienta está compilada con un Go anterior al de `go.mod`:** `make check` falla en `lint`, y hay que subir la herramienta en el mismo PR que sube Go.

## Reversión

El lockfile es JSON canónico independiente del lenguaje (ADR 0002), y la base de conocimiento son datos. Cambiar de lenguaje obliga a reescribir el código, pero no los datos ni los ficheros que ya tengan los usuarios. Cuanto antes se decidiera, menos código habría que reescribir.
