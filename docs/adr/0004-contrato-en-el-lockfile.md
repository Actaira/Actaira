# ADR 0004: el contrato de capacidades en `actaira.lock`

- **Estado:** aceptado.
- **Fecha:** 2026-10-02.
- **Decide:** la E1, paso 1.3 (`docs/epicas/E1.md`), con la decisión de Marcos del 2026-10-02 de llevar el contrato al lockfile (`docs/PLAN.md`, sección 0, "El contrato de capacidades").

## Contexto

El contrato de capacidades es la declaración, por agente, de lo que debe poder hacer: capacidades permitidas y prohibidas, límites por operación y por periodo, dominios de salida, responsable y caducidad. Marcos decidió que va en el esquema v1 de `actaira.lock`, en el formato abierto Agent Capability Manifest (ACM, borrador en `docs/spec/acm.md`).

Choca con dos cosas ya decididas:

- `actaira.lock` es JSON canónico sin espacios (ADR 0002): el fichero entero es una sola línea, que nadie puede editar ni revisar a mano en un PR;
- `actaira lock` genera el fichero a partir del repo y `lock --check` lo compara byte a byte. Un bloque escrito a mano dentro de un fichero generado no tiene de dónde regenerarse.

Además, la ronda única del paso 1.2c dejó aquí cinco preguntas (altos 3 y 4, medio 12, bajos 20 y 21, en `docs/estado/E1.md`).

## Decisión

1. **La persona escribe el contrato en `actaira.intent.json`**, en la raíz del repo, en formato ACM y con espacios: es lo que se lee y se revisa en el diff del PR.
2. **`actaira lock` lo valida y copia su forma canónica al bloque `intent` del lockfile.** El bloque es una copia, nunca la fuente: `lock --check` falla (código 1) si no coincide con el fichero. Sin `actaira.intent.json`, el bloque no existe y cada agente sale "sin contrato", no como error.
3. **Semántica (ACM v0):**
   - `allow` es la lista completa de lo permitido: una capacidad potencial fuera de `allow` rompe el contrato;
   - `deny` prohíbe de forma explícita y gana a `allow`. Una capacidad en las dos listas es un error de validación;
   - sin comodines en la v0;
   - los importes son enteros en la unidad mínima de su moneda, con el código ISO 4217 (ADR 0002, regla 3);
   - un contrato en `draft`, propuesto por `actaira intent init` (E2), lleva `confidence: inferred`, como pidió Marcos, y no cuenta para nada hasta que una persona lo pasa a `accepted` con `accepted_by` y `accepted_at`.
4. **Lo que no puede pasar en silencio:**
   - **caducado:** un contrato pasada su fecha sale "contrato caducado" y hace fallar el check de la E2 hasta que se renueva, para que lo que prohibía no deje de protegerse sin que nadie lo vea (alto 4);
   - **huérfano:** un contrato cuyo agente ya no está en el lockfile (porque su fichero se movió o se renombró, y su `id` cambió) es una entrada inválida: `lock` sale con el código 2 e `intent validate` con el 1, los dos con el `id` en el mensaje (alto 4). La persona actualiza el `id` del contrato en el mismo PR que mueve el agente, y el cambio se ve en el diff;
   - **cambiado en el mismo PR:** el check de la E2 evalúa la cabeza contra el contrato de la base, y un cambio del contrato es un hallazgo propio que hay que aceptar (alto 3). `accept` no puede anular un `deny`;
   - **no comprobable:** una tool con `effect: unknown`, `unresolved` o de una instantánea no cuenta como dentro del contrato; el comentario dice "contrato no comprobable para N tools" y nunca "cumple" (medio 12, F-0029).
5. **Errores:** un `actaira.intent.json` inválido (esquema, un decimal, una capacidad mal formada) es un error de la entrada, no interno: `lock` sale con el código 2 y el motivo, e `intent validate` con el 1 (bajo 21). Las cadenas se normalizan a NFC al leerlas, como el resto de datos del lockfile (ADR 0002, regla 4).
6. **Versión:** el bloque lleva `acm_version`. El esquema v1 del lockfile acepta el ACM 0; aceptar otro es un cambio del esquema, con su test de compatibilidad hacia atrás (bajo 21).

## Límites conocidos (ronda 3 del paso 1.3; decisión de Marcos del 2026-10-03, opción B)

Se corrigen en el paso 1.4 de la E1, que es donde un extractor los haría reales, con sus tests escritos en ese paso:

1. **El `id` solo es estable mientras la definición sea la única de su tipo, framework, fichero y nombre.** Con dos agentes iguales en esas cuatro partes, el ordinal decide el `id`: añadir, quitar o reordenar uno mueve el contrato a otro agente sin error de huérfano, porque los dos `id` siguen en el lockfile. Hasta que haya una regla que lo impida, el punto 4 ("lo que no puede pasar en silencio") no cubre este caso.
2. **El nombre y la versión del paquete de un servidor MCP no se comprueban.** Un especificador privado con credencial (`git+https://usuario:token@…`, una URL de tarball con `?token=…`) llegaría al lockfile. Es la fuga de F-0034 en un campo que su corrección no miró.

## Opciones

| Opción | A favor | En contra |
|---|---|---|
| A. Fichero fuente `actaira.intent.json` que `lock` copia al bloque (la elegida) | Se lee y se revisa en el PR; el lockfile sigue siendo generado y canónico; el cambio del contrato se ve como tal | Dos sitios: el fichero y su copia. `lock --check` los ata |
| B. Solo órdenes `actaira intent` que editan el bloque | Siempre válido | Nadie revisa en el PR lo que cambió: el lockfile es una línea |
| C. Lockfile con espacios y forma canónica solo para los hashes | Un solo fichero | Cambia el ADR 0002 y la comparación byte a byte de `lock --check` |

## Por qué esta

El contrato es lo que una persona firma y otra revisa. Tiene que leerse en el diff del PR, y el lockfile canónico no se lee. La copia en el lockfile mantiene lo que ya da el ADR 0002 (un fichero determinista que la nube y otras herramientas comparan) y lleva el contrato a donde lo usan la E2, la E3 y la nube.

## Coste

- Un fichero más en el repo del usuario, solo si escribe un contrato.
- El esquema del ACM y su validación, en un paquete de `pkg/` (`pkg/intent`), que también usará `actaira-cloud`.
- La validación en Go repite lo que dice el JSON Schema y añade lo que un esquema no puede expresar. Un test valida los mismos ficheros con los dos y exige el mismo resultado, salvo las diferencias escritas una a una en el test con su motivo (L-012), con una biblioteca de JSON Schema que solo usan los tests.
- `actaira.intent.json` se lee con `encoding/json/v2` de Go 1.27, que rechaza claves repetidas o con otras mayúsculas, UTF-8 inválido y números que no son enteros escritos con dígitos (F-0030).

## Latencia

Leer y validar un fichero de unos KB al generar el lockfile: despreciable frente a los extractores. Se mide con el resto de `discover` en el paso 1.6.

## Errores

Los del punto 5 de la decisión, con sus tests en el paso 1.3.

## Reversión

Pasar a la opción B o C exige una versión nueva del esquema del lockfile, con su test de compatibilidad hacia atrás; `actaira.intent.json` se puede seguir leyendo para migrar.
