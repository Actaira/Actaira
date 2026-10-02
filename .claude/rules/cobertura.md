---
paths:
  - "cmd/**"
  - "pkg/**"
  - "internal/**"
  - "docs/cobertura.md"
  - "docs/PLAN.md"
  - "docs/epicas/**"
---

# Reglas de la vista de cobertura

La definición completa está en `docs/cobertura.md`. Estas son las invariantes que ningún cambio puede romper (F-0017 y F-0018):

- **Ninguna salida da un porcentaje de cobertura ni un veredicto de conjunto** ("cubierto", "OK", un check verde). El resumen es "N de M fuentes conocidas observadas" más lo no visto.
- **Tampoco un pasaporte, un badge, un informe o una página para terceros:** ninguno dice que un agente o una credencial "cumple" el contrato. Dicen las rupturas vistas en lo observado, con N de M fuentes y lo no visto al lado, y un badge no lleva estado (F-0029).
- **Un contador solo da número si se ha visto todo lo que podría cambiarlo.**
  - Si no, dice qué falta: "sin fuente" o "uso desconocido". Mediadas da el número de lo visto, siempre con "llamadas no mediadas: sin fuente" al lado mientras no haya una fuente que las vea.
  - Nunca da 0 por no haber mirado.
  - Solo alimenta los ejes lo que sale de fuentes `observed`.
- **`unseen` (no mirado) y `unresolved` (mirado y no entendido) nunca se mezclan.** Una declaración de fuente sin resolver no crea una fuente y sale en el resumen.
- **Nada hace `observed` una fuente sin haberla leído tal como la ve el agente.** Una instantánea pública del registro MCP no hace `observed` una fuente MCP.
- **`mediated` es pasar por el punto de decisión.** Basta una llamada vista sin él para que una tool no cuente como mediada. La credencial intermediada es otro contador.
- **`actaira.lock` solo lleva lo que sale del repo y no depende de lo que git no versiona.**
  - Todo lo que git versiona y algún extractor leería se lee o deja una entrada en `coverage.skipped` con su motivo; lo que git no versiona no deja ninguna.
  - El mecanismo lo fijan el paso 1.4 de la E1 y sus tests obligatorios.
- **Cada contador tiene el test que fija su definición,** escrito en rojo antes de construirlo.
