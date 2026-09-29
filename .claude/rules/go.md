---
paths:
  - "**/*.go"
---

# Reglas de Go

- Todos los errores se manejan o se devuelven envueltos con contexto (`fmt.Errorf("...: %w", err)`). Nada de `_ =` para errores sin un comentario que diga por qué.
- Nada de `panic` en código de producción, salvo en `init` para configuración imposible.
- Toda E/S recibe un `context.Context` con tiempo máximo.
- Los tipos públicos de `pkg/` son API estable: cambiarlos exige subir la versión del esquema y un test de compatibilidad.
- Determinismo: mapas iterados siempre por claves ordenadas cuando la salida se guarda o se compara.
- Un fichero generado que se commitea y la CI comprueba (`actaira.lock`, salidas doradas) solo depende de lo que git versiona. El recorrido respeta `.gitignore` en todos los niveles, leído sin ejecutar git, no entra en repos anidados ni submódulos y no sigue enlaces simbólicos. Su test de determinismo compara el mismo repo con y sin ficheros ignorados en disco, no solo varias ejecuciones sobre el mismo árbol (F-0018).
- Los objetos de go-tree-sitter se liberan con `defer x.Close()`.
- Tests con tablas; los fixtures en `testdata/`; nada de red en tests unitarios. Los tests de red y de contenedor llevan `//go:build linux` (E1): el check obligatorio corre en linux/amd64 y `check-skips.sh` exige un F-NNNN de FALLOS.md a todo test que ese check no compile, así que nada de etiquetas propias como `integration`.
- Los logs nunca incluyen contenido de prompts, argumentos de tools ni secretos: solo identificadores y digests.
