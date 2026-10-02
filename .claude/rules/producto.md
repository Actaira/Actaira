---
paths:
  - "docs/PLAN.md"
  - "docs/epicas/**"
  - "docs/spec/**"
  - "cmd/**"
  - "pkg/**"
  - "internal/**"
---

# Reglas del vocabulario de producto

Valen para el plan, las épicas, la especificación y todo lo que enseña Actaira (`CLAUDE.md`, doctrina de producto 2):

- **Detectada, potencial y efectiva son tres palabras exactas y nunca se mezclan.** Detectada: la tool existe en el código o en el listado que ve el agente. Potencial: la base de conocimiento dice qué podría hacer. Efectiva: una API de identidad confirma que la credencial lo permite.
- **Lo que declara un servidor MCP (sus tools, descripciones y anotaciones) se compara con lo potencial según la base, no con "lo detectado".** Las tools de una instantánea pública salen como tools de la instantánea, no como detectadas (`docs/cobertura.md`) (F-0028).
- **Si un encargo usa una de estas palabras con otro sentido, se escribe la de la doctrina** y se anota la diferencia como discrepancia en `docs/estado/` (F-0028).
