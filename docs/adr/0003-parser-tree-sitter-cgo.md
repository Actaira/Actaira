# ADR 0003: tree-sitter con cgo, a través del binding oficial de Go

- **Estado:** aceptado para Linux. El resultado de macOS está en "Plataformas".
- **Fecha:** 2026-09-29.
- **Decide:** la E1 (`docs/epicas/E1.md`, paso 1.2), con la medición del paso 1.2a.

## Contexto

Los extractores de la E1 leen código Python, TypeScript y TSX sin ejecutarlo (plan, ADR 3). Necesitan un analizador sintáctico que:

- aguante código roto o a medias sin fallar, porque el código es del repo analizado;
- dé posiciones exactas (fichero, línea y columna) para las entradas `unresolved`;
- tenga gramáticas mantenidas de los tres lenguajes;
- sea rápido: `actaira discover` tiene que tardar menos de 10 s en el repo p95 del corpus.

## Decisión

1. **tree-sitter con cgo, con el binding oficial de Go** `github.com/tree-sitter/go-tree-sitter` v0.25.0 y las gramáticas oficiales:
   - `tree-sitter-python` v0.25.0;
   - `tree-sitter-typescript` v0.23.2, con TypeScript y TSX por separado, porque la gramática de TypeScript lee JSX como errores.
2. **Versiones de ABI** (lo comprobó `verificador-apis`: `evals/sessions/2026-09-29-e1-paso-2a-apis.txt`):
   - go-tree-sitter v0.25.0 acepta gramáticas de ABI 13 a 15;
   - la de Python v0.25.0 es de ABI 15 y la de TypeScript v0.23.2, de ABI 14.
   - La gramática de Python pide go-tree-sitter v0.24.0 en su `go.mod`, que solo llega a la 14. Por eso `go.mod` fija la v0.25.0 de forma explícita. Si bajara, `SetLanguage` fallaría y `TestParsesEachLanguage` saldría en rojo.
3. **`pkg/extract/treesitter` es la única puerta:** crea el parser, lo cierra y devuelve un árbol que se cierra con `Close`. Un segundo `Close` no hace nada, porque go-tree-sitter liberaría la misma memoria dos veces.
4. **Los objetos de tree-sitter se liberan siempre** (`.claude/rules/go.md`). Lo fija un test de fugas sobre 1.000 parseos: sin `Close`, la memoria del proceso crece 3.479 MB.
5. **El binario con cgo es dinámico.** El binario estático para distribuir se compila en Alpine en el paso 1.2b.

## Medición

Está en `evals/results/parser-2026-09-29.json`, con el commit, el entorno y el comando. Se midió en Linux amd64 (WSL2, 14 CPU, go1.27.1), con una sola goroutine, leyendo los ficheros antes de medir y cerrando cada árbol:

| Repo (fijado por commit, `evals/bench/fetch.sh`) | Ficheros | Tamaño | Tiempo total | Mediana por fichero | p95 por fichero | Con errores de sintaxis |
|---|---|---|---|---|---|---|
| `langchain-ai/langchain` (Python) | 1.000 | 6,0 MB | 537 ms | 0,08 ms | 2,2 ms | 0 |
| `langchain-ai/langchainjs` (TypeScript y TSX) | 1.000 | 3,6 MB | 303 ms | 0,14 ms | 1,1 ms | 0 |

- **Tamaño del binario:** el programa de medición, con tree-sitter y las tres gramáticas, pesa 8,4 MB. La CLI sin ellas pesa 2,4 MB (`evals/results/2026-09-29-arranque-cli.json`).
- **Gramáticas:** ninguno de los 2.000 ficheros reales dio errores de sintaxis, así que las versiones de las gramáticas leen el código actual de esos repos.

## Plataformas

- **Linux amd64:** compila y pasa los tests, en local y en el check obligatorio `check`.
- **macOS:** lo dice el job `check-macos` del workflow `platforms.yml`, que no es obligatorio. Su resultado se anota aquí al fusionar el paso 1.2a.
- **Harness en macOS:** es otra cuestión (backlog): GNU make, bash 4 y GNU sed. No cuenta para esta decisión.

## Opciones

| Opción | A favor | En contra |
|---|---|---|
| A. go-tree-sitter con cgo | Binding y gramáticas oficiales; el parser es el de las gramáticas, en C; medido: menos de 1 s para 1.000 ficheros | cgo: binario dinámico, compilación nativa por sistema y estático solo con Alpine |
| B. tree-sitter compilado a WebAssembly, con un runtime de WASM en Go | Sin cgo, un binario estático en cualquier sistema | Más lento; no hay binding oficial de Go para WASM; más piezas que mantener |
| C. Un parser escrito en Go por lenguaje | Sin cgo | Tres gramáticas propias que mantener al día con Python, TypeScript y TSX |
| D. Llamar al intérprete de Python o a `tsc` | Parsers exactos | Ejecuta herramientas del sistema del usuario y depende de ellas; en la Action, más lento y frágil |

## Por qué esta

Es la única opción con gramáticas oficiales de los tres lenguajes, errores localizados y velocidad medida muy por debajo del objetivo. El coste de cgo ya lo recogía el plan (ADR 1): la Action corre en Linux, y el binario estático sale de Alpine.

## Coste

- **cgo:** hace falta un compilador de C en la CI y en quien compile desde el código.
- **Distribución:** binarios por sistema, compilados en runners nativos (paso 1.2b).
- **Tamaño:** unos 6 MB más por las tres gramáticas.

## Latencia

Menos de 1 s para 1.000 ficheros por lenguaje, en una goroutine. El objetivo de `discover` es menos de 10 s en el repo p95 del corpus (paso 1.6).

## Errores

- **Código roto:** se parsea igual, con nodos ERROR y MISSING, que los extractores anotan como `unresolved`.
- **Una gramática con una versión de ABI incompatible:** `SetLanguage` devuelve error y `Parse` lo propaga, con el lenguaje en el mensaje.
- **La etiqueta v0.25.0 de go-tree-sitter ya no está en GitHub:** solo en el proxy de Go (proxy.golang.org). Se baja de ahí y la verifican `go.sum` y sum.golang.org. Con `GOPROXY=direct` no se encontraría. Si el proyecto publica una versión nueva, se sube en su propio PR, con esta medición repetida.
- **Sin cgo** (`CGO_ENABLED=0`): los paquetes que usan las gramáticas no compilan ("build constraints exclude all Go files" en sus bindings). La CLI aún compila porque todavía no los importa; dejará de hacerlo en el paso 1.5, cuando los use.

## Reversión

Los extractores solo ven `pkg/extract/treesitter`, así que cambiar a WASM (opción B) toca ese paquete y la distribución, no los extractores.
