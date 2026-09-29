---
paths:
  - "cmd/**"
  - "pkg/**"
  - "internal/**"
  - "docs/cobertura.md"
---

# Reglas de la vista de cobertura

La definición completa está en `docs/cobertura.md`. Estas son las invariantes que ningún cambio puede romper (F-0017 y F-0018):

- **Ninguna salida da un porcentaje de cobertura ni un veredicto de conjunto** ("cubierto", "OK", un check verde). El resumen es "N de M fuentes conocidas observadas" más lo no visto.
- **Un contador solo da número si se ha visto todo lo que podría cambiarlo.**
  - Si no, dice qué falta: "sin fuente", "uso desconocido" o "llamadas no mediadas: sin fuente".
  - Nunca da 0 por no haber mirado.
  - Solo alimenta los ejes lo que sale de fuentes `observed`.
- **`unseen` (no mirado) y `unresolved` (mirado y no entendido) nunca se mezclan.** Una declaración de fuente sin resolver no crea una fuente y sale en el resumen.
- **Nada hace `observed` una fuente sin haberla leído tal como la ve el agente.** Una instantánea pública del registro MCP no hace `observed` una fuente MCP.
- **`mediated` es pasar por el punto de decisión.** Basta una llamada vista sin él para que una tool no cuente como mediada. La credencial intermediada es otro contador.
- **`actaira.lock` solo lleva lo que sale del repo y no depende de lo que git no versiona.**
  - El recorrido respeta `.gitignore`, no entra en repos anidados y no sigue enlaces simbólicos.
  - Las reglas de ignorado se anotan siempre, como reglas.
- **Cada contador tiene el test que fija su definición,** escrito en rojo antes de construirlo.
