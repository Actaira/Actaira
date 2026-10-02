# Backlog: ampliación y comercial

**Para Claude Code.** No se construye nada de aquí sin que Marcos lo abra explícitamente. Cada elemento se convierte en una épica propia, con el mismo formato y el mismo bucle: `/epica`.

| Elemento | Qué abre este elemento | Nota |
|---|---|---|
| Efectos causales de varios saltos (C5 ampliado) | Un cliente lo pide o la cobertura del primer salto se queda corta | Correlación con registros de auditoría; nunca inventar enlaces |
| Gobierno de memoria (C8) | Tres clientes lo piden | Procedencia en escritura; el borrado se comprueba en los almacenes conectados |
| Registros de plataforma (AWS Agent Registry, Agent 365, Copilot Studio, apps de ChatGPT Enterprise) | Clientes Enterprise que tienen agentes fuera de repos | Conectores de solo lectura |
| Importar hallazgos de envenenamiento de tools (Snyk Agent Scan, Cisco MCP Scanner) | Petición de clientes | Se importa su SARIF o JSON; no se reimplementa |
| Tarjetas de agente A2A | Clientes con agentes que llaman a otros agentes | Aristas `delegates_to` y aviso de credenciales en la tarjeta |
| Comentario en merge requests de GitLab | Usuarios de GitLab | Token de proyecto o de grupo |
| Windows nativo | Petición de usuarios | Pipe con ACL; firma con SignPath Foundation |
| BYOC y SCIM | Clientes Enterprise | Plano de control en la nube del cliente |
| Plan Enterprise | Que haya equipo (decisión de Marcos del 2026-10-02) | Sin venta directa: Enterprise llega por adopción interna o por integraciones que exportan el contrato (JSON estable, SARIF, AI-BOM). Incluye BYOC, SCIM, retención larga, la capa de cumplimiento completa y la atestación SOC 2 o ISO 27001 (`docs/PLAN.md`, sección 9) |
| OSCAL y marcos en backlog (ENS, NIS2, DORA, RGPD, NIST AI RMF) | Un cliente lo pide | Anexo DORA y LEI solo con cliente financiero |
| PDF del informe generado en el servidor | Clientes que lo exigen | Coste medido antes de añadir Chromium sin interfaz |
| Azure Marketplace | Clientes que compran por Marketplace | Requisitos de la oferta SaaS de Microsoft comprobados antes de empezar |

## Comercial (cuando el producto funcione en producción; lo abre Marcos)

| Elemento | Qué es |
|---|---|
| Lista de builders y conversaciones | 30 builders con nombre y el guion de 5 preguntas; ningún mensaje sale sin que Marcos lo apruebe |
| Tabla comparada | Snyk Agent Scan y mcplock sobre el mismo corpus, en contenedores desechables, con el permiso de Marcos antes de publicar |
| El estudio | Datos agregados del rastreador, reproducible, con aviso privado previo a los casos graves |
| Lanzamiento | Textos de Show HN, registro MCP y PRs de documentación a los SDK, que aprueba y publica Marcos |
| GitHub Marketplace | Publicar la Action; lo hace Marcos al crear el release |
| LinkedIn y directorios de partners | Cuando haya producto que enseñar |
| Medición de la adopción | Método publicado: búsqueda de código como cota inferior, descargas como ejecuciones y registro voluntario |
| Playground público | Pegar la URL de un repo público y ver sus capacidades, contra el presupuesto global |
