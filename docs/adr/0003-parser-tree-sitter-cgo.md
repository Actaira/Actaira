# ADR 0003: tree-sitter con cgo, a través del binding oficial de Go

- **Estado:** aceptado, para Linux y macOS.
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
3. **`pkg/extract/treesitter` es la única puerta:**
   - `Parse(ctx, lang, src)` crea el parser, lo cierra y devuelve un árbol que se cierra con `Close`.
   - Un segundo `Close` no hace nada, porque go-tree-sitter liberaría la misma memoria dos veces.
   - El parseo se para cuando el contexto termina, con el callback de progreso de go-tree-sitter, y el error envuelve `ctx.Err()`. Hace falta porque un fichero hostil cuesta segundos y más de 1 GB (ver "Latencia").
4. **Los objetos de tree-sitter se liberan siempre** (`.claude/rules/go.md`). Lo fijan dos tests de fugas:
   - 1.000 parseos de un fichero de 60 KB: sin `Tree.Close`, la memoria del proceso crece 3.479 MB;
   - 20.000 parseos de un fichero mínimo: sin cerrar el parser, crece unos 140 MB.
5. **El binario con cgo es dinámico.** El binario estático para distribuir se compila en Alpine en el paso 1.2b.

## Medición

Está en `evals/results/parser-2026-09-29.json`, con el commit, el entorno (WSL2, 14 CPU, go1.27.1, gcc 13.3) y el comando. Se midió en Linux amd64, con una sola goroutine, leyendo los ficheros antes de medir y cerrando cada árbol, y con una gramática por repo:

| Repo (fijado por commit, `evals/bench/fetch.sh`) | Gramática | Ficheros | Tamaño | Tiempo total | Mediana por fichero | p95 por fichero | Con errores de sintaxis |
|---|---|---|---|---|---|---|---|
| `langchain-ai/langchain` | Python | 1.000, de ellos 50 vacíos | 6,0 MB | 539 ms | 0,08 ms | 2,3 ms | 0 |
| `langchain-ai/langchainjs` | TypeScript | 1.000 | 3,7 MB | 298 ms | 0,14 ms | 1,1 ms | 0 |
| `vercel/ai` | TSX | 520, todos los del repo | 1,5 MB | 130 ms | 0,14 ms | 0,8 ms | 1 |

- **Tamaño del binario** (`evals/results/2026-09-29-tamano-cli.json`, `evals/bench/size.sh`): la CLI compilada con `-trimpath` pesa 2,37 MB, y con tree-sitter y las tres gramáticas enlazadas, 6,32 MB. Es decir, 3,95 MB más.
- **Gramáticas:**
  - de los 2.520 ficheros reales, 2.519 se leen sin errores;
  - el que falla es `apps/docs/app/[lang]/unauthenticated-ai-gateway/page.tsx` de `vercel/ai`, una página de documentación válida con JSX y plantillas que la gramática TSX v0.23.2 lee con errores;
  - los extractores anotarán esos puntos como `unresolved`, con su posición.

## Plataformas

- **Linux amd64:** compila y pasa los tests, en local y en el check obligatorio `check`.
- **macOS:** también compila, y pasa `go vet` y los tests Go.
  - Lo comprueba el job `check-macos` de `platforms.yml`, que no es obligatorio, en macOS 26 arm64 (imagen 20260907.0351.1) con go1.27.1 y el Clang de las Command Line Tools.
  - Primera ejecución: https://github.com/Actaira/Actaira/actions/runs/36590466878 (`evals/sessions/2026-09-29-e1-paso-2a-ci.txt`).
  - El test de fugas no corre ahí: lee `/proc` y es solo para Linux.
  - La E1 y la E2 no tienen que salir solo para Linux. Si se distribuyen binarios de macOS, y cómo, se decide en el paso 1.2b. Apple no admite binarios estáticos.
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
- **Tamaño:** 3,95 MB más en la CLI, por tree-sitter y las tres gramáticas.

## Latencia

- **Código real:** menos de 1 s para 1.000 ficheros por lenguaje, en una goroutine. El objetivo de `discover` es menos de 10 s en el repo p95 del corpus (paso 1.6).
- **Peor caso** (`evals/results/parser-hostil-2026-09-29.json`, `evals/bench/hostile`): ficheros de 1 MB hechos para que el parser trabaje, sin plazo, cada uno en su proceso:

| Caso | Gramática | Tiempo | Memoria máxima del proceso |
|---|---|---|---|
| `a<` repetido (genéricos sin cerrar) | TypeScript | 2,3 s | 1.218 MB |
| `(a,` repetido | TypeScript | 2,0 s | 1.082 MB |
| `{` repetido | TypeScript | 0,33 s | 266 MB |
| `<div>` repetido | TSX | 0,16 s | 83 MB |
| `(` o `[` repetidos | Python | 0,27 s | 258 MB |

- **Plazo por fichero:** el plazo del contexto corta el tiempo, pero no la memoria, que tree-sitter reserva antes de que el callback se entere. `TestADeadlineStopsAHostileParse` para 1 MB hostil en menos de 1 s con un plazo de 50 ms.
- **Paso 1.4:**
  - los extractores fijan un plazo por fichero;
  - anotan como `unresolved` lo que no termina;
  - parsean los ficheros de uno en uno, así que la memoria máxima es la de un fichero, no la suma.
  - El límite de 1 MB por fichero ya está en la épica.

## Errores

- **Código roto:** se parsea igual, con nodos ERROR y MISSING, que los extractores anotan como `unresolved`.
- **Un fichero que no termina de parsearse en su plazo:** `Parse` devuelve un error que envuelve `context.DeadlineExceeded`, y el extractor lo anota como `unresolved`.
- **Una gramática con una versión de ABI incompatible:** `SetLanguage` devuelve error y `Parse` lo propaga, con el lenguaje en el mensaje.
- **La etiqueta v0.25.0 de go-tree-sitter ya no está en GitHub:** solo en el proxy de Go (proxy.golang.org). Se baja de ahí y la verifican `go.sum` y sum.golang.org. Con `GOPROXY=direct` no se encontraría. Si el proyecto publica una versión nueva, se sube en su propio PR, con esta medición repetida.
- **Sin cgo** (`CGO_ENABLED=0`): los paquetes que usan las gramáticas no compilan ("build constraints exclude all Go files" en sus bindings). La CLI aún compila porque todavía no los importa; dejará de hacerlo en el paso 1.5, cuando los use.

## Reversión

Los extractores solo ven `pkg/extract/treesitter`, así que cambiar a WASM (opción B) toca ese paquete y la distribución, no los extractores.
