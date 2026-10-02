# ADR 0002: `actaira.lock` en JSON canónico propio, un subconjunto estricto de JCS

- **Estado:** aceptado.
- **Fecha:** 2026-09-29.
- **Decide:** la E1 (`docs/epicas/E1.md`, pasos 1.1 y 1.3). Se construye en `pkg/lock/canonical.go` en el paso 1.3.

## Contexto

`actaira.lock` se commitea en el repo del usuario y `actaira lock --check` lo vuelve a generar en la CI para compararlo byte a byte. La E1 exige el mismo fichero en 10 ejecuciones. Los hashes de las tools (`schema_hash`, `description_hash`) son el SHA-256 de un JSON, así que ese JSON tiene que salir igual en cualquier máquina y con cualquier versión de Go. La nube (`actaira-cloud`) y otras herramientas leen y comparan el mismo fichero.

## Decisión

El JSON canónico de Actaira es **JCS (RFC 8785, https://www.rfc-editor.org/rfc/rfc8785) restringido a lo que el lockfile necesita**:

1. **Claves de objeto ordenadas como en JCS:** por las unidades de código UTF-16 de su nombre (RFC 8785, sección 3.2.3), no por los bytes UTF-8.
2. **Sin espacios** entre elementos.
3. **Solo enteros,** dentro del rango que JavaScript representa sin pérdida (de -(2^53 - 1) a 2^53 - 1). Un número en coma flotante o fuera de ese rango es un error, no se redondea. Con esa regla, la serialización de números de JCS (la de ECMAScript) da siempre los dígitos del entero, sin exponente ni decimales.
4. **Cadenas en UTF-8 válido y normalizadas a NFC antes de serializar.** JCS no normaliza Unicode y pide conservar las cadenas tal cual (RFC 8785, sección 3.1). Por eso la normalización es parte de construir los datos del lockfile, no del serializador: el mismo nombre escrito con caracteres compuestos o descompuestos da el mismo hash, y el serializador rechaza una cadena que no esté en NFC en vez de cambiarla. Un texto con UTF-8 inválido es un error; `encoding/json` lo cambiaría en silencio por U+FFFD.
5. **Escapes de JCS** (RFC 8785, sección 3.2.2.2): `"` y `\` con barra; los caracteres de control de U+0000 a U+001F con `\b`, `\t`, `\n`, `\f`, `\r` o `\u00xx` en minúsculas; todo lo demás, incluidos U+2028 y U+2029, tal cual. `encoding/json` de Go no sirve: escapa `<`, `>` y `&` si no se desactiva, escapa U+2028 y U+2029 incluso con `SetEscapeHTML(false)` y ordena las claves de los mapas por bytes UTF-8 (https://pkg.go.dev/encoding/json).

Con las reglas 3 y 4, la salida de Actaira es, byte a byte, la que daría cualquier implementación de JCS sobre los mismos datos. Los tests del paso 1.3 lo fijan con vectores propios, con los del RFC que caen dentro del subconjunto y comparando cada salida con `jsontext.Value.Canonicalize` de la biblioteca estándar de Go 1.27, que implementa JCS (https://pkg.go.dev/encoding/json/jsontext#Value.Canonicalize), como oráculo independiente.

## Opciones

| Opción | A favor | En contra |
|---|---|---|
| A. Subconjunto estricto de JCS, con código propio | Sin una biblioteca de JCS (la comprobación de NFC usa `golang.org/x/text/unicode/norm`, del proyecto Go, BSD-3-Clause; paso 1.3 de la E1); compatible con JCS; los errores (coma flotante, UTF-8 inválido) se ven en vez de redondearse | Código propio que probar |
| B. JCS completo con una librería | Menos código | Una dependencia en `pkg/`, que es API pública; admite coma flotante, que en un lockfile solo trae diferencias entre máquinas; no normaliza Unicode |
| C. `encoding/json` con mapas ordenados | Viene con Go | Ordena por bytes UTF-8, escapa HTML y U+2028/U+2029: no coincide con JCS, y cualquier cambio de Go en esos detalles cambia los hashes |
| D. CBOR determinista u otro formato binario | Compacto | El lockfile se lee en los diffs de los PR; un formato binario no |
| E. Serializar con cualquier codificador y pasar por `jsontext.Value.Canonicalize` | JCS de la biblioteca estándar, sin código propio | Admite coma flotante (su documentación avisa de que los enteros de más de 2^53 pierden precisión) y no normaliza ni rechaza lo que no está en NFC (sí rechaza por defecto el UTF-8 inválido: `verificador-apis`, paso 1.3 de la E1). Las reglas 3 y 4 habría que comprobarlas aparte igualmente. Se usa como oráculo en los tests, no como serializador |

## Por qué esta

El lockfile y los hashes tienen que salir iguales en cualquier sitio, también dentro de años y en otros lenguajes. Un subconjunto de un estándar publicado se puede reimplementar en la nube o en otra herramienta sin leer el código de Actaira, y lo que no está en el subconjunto no puede aparecer por accidente.

## Coste

- Un serializador propio de unas pocas decenas de líneas, con sus tests de vectores fijos.
- Los números del lockfile solo pueden ser enteros: un tamaño, una línea o un contador. Si alguna vez hiciera falta un decimal, iría como cadena.

## Latencia

La serialización es lineal en el tamaño del lockfile. `actaira discover` tiene que tardar menos de 10 s en el repo p95 del corpus (E1, "Listo cuando"), y el JSON canónico es una parte pequeña de eso. Se mide con el corpus en el paso 1.6.

## Errores

- **Un valor fuera del subconjunto** (coma flotante, entero fuera de rango, UTF-8 inválido): la serialización falla con el campo que lo causó, y `actaira lock` sale con el código 3.
- **Una versión de Go que cambie el orden de los mapas o `encoding/json`:** no afecta, porque el serializador no depende de ellos.

## Reversión

Pasar a JCS completo es compatible hacia delante: todo lockfile ya escrito es JCS válido. Cambiar a otro formato exige subir `schema_version` y el test de compatibilidad hacia atrás del paso 1.3.
