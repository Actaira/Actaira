# Actaira: plan de construcción

**Versión 2.1, 2 de octubre de 2026.** Decisiones de Marcos: el **contrato de capacidades** pasa a ser la idea central del producto (sección 0) y se fija la estrategia de producto: quién es quién, `actaira inspect` con el registro público de servidores MCP como primer lanzamiento, y el builder como primer plan de pago (secciones 0, 2, 5 y 9).

**Versión 2.0 (definitiva), 28 de septiembre de 2026.** Integra todo lo decidido: un solo nombre, sin plazos, prueba de 7 días con topes, despliegue en Azure con escala a cero programado con Claude Code, cumplimiento como capa, y una revisión de coherencia de 52 puntos sobre el texto. Historial: La 1.6 fija el nombre, **Actaira** para todo (núcleo abierto y plataforma); quita todos los plazos, porque el orden lo marcan las dependencias y la prioridad es el núcleo abierto y la plataforma self-serve; adelanta una plataforma self-serve sin runner; y deja el cumplimiento como una capa. La 1.5 añade una fase previa sin código (nombre nuevo porque "seamark" está ocupado, y conversaciones con builders), corrige la cuña (el lockfile por hash ya lo tienen otros; lo propio es la semántica de capacidades), recorta la fase 1 a lo que mueve la adopción y añade las features que el mercado ya da por hechas (flujos tóxicos, SARIF, baseline, Agent Skills, Vercel AI SDK, deriva programada, etiquetas OWASP). La 1.4 recorta lo que no hace falta para probar la cuña: fases acotadas, C0 mínimo, C1 y C2 como un solo lanzamiento, capacidades potenciales frente a efectivas, C8 al backlog, C5 limitado a efectos de primer orden, compliance fuera de la portada, precio con cuota de acciones y los builders como primer cliente de pago. La 1.3 mete la IA donde aporta (sección 3, "La IA dentro") y fija qué va en el código abierto y qué en Actaira Cloud (sección 9). La 1.2 cerró los tres datos que quedaban por comprobar: permisos de Salesforce y de HubSpot contra su documentación, y el anexo A de ISO/IEC 42001 contra el texto de la norma. Plan para construir desde cero (sin código de actaira-sys ni del antiguo seamark en Python; sí su doctrina y sus lecciones) una plataforma self-serve de **assurance continuo para agentes de IA en producción**:

- **Actaira open source**, el núcleo abierto (Apache-2.0) en GitHub: la CLI `actaira`, la GitHub Action y el lockfile `actaira.lock`. Se lo instala el desarrollador.
- **Actaira Cloud**, la plataforma self-serve de pago, que contrata la empresa.
- **La capa de cumplimiento**, opcional, encima de la evidencia de la plataforma. No es la identidad del producto.

Ha pasado dos revisiones adversariales independientes:

- **Técnica** (arquitectura y bloques C0 a C6): 24 hallazgos, 2 críticos.
- **De negocio, cumplimiento y marco legal español** (mercado, C7 a C10 y el conjunto): 21 hallazgos, 3 críticos.

Tras esas dos, hubo tres revisiones más: una externa de 8 puntos (1.4), una hostil de fundador y de inversor con 25 hallazgos (5 críticos) y un barrido de mercado de 20 features (1.5). Todo está aplicado. Cada bloque lleva su tabla de correcciones y la sección 13 recoge lo que cambió el plan entero.

**Nombre:** Actaira para todo. El antiguo nombre provisional, "seamark", se descarta: `github.com/seamark-dev/seamark` es una CLI en Go del mismo nicho. Antes de publicar se comprueba "Actaira" en OEPM y EUIPO y se decide qué pasa con los repos antiguos (fase previa).

**Lema:** Know what every agent can do. Control what it is allowed to do. Prove it.
**En castellano:** sabes qué puede hacer cada agente, decides qué se le permite y lo demuestras.

---

## En una página: qué hace Actaira y qué la hace especial

**El problema.** Las empresas que construyen agentes de IA (y las que los construyen para otros, los builders) no saben qué **puede** hacer cada agente. Tampoco saben:

- qué cambió cuando un servidor MCP, un permiso o una tool cambian sin tocar su código;
- qué rompe si cae una credencial;
- cómo demostrárselo a un cliente o a un auditor.

La observabilidad dice qué hizo el agente ayer. Nadie dice, de forma sencilla, qué puede hacer hoy.

**Qué es Actaira: el contrato de capacidades de tus agentes.** Declaras qué puede hacer cada agente; Actaira lo vigila en cada PR, te da los permisos justos, demuestra si alguien puede saltárselo, lo hace cumplir en ejecución y te da la prueba firmada para tu cliente. El contrato se escribe una vez en el repo y es la única fuente de verdad, del PR al auditor (sección 0).

**Qué hace Actaira, de menos a más:**

1. **En el repo, gratis (Actaira open source).** `actaira inspect` dice qué hace cada tool de un servidor MCP antes de instalarlo, sin ejecutar nada. Además, Actaira lee el código del agente, sus tools, sus servidores MCP y sus skills, y genera un **lockfile de capacidades** con el contrato de cada agente. En cada PR que cambia algo importante comenta:
   - "este cambio le da al agente la capacidad potencial de borrar clientes, por esta causa, y afecta a estos 3 agentes";
   - si el cambio **rompe el contrato**, y en ese caso el check falla;
   - el camino, paso a paso, desde una entrada no fiable hasta una capacidad irreversible;
   - avisos de **flujos tóxicos**: entrada no fiable, más datos sensibles, más salida al exterior en el mismo agente.
2. **En la nube, self-serve (Actaira Cloud, fase 2).** Para el builder, primero: un **contrato por cliente** y un **pasaporte por agente** que puede enseñar a sus clientes. Además, la flota entera, el historial de capacidades, alertas cuando algo cambia e IA incluida sin clave. Prueba de 7 días con topes, y se paga con tarjeta.
3. **Capacidades efectivas (fase 3).** Un runner en la infraestructura del cliente, sin sacar sus secretos, confirma contra AWS, Kubernetes, GitHub, Salesforce, Zendesk o HubSpot lo que la credencial del agente permite de verdad. Avisa si un permiso cambia aunque nadie toque el código, y propone desde el contrato la credencial mínima.
4. **Control (fase 4).** Bloquea antes de que ocurra: el contrato se compila en política, con aprobaciones humanas, presupuestos de autonomía y kill switch granular. La credencial la guarda Actaira, así que el agente no puede saltarse el control.
5. **Prueba (fase 5).** Evidencia firmada por el propio cliente que **caduca sola** cuando cambia algo de lo que depende, y el pasaporte firmado. Encima, una **capa de cumplimiento** opcional que la traduce a SOC 2, ISO 27001, ISO 42001, AI Act, AIUC-1 y CSA AI-CAIQ.

**Lo especial, comprobado frente a Snyk, Cisco, mcplock, agent-bom, Vanta, Noma, Obsidian y LangSmith:**

| Qué | Por qué nadie más lo da así |
|---|---|
| **El contrato de capacidades** | Una sola declaración por agente que se usa en el PR, en las credenciales, en ejecución y ante terceros. No está comprobado frente a la competencia: se comprueba al cierre de la E2, con `verificador-apis`, antes de que la web diga "único" |
| **Capacidades con efecto, causa y blast radius en el PR** | Los demás comparan hashes o inventarios; Actaira dice "gana `customer.delete` porque `customer-mcp` pasó de la 2.3.1 a la 2.4.0, y afecta a 3 agentes" |
| **Detectada, potencial y efectiva, separadas** | Lo gratis dice lo que tu código podría exponer; lo de pago, lo que el agente puede de verdad. Honesto y fácil de vender |
| **Evidencia que caduca por dependencia**, firmada por el cliente y anclada fuera | Los demás prueban que un registro no se alteró; ninguno, que la conclusión sigue siendo cierta |
| **Modo builder**, con contrato por cliente y pasaporte por agente | Pensado para quien opera agentes para otras empresas, que puede enseñarlo y revenderlo |
| **IA que nunca rebaja un riesgo** | La IA propone y explica, pero solo puede subir la gravedad y nunca decide |
| **Cobertura honesta** | Dice siempre qué no ve (lo `unseen`), en vez de prometer control total: N de M fuentes observadas, nunca un porcentaje (`docs/cobertura.md`) |

**En una frase:** Actaira te dice qué puede hacer cada agente, te deja decidir qué se le permite y te da la prueba. Lo que decides queda escrito en el contrato de capacidades. Empieza gratis en el PR y crece hasta una plataforma self-serve.

---

## 0. La idea en seis líneas

**La frase:** Actaira, el contrato de capacidades de tus agentes. Declaras qué puede hacer cada agente; Actaira lo vigila en cada PR, te da los permisos justos, demuestra si alguien puede saltárselo, lo hace cumplir en ejecución y te da la prueba firmada para tu cliente.

- **Actaira open source (gratis):** lo que tu código **podría** exponer, es decir, las capacidades potenciales, y si un cambio rompe el contrato.
- **Actaira Cloud (de pago, self-serve):** lo que el agente desplegado **puede hacer de verdad**, es decir, las capacidades efectivas, y el control y la prueba encima.

**La idea:**

1. **Quién es quién** (todos los ejemplos del plan son hipotéticos):
   - **El desarrollador es la distribución.** Usa Actaira open source gratis, sin cuenta y sin ruido. El gancho es una pregunta: "¿qué hace este MCP?", que responde `actaira inspect` antes de instalarlo.
   - **El builder es el primer cliente de pago:** quien construye y opera agentes para varias empresas, por ejemplo uno de atención al cliente cuyos agentes tocan Salesforce, Zendesk o Stripe de cada cliente. Tiene el problema multiplicado por cliente, y paga por el contrato y el pasaporte que enseña a sus clientes.
   - **Enterprise llega sin venta directa:** por adopción interna, o por integraciones que exportan el contrato (JSON estable, SARIF, AI-BOM). El plan Enterprise queda en el backlog hasta que haya equipo.
2. **Qué dolor:** nadie sabe qué **puede** hacer cada agente hoy, qué cambió sin tocar su código, qué rompe si cae una credencial, ni cómo demostrarlo a un cliente o a un auditor.
3. **Qué no es:** ni observabilidad, ni evals, ni gateway de LLM. Eso lo tienen LangSmith, Langfuse o el propio builder, y Actaira lo **ingiere**.
4. **Qué es:** un grafo vivo que une **activos, capacidades, acciones, consecuencias y evidencia**, con el **contrato de capacidades** de cada agente en el centro. Encima lleva control en tiempo de ejecución y un **estado de evidencia** que se vigila 24/7 y caduca solo cuando cambia algo de lo que depende.
5. **Cómo entra:** gratis y sin hablar con nadie. `actaira inspect` responde "¿qué hace este MCP?" sin instalar ni ejecutar nada. `actaira` genera en el repo un **lockfile de capacidades** (`actaira.lock`), con el contrato, y **solo comenta en un PR cuando cambian capacidades** de escritura o irreversibles o se rompe el contrato, con el Capability Diff, la causa y el blast radius.
6. **Cómo cobra:** primero, el **plan Builder**: contrato por cliente y pasaporte por agente, con la marca del builder. Después, el plan **Team**. Actaira Cloud aporta además la flota, las capacidades efectivas, el control en tiempo de ejecución, la evidencia firmada, la exportación a cumplimiento y el soporte. Se cobra por agente activo, con una cuota de acciones gobernadas incluida en cada plan (sección 9).

**A quién va el núcleo abierto, y qué pasa con el antiguo seamark en Python:** va a quien **construye** agentes de producto (OpenAI Agents SDK, LangGraph, Vercel AI SDK, MCP, Agent Skills), no a quien configura agentes de código. El repo en Python (`seamark`, configuración de Claude Code, Cursor y Codex) se archiva con un aviso o se renombra a `-legacy`, según se decida en la fase previa, y su configuración pasa a ser una fuente más del grafo más adelante.

**Promesa honesta de la "tranquilidad":**

- **Qué hace:** Actaira vigila 24/7 lo que está conectado y mediado, bloquea lo que la política prohíbe en los caminos mediados y dice siempre qué no ve.
- **Si Actaira deja de vigilar**, el runner del cliente lo detecta por un latido y el estado pasa a `error`. El silencio nunca se lee como "todo bien".
- **Lo que no es:** un informe de aseguramiento (ISAE 3000) ni una opinión de auditoría, y así se dice en cada página que ve un tercero.

### El contrato de capacidades

**Qué es.** El equipo declara una vez en el repo qué debe poder hacer cada agente. Es el bloque `intent` de `actaira.lock`, en un formato abierto, el **Agent Capability Manifest** (ACM), cuyo borrador se publica en `docs/spec/` en la E1. Esa misma declaración se usa en cuatro sitios, y es la única fuente de verdad del PR al auditor:

| Dónde | Para qué | Épica |
|---|---|---|
| En el PR | Dice si el cambio rompe el contrato, y entonces el check falla. Enseña el camino desde una entrada no fiable hasta una capacidad irreversible | E2 |
| En las credenciales | Compila la credencial mínima exacta (política IAM, clave restringida de Stripe, token de grano fino de GitHub) y propone recortarla con un PR que fusiona una persona | E5 |
| En ejecución | Se compila en política Cedar, primero en modo sombra y después aplicada | E6 |
| Ante terceros | El pasaporte por agente: la v1, con enlace y badge, en la E3; el firmado, en la E7 | E3 y E7 |

**Qué lleva, por agente:** capacidades permitidas y prohibidas, límites por operación y por periodo, dominios de salida permitidos, responsable y caducidad.

**Doctrina** (se suma a la de `CLAUDE.md`):

1. **El contrato lo escribe y lo firma una persona.** `actaira intent init` puede proponer un borrador a partir del lockfile actual, marcado `inferred`, que no vale hasta que alguien lo acepta. En el repo, la firma es la aceptación registrada (quién y cuándo), que protege la revisión del PR; la firma criptográfica llega con el pasaporte firmado de la E7.
2. **La exposición máxima solo se calcula con límites escritos** en el contrato o en la política. Si falta un límite, sale "sin límite", nunca un número inventado.
3. **Sin contrato, el agente sale "sin contrato",** no como error. Un contrato pasada su caducidad se enseña como caducado; qué pasa entonces con lo que prohibía lo decide el paso 1.3 de la E1.
4. **Actaira sigue sin ejecutar código del repo analizado.** Los tests de ataque los genera Actaira, con tools simuladas, y los ejecuta el cliente en su propia CI si quiere (opt-in). Su resultado entra como evidencia en la E7.

**Reparto por épica:**

- **E1:** el bloque `intent` en el esquema v1 del lockfile y el borrador del ACM, con su JSON Schema y su validador en la CLI (`actaira intent validate`).
- **E2:** `actaira intent init`; el diff contra el contrato, con el check en rojo si se rompe; y la alcanzabilidad estática desde entradas no fiables hasta capacidades irreversibles, también la heredada entre agentes (subagentes y handoffs), con el camino paso a paso.
- **E3:** el contrato por cliente del builder; el pasaporte por agente v1, con enlace y badge; los avisos a todos los clientes que usan un MCP cuando una versión nueva añade una capacidad irreversible; y la máquina del tiempo sobre el historial de lockfiles.
- **E5:** el compilador de credenciales desde el contrato y el PR que recorta la credencial hasta el contrato, validado con el simulador oficial donde lo hay.
- **E6:** el contrato compilado en política Cedar, el modo sombra antes de aplicar y la exposición máxima acotada.
- **E7:** el pasaporte firmado, la máquina del tiempo con evidencia y los tests de ataque que pasa el cliente, como evidencia.

---

## 1. Qué cubre, punto por punto

| Necesidad | Cómo la cubre | Dónde | Límite honesto |
|---|---|---|---|
| 0. Qué debe poder hacer cada agente | El contrato de capacidades (sección 0): bloque `intent` de `actaira.lock`, en el formato abierto ACM, usado en el PR, las credenciales, la ejecución y el pasaporte | E1 (esquema), E2 (PR), E3 (pasaporte), E5, E6 y E7 | Lo escribe y lo acepta una persona; sin contrato, el agente sale "sin contrato" |
| 1. Inventario real de agentes | Gemelo digital por agente y versión: modelo, hash del prompt, tools, servidores MCP, subagentes, memoria, secretos referenciados, identidades, despliegues | C1 (repo), C3 y C4 (runtime), C9 (flota) | Solo lo que está en repos conectados o pasa por el runner, el SDK u OTel; lo demás sale como "no inventariado" |
| 2. Lo que el agente **puede** hacer | Grafo de capacidades: agente, tool, credencial, sistema, acción; declaradas, condicionales y efectivas | C2 (declaradas), C3 (efectivas) | Lo efectivo solo existe para fuentes que exponen permisos reales; un scope OAuth grueso no es una capacidad efectiva |
| 3. Fan-out causal | Primer salto: tool call y su efecto directo confirmado, con correlación con los registros de auditoría de los SaaS; varios saltos en la fase 6 | C5 | Los SaaS no propagan trazas; se publica qué porcentaje de efectos se confirma de verdad |
| 4. Políticas que bloquean antes | Punto de decisión Cedar en el runner, con **intermediación de credenciales**: el secreto vive en el runner y el agente nunca lo ve | C4 | Lo no intermediado sale como hueco de cobertura, medido como N de M credenciales intermediadas, con la lista de las que no lo están |
| 5. Blast radius | Consulta sobre el grafo: credencial, agentes, sistemas, clientes, despliegues; "si quito este MCP, qué se rompe" | C2, C3, C9 | Tan completo como el grafo; la respuesta dice qué fuentes faltan |
| 6. Cambios de capacidad sin tocar código | Vigilantes de permisos reales, políticas IAM y esquemas de tools MCP (hash por tool, calculado en la sesión real del agente) | C1, C3, C4 | Sondeo cada 15 minutos o menos por fuente, y webhooks donde existen |
| 7. Evidencia y procedencia | Libro firmado por el runner con clave del cliente, cabezas de árbol en un log de transparencia externo y sello RFC 3161; verificación offline con `actaira verify` | C6 | Prueba integridad y dependencias, no que la política sea buena |
| 8. Presupuesto de autonomía | Límites por sesión y periodo, con contadores compartidos entre réplicas | C4 | Cuenta lo mediado |
| 9. Gobierno de memoria | **Backlog:** entra en la fase 6 | C8 | Diseño escrito; se construye en la fase 6 |
| 10. Kill switch granular | Reglas de corte por agente, tool, destino, importe, MCP o despliegue; también un corte local que no depende de la nube | C4 | p95 de 10 s como máximo en caminos mediados, medido |
| Capa de cumplimiento (opcional) | SOC 2, ISO/IEC 27001, ISO/IEC 42001, AI Act, AIUC-1 y CSA AI-CAIQ; CSV y JSON, Vanta y Drata. El resto de marcos, en backlog | C7 | Aporta evidencia a controles de los caminos mediados, con su cobertura y conciliación; no certifica |
| Assurance 24/7 | Estado de evidencia por agente y cliente, recalculado con cada cambio; alertas; resumen diario; latido | C6, C9 | La vigilancia es automática; el soporte humano 24/7 no existe hasta que haya equipo (sección 9) |

---

## 2. El mercado, comprobado a 28 de septiembre de 2026

**Lo que valida el mercado:**

- **Compras.** Cisco compró Astrix, de identidades de máquinas y agentes, por unos 400 M USD. OpenAI compró Promptfoo, una CLI abierta con adopción masiva. Check Point compró tres startups, entre ellas Cyata, de seguridad de agentes. Lo que se compra es adopción y posición.
- **LangChain.** LangSmith Fleet (marzo de 2026) trae registro de agentes, versiones, RBAC y modelo de credenciales. El LLM Gateway, en beta pública desde el 30 de julio de 2026, trae límites de gasto, PII y secretos, y anuncia que llevará esos controles a tools, MCP y llamadas entre agentes.
- **Los proveedores.** Stripe recomienda claves restringidas para agentes. MCP obliga a tratar las anotaciones de las tools como pistas no fiables.

**Competencia, por capa:**

| Quién | Qué tiene | Qué no tiene y es de Actaira |
|---|---|---|
| LangSmith (Fleet y Gateway) | Registro, versiones, RBAC, credenciales, gateway de LLM, trazas, evals; control de tools y MCP anunciado | Neutralidad de framework, permisos efectivos por identidad, cambios sin cambio de código, evidencia que caduca, multicliente |
| Snyk Agent Scan (Apache-2.0, antes mcp-scan de Invariant) | Escaneo de configuraciones de agentes, MCP y skills; **fijación de tools por hash** (rug pull) y **análisis de flujos tóxicos**, gratis; modo CI; `snyk aibom` en CycloneDX | La semántica (qué hace cada tool y por qué, con efecto, causa y blast radius entre agentes); el contrato de capacidades; potencial frente a efectiva; evidencia que caduca; modo builder |
| Galileo Agent Control (código abierto, marzo de 2026) | Plano de control centralizado de guardrails | Grafo de capacidades, blast radius, evidencia |
| AWS AgentCore Policy (GA, marzo de 2026) | Cedar sobre las tools del gateway de AgentCore | Pensado para el ecosistema AgentCore; no hace grafo ni evidencia multiplataforma |
| Microsoft Agent 365 y Entra Agent ID | Registro e identidad de agentes en el mundo Microsoft | Neutralidad, diff en PR, evidencia verificable |
| Noma | Inventario, riesgo y control de acceso de agentes y MCP en tiempo de ejecución, para el CISO | Entrada self-serve por el repo, lockfile, evidencia que caduca |
| Obsidian (AI Blast Radius) | Autoridad efectiva por OAuth en SaaS, con evaluación gratuita | Diff en PR, runtime propio, evidencia |
| Zenity | Seguridad de agentes y MCP para empresas | Entrada de desarrollador y self-serve |
| mcplock, MCPTrust, GuardMCP, AgentAuditKit, mcp-pin (código abierto, pequeños) | Lockfile de tools MCP por hash, verificación en CI, SARIF, etiquetas OWASP | No clasifican efectos ni calculan blast radius |
| Cisco aibom | AI-BOM en CycloneDX y SPDX, SARIF y `diff` entre dos AIBOM | Diff de inventario, no de capacidades con efecto |
| agent-bom (Apache-2.0) | Grafo, rutas de alcance, gateway en tiempo de ejecución, evidencia de cumplimiento, servidor MCP | Sin caducidad de evidencia por dependencia ni anclaje externo; sin modo builder |
| Vanta AI Governance (acceso anticipado, 30 jul 2026) | Inventario de agentes, qué puede hacer cada uno, trust center | Pasa de ser destino de exportación a competidor desde arriba (GRC); sin diff en el PR ni capacidades efectivas por identidad |
| Plimsoll Action | Diff de capacidades por release a partir de lo observado en ejecución (eBPF), comentario y SARIF | Trabaja sobre lo observado, no sobre el código |

**Dónde se gana:** el lockfile por hash ya **no** es diferencial, y los flujos tóxicos tampoco: Snyk Agent Scan ya fija las tools por hash y detecta flujos tóxicos gratis, y varias herramientas abiertas hacen lo primero. Aquí son solo lo mínimo que se espera. La diferencia que se enseña en `actaira inspect` y en el comentario del PR es doble:

- **la semántica:** qué hace cada tool y por qué. Traducir tools a **capacidades con efecto** ("gana `customer.delete`"), decir la **causa** y el **blast radius entre agentes**, y separar **potencial** de **efectiva**;
- **el contrato:** qué debe poder hacer cada agente, y si el cambio lo rompe (sección 0).

Antes del lanzamiento se publica una tabla comparada y medida contra Snyk Agent Scan y mcplock sobre los mismos repos. Al cierre de la E2, `verificador-apis` comprueba a los competidores del momento antes de que la web diga "único". Encima, lo que nadie tiene junto:

- el **contrato de capacidades**, usado en el PR, las credenciales, la ejecución y el pasaporte;
- el **diff de capacidades con efecto, causa y blast radius** en el PR;
- las **capacidades efectivas** confirmadas por identidad, a la vista del desarrollador;
- la **evidencia que caduca** cuando cambia aquello de lo que depende, firmada por el cliente y anclada fuera;
- el **modo multicliente para builders**, con contrato por cliente y pasaporte por agente;
- la **regla de monotonía** de la IA: puede subir la gravedad, nunca bajarla.

**Dónde se puede perder:** si LangSmith cierra tools y MCP, si Snyk añade semántica de capacidades, o si Vanta AI Governance y agent-bom llegan desde arriba a lo efectivo y a la evidencia antes de que el núcleo abierto tenga adopción. La ventana depende de lanzar pronto. La defensa es la neutralidad de framework y la evidencia verificable por terceros.

**El foso a largo plazo no es el código**, porque `actaira diff` lo puede copiar una empresa grande. Es el conocimiento estructurado de capacidades de agentes, que crece con cada integración:

- semántica de frameworks, tools y MCP;
- semántica de IAM y permisos por sistema (por ejemplo, este permission set de Salesforce más esta tool MCP más esta identidad dan `customer.read`, `customer.update` y `customer.delete`), explicando siempre el porqué;
- observaciones en tiempo de ejecución y decisiones de política;
- la evolución histórica de las capacidades.

**Reparto:**

- **Abierta (motor de adopción y comunidad):** la semántica de tools públicas y de MCP.
- **En Actaira Cloud (el foso):**
  - los mapeos de permisos por sistema y sus combinaciones;
  - la historia de deriva de capacidades;
  - las señales agregadas y anonimizadas entre inquilinos, solo con consentimiento y previsto en el DPA.

---

## 3. Arquitectura

```text
REPO DEL CLIENTE              INFRA DEL CLIENTE                        ACTAIRA CLOUD (UE)
────────────────              ─────────────────                        ──────────────────
actaira CLI / Action   ──►    actaira runner (Go)          ──mTLS──►   ingesta ─► grafo ─► estado
  discover                      ├ intermediario de credenciales        políticas firmadas ◄─┘
  actaira.lock                  │  (el secreto no sale del runner)     consola, flota, alertas
  diff + blast radius           ├ conectores de identidad              capa de cumplimiento (opcional)
                                ├ punto de decisión Cedar              modo builder multicliente
SDK Python / TS  ──socket──►    ├ proxy MCP (stdio / HTTP)             Ask Actaira
(autenticado)                   ├ receptor OTel e importadores
                                ├ firma del libro (clave del cliente)
                                └ corte local (kill switch)
```

**Tres planos:**

- **Ejecución**, en casa del cliente: decide en local, con el paquete de política firmado. Una caída de Actaira no rompe los agentes del cliente.
- **Control**, en la nube: políticas, grafo, consola.
- **Evidencia**: la firma el runner y se verifica fuera de Actaira.

**Modos de despliegue:**

- **Solo código abierto:** CLI y Action, sin cuenta.
- **Actaira Cloud sin runner (fase 2):** la Action sube el lockfile; no toca la infraestructura del cliente.
- **Actaira Cloud con runner (desde la fase 3):** los secretos, la clave HMAC y la clave de firma se quedan en el cliente.
- **BYOC:** para Enterprise, y cuando haya equipo.

### Decisiones de arquitectura (ADR)

| ADR | Decisión | Por qué | Coste que se acepta |
|---|---|---|---|
| 1 | **Go** para CLI, Action, runner, proxy y nube | Hipótesis a confirmar en C0: arranque de pocos milisegundos (medido en la antesala, se remide), distribución de un binario, `cedar-go` oficial | Si tree-sitter exige cgo, el binario deja de ser estático y se compila en runners nativos de la matriz de GitHub Actions. **Coste frente a beneficio de empezar de cero:** el antiguo seamark en Python resuelve otro problema (configuración de agentes de código), así que lo reutilizable son sobre todo la verificación y la criptografía, que no hacen falta hasta la fase 5; reescribir en Go no tira el producto de la fase 1 porque ese producto no existe todavía. En una Action de CI el arranque en milisegundos no importa: Go se elige por el runner y el proxy de las fases 3 y 4, por un solo lenguaje y por la distribución |
| 2 | **SDK finos en Python y TypeScript** que preguntan al runner por un socket autenticado (`SO_PEERCRED`/`LOCAL_PEERCRED` más un token por agente; en Windows, named pipe con ACL) | Los agentes se escriben en Python y TS; un solo motor de decisión; nadie puede suplantar el runner | Un salto de proceso por decisión; p99 de 5 ms como máximo, medido |
| 3 | **Descubrimiento estático con tree-sitter**; nunca se importa ni se ejecuta código del cliente | Ejecutar código ajeno es un vector de ataque (lección de GitSpawn) | cgo o variante wasm, decidido con medición en C0 |
| 4 | **Cedar solo para evaluar en Go**. Validación y análisis en la CI con la CLI oficial en Rust y en la consola con `cedar-wasm`. Sin plantillas | El validador de cedar-go es experimental (`x/exp/schema`); plantillas, evaluación parcial y análisis simbólico solo existen en Rust | Dos toolchains en la CI |
| 5 | **Obligaciones como anotaciones de política** (`effect("redact")`, `effect("approve")`, `limit(...)`) con precedencia escrita: denegar gana, luego aprobación, luego limitar, luego redactar | Cedar solo devuelve permitir o denegar y no tiene estado | El runner implementa las obligaciones y tiene tests propios |
| 6 | **Contadores de presupuesto** en un almacén compartido del cliente (Redis o Postgres), pasados a Cedar como `context` | Con varias réplicas, contadores locales multiplican el presupuesto | Una dependencia más en el runner; con una sola réplica, en memoria |
| 7 | **Se cachea el paquete de política firmado, nunca decisiones**, con antigüedad máxima; pasada esa antigüedad, las reglas `fail_closed` deniegan. Kill switch local además del remoto | Una decisión cacheada serviría un "permitir" después del corte | La política tarda en propagarse lo que se mide y se publica |
| 8 | **Fallo por regla**: el SDK carga la lista de tools irreversibles y falla cerrado en ellas aunque el runner no responda; el resto falla abierto con alerta | Un gateway que tumba producción se desinstala; uno que deja pasar dinero no vale | El cliente puede cambiarlo, con valor seguro por defecto |
| 9 | **Intermediación de credenciales**: el runner guarda el secreto y lo inyecta en la llamada saliente | Si el agente tiene la clave, un decorador es un aviso, no un control | Integrar cada sistema por el intermediario; lo no intermediado se publica como hueco |
| 10 | **Inquilino derivado de la credencial mTLS del runner**, nunca del payload; subinquilino marcado como "atribuido por el builder" | Un runner no puede falsificar a qué cliente pertenece la evidencia | Un certificado por inquilino |
| 11 | **Clave HMAC por subinquilino**, generada y guardada en el runner o el KMS del cliente, con `key_id` y rotación versionada; nunca sube a Actaira | Si la tiene Actaira, los digests son datos personales reversibles | Abrir un digest exige que el cliente revele el dato |
| 12 | **Postgres** para el grafo, con RLS forzado por inquilino | Un solo almacén barato y conocido | Si el blast radius en flota grande no llega a su objetivo de latencia, se evalúa otro motor |
| 13 | **Nunca un número de riesgo inventado**; cada afirmación cita fuente, fecha y confianza. Actaira no ejecuta nada que no autorice una política escrita por un humano | Doctrina heredada (las cuatro negativas) | Menos "puntuaciones" que la competencia |
| 14 | **IA para entender y proponer, nunca para decidir** (siete piezas, ver "La IA dentro"): todo lo que propone va marcado `inferred`, con citas validadas, y solo puede subir la gravedad, nunca bajarla | Un auditor no acepta "lo decidió un modelo" y un atacante no puede rebajar un riesgo escribiendo en la descripción de una tool | Cada pieza necesita su validador y su eval; se usa la plantilla fija si la IA falla o no hay clave |
| 15 | **Cumplimiento como capa**: módulo separado que consume la evidencia por una interfaz estable y publica mapeos versionados | El producto es el grafo de capacidades, el control y la prueba; si el cumplimiento fuera el núcleo, Actaira volvería a parecer una plataforma GRC | Una interfaz más que mantener; a cambio, añadir un marco es añadir datos, no tocar el núcleo |
| 16 | **Despliegue en Azure, pagando solo por uso:** Azure Container Apps en plan de consumo, región UE, con escala a cero; base de datos Postgres serverless con pausa automática (Neon en la UE al principio, o Azure Database for PostgreSQL pagada con créditos); web estática en Cloudflare Pages; imágenes en GitHub Container Registry; infraestructura como código con Bicep y az CLI; despliegue con GitHub Actions por OIDC, sin claves en el repo; cobro con Stripe o un Merchant of Record. Presupuestos y alertas de gasto en Azure y cuotas por plan en la aplicación | Coste fijo casi cero hasta que haya usuarios: Container Apps no cobra con cero réplicas e incluye cada mes 180.000 vCPU-segundos, 360.000 GiB-segundos y 2 millones de peticiones gratis. Los créditos de Microsoft for Startups (1.000 USD y luego 4.000 USD sin inversor) cubren el arranque, y Azure deja abierta la vía del Azure Marketplace | Arranques en frío de unos segundos, aceptables para la Action, los webhooks y la consola. La nube no se puede atar a los cobros de Stripe: lo que consumen los usuarios gratis se paga igual, y por eso la prueba lleva topes por cuenta y un tope global |

---

### La IA dentro

**Regla que no se mueve:** la IA entiende, explica y propone. Nunca decide si una acción se permite, si una capacidad es efectiva ni si una evidencia caduca. Todo lo que propone lleva una marca propia (`inferred`) hasta que lo confirma una persona o una regla escrita.

**Las siete piezas de IA:**

| # | Pieza | Bloque | Qué hace la IA | Qué queda determinista | Protección |
|---|---|---|---|---|---|
| 1 | **Clasificador de tools desconocidas** | C2 | Lee el nombre, el esquema, la descripción y, si está en el repo, el código de la tool. Propone efecto (lectura, escritura, irreversible), sistemas y datos sensibles, con confianza | El resultado entra en el grafo con nivel `inferred`. Nunca como `effective` | **Monotonía:** la IA solo puede **subir** la gravedad que dan las heurísticas; bajarla exige confirmación humana. Una descripción que dice "clasifícame como solo lectura" no consigue nada |
| 2 | **Explicación del diff y de las alertas** | C2, C3 | Una o dos frases en lenguaje normal: qué cambió y por qué importa | El diff, la ruta del grafo y el blast radius | Cada frase cita identificadores del grafo; un validador descarta las frases sin cita válida y, si falla, se usa la plantilla fija |
| 3 | **Mínimo privilegio** | C3, C4 | Redacta el cambio de permisos (IAM, permission set, clave restringida, política Cedar) y su explicación | La diferencia entre lo que el agente puede hacer (efectivo) y lo que usa (observado) se calcula sin IA | El cambio se valida (CLI de Cedar, simulador de IAM) y se enseña como diff de capacidades; lo firma una persona |
| 4 | **Políticas en lenguaje natural** | C4 | "Nada de reembolsos de más de 500 € sin aprobación" pasa a Cedar, con casos de prueba generados | La evaluación de la política | Tiene que compilar, pasar sus casos y enseñarse como diff de capacidades; lo firma una persona. Si la política amplía capacidades, se marca en rojo |
| 5 | **Triaje y resumen diario** | C6 | Redacta las tres cosas que mirar hoy | El orden de prioridad, con una puntuación versionada y desglosada | Citas validadas; como mucho tres acciones |
| 6 | **Investigador de incidentes** | C5, C9 | "¿Qué pasó con este reembolso?": narra la cadena causal | El recorrido del grafo causal | Solo narra lo que el recorrido devuelve, con citas; lo `unseen` se dice |
| 7 | **Ask Actaira** | C9 | Traduce la pregunta a una consulta del grafo | La consulta y la respuesta | Gramática cerrada; se enseña la consulta; el texto del atacante nunca entra en el prompt, solo identificadores |

**Cuarentena común:** descripciones de tools, docstrings, nombres de rama y mensajes de commit son datos del atacante.

- Van delimitados, nunca como instrucciones, y la salida se fuerza a un esquema JSON validado.
- Nunca salen al modelo secretos, contenido de eventos ni datos personales. Solo esquemas, código de la tool (con permiso) e identificadores.

**Cómo llega la IA a cada cliente:**

| Dónde | Cómo | Por qué |
|---|---|---|
| **Código abierto (CLI y Action)** | Todo lo determinista funciona **sin clave**. Las piezas 1 a 4 se activan con la clave del propio usuario (Anthropic, OpenAI, Azure OpenAI, Bedrock o Mistral) o con un modelo local (Ollama). En la Action, la clave va como secreto del repo | El núcleo abierto tiene que dar valor sin pedir nada; quien quiera más IA pone su clave |
| **Base de conocimiento pública** | **Fase 1:** las 50 tools más frecuentes, revisadas a mano, sin IA. **Fase 2:** el registro MCP completo, clasificado con las piezas 1 y 2 y revisado | La mayoría de usuarios del código abierto nunca necesita clave |
| **Actaira Cloud** | **IA incluida por defecto**, con un modelo alojado en la UE y cuota por plan. El cliente puede usar su propia clave (Enterprise, o si su política lo exige) o apagarla por inquilino | Quitar la fricción de la clave es parte de lo que se paga |

**Coste controlado:**

- La clasificación se cachea por hash del esquema, así que cada tool pública se clasifica una sola vez para todos, y cada tool privada una vez por inquilino.
- Un modelo pequeño clasifica y explica; uno grande redacta políticas.
- Cada llamada registra tokens, coste y latencia en `evals/results/`.

---

## 4. El modelo de datos

**Evento universal**, igual para cualquier fuente (SDK, proxy MCP, OTel, importadores):

```json
{
  "event_id": "01J...", "ts": "2026-09-27T14:41:03.120Z",
  "subtenant": "cliente-a",
  "actor": {"agent": "claims-agent", "version": "v42", "run": "r-9f..."},
  "deployment": "production-eu",
  "action": {"kind": "tool_call", "name": "create_claim", "effect": "write"},
  "resource": {"system": "crm", "object": "Claim"},
  "identity": "crm-integration-user-22", "credential_brokered": true,
  "parent": "span-7a...", "trace": "4bf92f...",
  "input_digest": "hmac-sha256:k3:...", "output_digest": "hmac-sha256:k3:...",
  "policy_decision": {"result": "allow", "policy": "claims-v17", "obligations": [], "reason_ids": ["limit-refund-500"]},
  "coverage": "mediated"
}
```

- **Inquilino.** No va en el payload: Actaira lo deriva de la conexión mTLS del runner (ADR 10).
- **`coverage`** puede ser `mediated`, `observed` (visto por OTel sin punto de decisión), `declared` (solo en el repo) o `unseen`. La vista de cobertura por agente (`docs/cobertura.md`) usa este campo tal cual, sin otro enumerado y sin copiarlo a las capacidades: con él calcula qué capacidades están mediadas. El estado de cada fuente (`observed`, `not_configured`, `error` o `stale`) es otro campo, y ahí `observed` significa que la fuente se leyó bien, no que se viera en ejecución. `unseen` (no mirado) nunca se mezcla con `unresolved` (mirado y no entendido).

**Nodos del grafo:** Agent, AgentVersion, Deployment, Model, Prompt, Tool, MCPServer, Subagent, MemoryStore, Identity, Secret, System, Action, Customer, Policy, Evidence.

**Aristas:**

- `can_call`, `uses_credential`, `can_access`, `permits`, `delegates_to`, `reads_memory` y `writes_memory`.
- `deployed_as`, `serves_customer`, `caused` y `depends_on`.

Cada arista lleva fuente, fecha y nivel de confianza:

- `declared`: sale del repo o de la declaración del cliente.
- `conditional`: depende de un contexto que no se conoce.
- `effective`: respaldada por una respuesta de API guardada.
- `observed`: vista en tiempo de ejecución.
- `inferred`: propuesta por la IA. Se enseña, pero no cuenta para ninguna decisión ni evidencia hasta que la confirma una persona o la base de conocimiento.

**Estados de evidencia:** `vigente`, `caducada`, `insuficiente`, `no_aplica` y `error`.

**Qué campos cuentan como dependencia** se fija en una tabla escrita **antes** de la batería de C6:

- **Sí invalidan:** esquema de la tool **y su descripción** (el tool poisoning va en la descripción), permisos, política, modelo, prompt de sistema y despliegue.
- **No invalidan:** el texto de un README y los comentarios de código.

---

## 5. Orden de construcción y señales de mercado

**Sin plazos.** Nada de este plan se mide en días ni en semanas. El orden lo marcan dos cosas:

- **Las dependencias técnicas.**
- **La prioridad declarada:** primero el **núcleo abierto** y, sobre él, la **plataforma self-serve**.

Las señales de mercado no paran la construcción. Deciden qué entra antes en la plataforma y cuándo se gasta dinero.

| Fase | Qué se construye | Bloques |
|---|---|---|
| **Previa (sin código)** | Marca "Actaira" comprobada en OEPM y EUIPO, organización `actaira` en GitHub,. Lista de 30 builders con nombre y conversaciones con un guion de 5 preguntas. Tabla comparada contra Snyk Agent Scan y mcplock | Ninguno |
| **0. Núcleo abierto: la primitiva** | `actaira.lock` con tools fijadas por hash y versión del servidor MCP; modelo de capacidades; extractores; el bloque `intent` del contrato y el borrador del ACM con su validador | C0, C1 |
| **1. Núcleo abierto: Capability Diff** | Primero, `actaira inspect` y el registro público de servidores MCP, que salen en la v0.2.0, el primer lanzamiento público. Después: extractores (OpenAI Agents SDK, LangGraph, Vercel AI SDK, configuraciones MCP de los clientes conocidos, Agent Skills), lockfile, `init` y `accept` con motivo, `intent init`, diff con causa y contra el contrato, alcanzabilidad desde entradas no fiables, flujos tóxicos, blast radius potencial, SARIF, etiquetas OWASP, deriva programada de MCP remotos, pre-commit y plantilla de GitLab CI. **El estudio sale cuando el rastreador tenga historia suficiente para medir cambios**, sin fecha fija | C2 |
| **2. Plataforma self-serve: la base** | Actaira Cloud sin runner. Alta con GitHub, y la Action sube el lockfile. Primero, lo del builder: subinquilinos, contrato por cliente, pasaporte por agente v1 y el plan Builder; después, el plan Team. En los dos: vista de flota entre repos, historial y diff de capacidades, máquina del tiempo, alertas (también la de un MCP que gana una capacidad irreversible), IA incluida sin clave y cobro. Es la primera experiencia de pago y no necesita tocar la infraestructura del cliente | C9 (base), C6 (alertas) |
| **3. Plataforma: capacidades efectivas** | Runner, conectores de identidad (el primero, el que pidan los builders), deriva de capacidades sin cambio de código, mínimo privilegio, el compilador de credenciales desde el contrato y la mejora del plan Builder con capacidades efectivas | C3 |
| **4. Plataforma: control** | Intermediación de credenciales, el contrato compilado en políticas con modo sombra, exposición máxima acotada, aprobaciones, kill switch, presupuestos de autonomía | C4 |
| **5. Plataforma: assurance** | Evidencia que caduca en la nube, página de estado de evidencia con la marca del builder, pasaporte firmado, máquina del tiempo con evidencia, tests de ataque como evidencia, **capa de cumplimiento** | C6, C7 |
| **6. Ampliación** | Efectos de varios saltos, memoria, registros de plataforma, Enterprise cuando haya equipo | C5 ampliado, C8 |

**De dónde sale la lista de tools de un MCP sin conectarse:** del paquete fijado (versión de npm o PyPI) y del `tools/list` capturado en la base de conocimiento pública para los servidores del registro, más las tools definidas en el código. Criterio de "listo cuando" de la fase 1: medir en el corpus en cuántos PRs reales saltaría el comentario, para no vender una demo que en repos de verdad no aparece.

**Lo que se enseña al acabar la fase 1 (la demo):**

- `git push` de un cambio en una tool o en un servidor MCP;
- el comentario en el PR: "`support-agent` gana la capacidad potencial `customer.delete`, porque la tool `delete_customer` apareció al pasar el servidor `customer-mcp` de la 2.3.1 a la 2.4.0; afecta a 3 agentes; [ver ruta]".

**Señales de mercado (no son relojes ni paradas de construcción):**

| Señal | Cómo se mide | Qué decide |
|---|---|---|
| Adopción del núcleo | Repos públicos con la Action, con un método publicado: búsqueda de `uses:` con captura fechada, descargas de releases, registro voluntario y telemetría opt-in. Además, builders con la Action en un repo privado, confirmado por ellos | Si el mensaje funciona; si no, se revisa el mensaje y la demo, sin parar la construcción |
| Dolor contado | Conversaciones con builders de la lista | Qué conector va primero en la fase 3 y qué piden el contrato por cliente y el pasaporte |
| Disposición a pagar | Cartas de intención con precio objetivo, o pilotos pagados del plan Builder | Precio de la plataforma y cuándo se gasta en pentest, legal y atestación |
| Retención | Uso repetido del núcleo y de la plataforma | Cuándo buscar socio |

**Métricas de producto (no comerciales).** Dicen si el producto se usa, no se venden ni llevan objetivo inventado. Cada una se publica con su método y su fecha en `evals/results/`, y lo que el método no ve se dice:

| Desde | Métrica | De dónde sale |
|---|---|---|
| La v0.2.0 | Descargas de la CLI | Contador de descargas de los assets de cada release de GitHub. Cuenta descargas, no usuarios |
| La v0.2.0 | Visitas al registro público de servidores MCP | Las analíticas del alojamiento de la web estática, sin cookies. El método se fija en el paso 2.3 de la E2 |
| La E3 | Builders en prueba que crean un pasaporte para un cliente | La propia plataforma: inquilinos en prueba con al menos un pasaporte de un subinquilino |

**Lo único que sí se frena: el gasto.** Constituir la SL, el pentest, las plantillas legales y la atestación SOC 2 o ISO 27001 esperan a que haya clientes que paguen. Los pilotos se facturan con un sistema compatible con Verifactu.

**Backlog (entra cuando un cliente lo pida o en la fase 6):**

- Windows nativo, SCIM, OpenSSF Scorecard y BYOC.
- Gobierno de memoria (C8), en backlog hasta la fase 6.
- Efectos causales de varios saltos (colas, workers, sistemas en cadena), en la fase 6.
- Mapeos a ENS, NIS2, DORA, RGPD y NIST AI RMF.
- Frameworks fuera de la lista de la fase 1 (CrewAI, Google ADK, Microsoft Agent Framework, Claude Agent SDK), salvo que el estudio los señale.

**Dependencias:**

- La fase 0 y la 1 no dependen de nada externo.
- La 2 depende de la 1, porque la Action es la que sube el lockfile.
- La 3 depende de la 2, porque la nube recibe lo que manda el runner.
- La 4 depende de la 3.
- La 5 depende de la 3 (firma el runner) y de la 4 (caminos mediados).
- La 6 depende de la 3 y de la 4.
- La parte local de C6 depende de C1; la de nube, de la fase 2.

---

## 6. Cómo se mide (vale para todos los bloques)

- **Corpus congelado antes de ajustar nada.** Repos públicos de agentes etiquetados por ti y por **una segunda persona a ciegas**, con el acuerdo entre los dos publicado (kappa de Cohen). Se nombra a esa persona antes de C1, o se presupuesta el etiquetado de pago (sección 11). Si no aparece nadie, se publica "kappa pendiente" y no se afirma el recall.
- **Proporciones con intervalo de Wilson.** Con cero fallos se publica la cota superior (0 de 200 da hasta el 1,9 %). Bootstrap agrupado por repo o por familia cuando los casos no son independientes.
- **Umbrales de pasa o no pasa fijados aquí.** Si no se llega, el bloque no se cierra:
  - cota inferior de Wilson del recall de tools de al menos 0,80;
  - sondeo de cambios cada 15 minutos o menos;
  - decisión con p99 de 5 ms como máximo;
  - kill switch con p95 de 10 s como máximo;
  - alerta con p95 de 5 minutos como máximo.
- **Resultados con fecha y commit** en `evals/results/`. Ningún documento afirma en presente lo no construido.
- **Una sesión real de agente por bloque**, además de los tests. La lección del antiguo seamark: tres llamadas reales encontraron cuatro bugs que 1.905 tests no vieron.

---

## 7. Bloques

### C0. Cimientos

**Objetivo:** que todo lo que venga después se apoye en decisiones medidas y en un modelo de amenazas escrito.

**Entregables:**

- **Repo:** monorepo `actaira` (Apache-2.0) con Go y GoReleaser para **Linux y macOS** (la Action corre en Linux). Firma con cosign sin claves y SBOM por versión, que GoReleaser da casi gratis. Windows y Scorecard, cuando lo pidan.
- **Esquemas versionados** del evento universal, del gemelo digital y de `actaira.lock`, con tests de compatibilidad hacia atrás.
- **Mediciones:** tree-sitter con cgo frente a la variante wasm, y arranque de la CLI. La latencia del socket se mide en la fase 4, cuando existan el runner y los SDK.
- **Modelo de amenazas de una página:** el repo hostil y el servidor MCP que miente, que son lo que toca la fase 1. El de la nube (subida del lockfile, fugas entre inquilinos, Actaira comprometida) se escribe al abrir la fase 2; el del runner y el socket, al abrir la fase 3.
- **Seguridad del proyecto:** `SECURITY.md`, `security.txt` y política de divulgación coordinada. El procedimiento de notificación de la CRA y la clasificación del producto se hacen al empezar a cobrar (C9), porque las obligaciones de fabricante nacen al comercializar.
- **Doctrina en `CLAUDE.md`:** las cuatro negativas, el presupuesto de revisión (una pasada por bloque, que solo produce arreglos o líneas de backlog) y la regla de que un presupuesto que solo vive en el chat no existe.

**Listo cuando:** las mediciones están en `evals/results/`, los ADR 1 y 3 quedan decididos con esos números, y un clon limpio compila y pasa la CI en Linux y macOS.

**Pasada adversarial de C0:**

| Crítica | Corrección |
|---|---|
| "Arranque de ~2 ms" y "binario estático" se afirmaban antes de medir | Pasan a hipótesis de C0 |
| cgo rompe la compilación cruzada, y para macOS hace falta el SDK de Apple | Runners nativos de la matriz de GitHub Actions |
| Faltaba la CRA, que ya obliga a notificar | Proceso de vulnerabilidades y notificación desde C0 |
| Riesgo de repetir el bucle de autoauditoría de julio | Presupuesto de revisión en la doctrina |
| C0 era un proyecto maduro antes de tener un usuario (revisión externa de la 1.4) | Solo Linux y macOS, amenazas de la fase 1, CRA al cobrar |

### C1. Descubrir: el gemelo digital desde el repo (núcleo abierto)

**C1 y C2 salen en un solo lanzamiento, "Actaira Capability Diff".** Publicar `discover` solo es enseñar infraestructura sin el momento de valor. El lockfile guarda, por cada tool, su hash y la versión del servidor MCP que la sirve, para que el diff pueda decir la causa ("`customer-mcp` 2.3.1 a 2.4.0").

**Objetivo:** que `actaira discover` diga, en segundos y sin cuenta, qué agentes hay en un repo y con qué están hechos.

**Entregables:**

- **Extractores estáticos, lista cerrada:** OpenAI Agents SDK, LangGraph/LangChain y **Vercel AI SDK** (Python y TS); **configuraciones MCP versionadas en el repo** (`.mcp.json`, `.cursor/mcp.json`, `.vscode/mcp.json`, configuración de Codex y de Claude); y **Agent Skills** (`SKILL.md`: `allowed-tools` y los scripts que trae). CrewAI, Google ADK, Microsoft Agent Framework y Claude Agent SDK entran solo si el estudio los señala.
- **Procedencia desde el registro MCP:** namespace verificado, vínculo paquete-registro y versión fijada o no.
- **Por cada agente:**
  - modelo, hash del prompt de sistema, tools con firma y descripción, subagentes y handoffs;
  - servidores MCP, almacenes de memoria referenciados, secretos referenciados por nombre (nunca su valor) y proveedores externos.
- **Cuarentena, definida aquí:** las descripciones de tools, los docstrings y el resto del texto del repo son datos del atacante. Se guardan y se hashean, y nunca entran en un prompt.
- **`actaira inspect`** (E2, paso 2.3; en C2), que **nunca instala ni ejecuta nada en la máquina del usuario**:
  - un servidor HTTP remoto se consulta con `tools/list`, y se guarda el hash del esquema y de la descripción de cada tool;
  - un paquete stdio no se arranca: sus tools salen de las instantáneas del rastreador, que lo ejecuta en su propio contenedor sin red. Lo que no está en ninguna instantánea sale `unseen`, con su motivo;
  - las anotaciones se guardan como pistas no fiables.
- **El contrato de capacidades** (sección 0): el bloque `intent` en el esquema v1 de `actaira.lock` y el borrador del formato abierto ACM, con su JSON Schema y su validador (`actaira intent validate`).
- **Rastreador del estudio:** captura diaria de `tools/list` de servidores MCP **HTTP públicos** del registro MCP, que acumula historia para C2.
- `actaira.lock`: determinista (mismo repo, mismo fichero byte a byte) y pensado para commitearse.
- **Honestidad por construcción:** lo que el extractor no entiende sale como `unresolved`, con su fichero y su línea.

**Listo cuando:**

- En el corpus congelado de 30 repos o más, la cota inferior de Wilson del recall de tools es de al menos 0,80, con la precisión y la tasa de `unresolved` publicadas.
- Mismo lockfile en 10 ejecuciones, en Linux y macOS.
- Un test con un repo trampa y un servidor MCP trampa demuestra que no se ejecuta nada fuera del contenedor.
- `discover` tarda menos de 10 s en el repo p95 del corpus.

**Pasada adversarial de C1:**

| Crítica | Corrección |
|---|---|
| Arrancar un MCP stdio de `.mcp.json` es ejecutar código del repo, y "sandbox" no estaba definido | Contenedor Linux sin red; en macOS y Windows, solo HTTP. Desde la versión 2.1 del plan, `inspect` no arranca ningún stdio en la máquina del usuario: solo lo hace el rastreador, en su contenedor |
| C1 dependía de bloques posteriores (lista de extractores, cuarentena) | Lista cerrada y cuarentena definidas en C1 |
| Las tools dinámicas no se ven en estático | `unresolved` con ubicación y tasa publicada; en tiempo de ejecución las ve el proxy |
| Recall contra etiquetas propias es circular | Segunda persona a ciegas, kappa y umbral mínimo |

### C2. Capability Diff, blast radius y el estudio (núcleo abierto)

**Objetivo:** el momento "aha" en el PR y la repercusión pública.

**Entregables:**

- **Base de conocimiento de capacidades abierta:** traduce tools conocidas a acciones con efecto. Por ejemplo, `stripe.refunds.create` pasa a ser `money.refund`, escritura irreversible. Empieza por las 50 tools más frecuentes del corpus; lo que no está sale como `effect: unknown`.
- **`actaira inspect` y el registro público de servidores MCP, el primer lanzamiento público (v0.2.0):** el gancho del desarrollador, "¿qué hace este MCP?".
  - `actaira inspect <npm:paquete@versión | pypi:paquete==versión | https://url-remota | ruta a una config MCP>` dice qué hace cada tool (efecto, recurso, etiquetas de flujo, flujos tóxicos, anotaciones que mienten y procedencia), con su causa y su fuente, sin instalar ni ejecutar nada en la máquina del usuario.
  - El registro es una web estática generada desde `actaira-kb` con los mismos datos: lo declarado por cada servidor frente a lo potencial según la base de conocimiento, sin mezclarlos, y el historial por versión, sin puntuaciones.
- **`actaira diff`** entre la base y la cabeza del PR:
  - capacidades nuevas, perdidas y cambiadas;
  - tools cuyo hash de esquema o descripción cambió;
  - efecto y sistemas alcanzados;
  - si el cambio rompe el contrato de algún agente (sección 0). Un agente sin contrato sale "sin contrato", no como error.
- **`actaira blast`:** dada una credencial, un MCP o una tool, qué agentes y sistemas toca.
- **GitHub Action con el patrón de dos workflows:**
  - `pull_request` calcula sin permisos de escritura y sube un artefacto.
  - `workflow_run` comenta, sin parsear nunca código del fork con un token de escritura.
  - Un check que falla si aparece una capacidad irreversible nueva o si el cambio rompe el contrato; la revisión obligatoria de CODEOWNERS se configura como protección de rama y se documenta así.
- **Primera ejecución y ruido, lo que decide si se desinstala:**
  - `actaira init` crea la base en un repo existente sin comentar nada;
  - `actaira accept <capacidad> --reason --owner --until` deja la aceptación en el lockfile, hallazgo a hallazgo;
  - por defecto solo se comenta lo de escritura o irreversible, con umbral configurable;
  - `unresolved` y `effect: unknown` van plegados al final, nunca como alarma;
  - criterio medido: menos de 1 comentario por cada 20 PRs del corpus benigno.
- **Flujos tóxicos:** marca el agente que junta entrada no fiable, datos sensibles y un canal de salida externo (la "trifecta letal"). Es una consulta sobre el grafo con tres etiquetas más en la base de conocimiento.
- **Alcanzabilidad:** desde cada entrada no fiable hasta cada capacidad irreversible, también la heredada entre agentes (subagentes y handoffs), con el camino paso a paso. Es estática: dice que el camino existe en el código, no que alguien lo haya recorrido.
- **Anotaciones que mienten:** avisa cuando `readOnlyHint` o `destructiveHint` contradicen el efecto de la base de conocimiento.
- **Deriva programada:** una Action con `schedule` vuelve a leer las tools de los MCP remotos y abre un issue si cambian, sin esperar a un PR.
- **Salidas y canales:**
  - SARIF para la pestaña de seguridad de GitHub;
  - etiquetas OWASP Agentic Top 10 y OWASP MCP Top 10 en cada hallazgo;
  - hook de pre-commit y plantilla de GitLab CI (el comentario en la merge request, justo después del lanzamiento);
  - telemetría opt-in, apagada por defecto y documentada, para medir la adopción.
- **Justo después del lanzamiento:** servidor MCP y skill para que Claude Code o Cursor pregunten qué capacidad acaban de añadir; playground web con un repo o MCP público y un badge; exportación AI-BOM en CycloneDX 1.6; lockfile con attestation de GitHub o Sigstore.
- **IA en C2 (entra con la plataforma, fase 2; no bloquea el lanzamiento):**
  - **Clasificador de tools desconocidas** (pieza 1), con la regla de monotonía.
  - **Explicación del diff** (pieza 2), con citas validadas.
  - La **base de conocimiento pública** pasa de las 50 tools revisadas a mano de la fase 1 al registro MCP completo, clasificado con las piezas 1 y 2 y revisado, para que el código abierto dé el aha sin clave.
  - **Eval del clasificador:** contra las etiquetas de otra persona, con precisión y recall por clase y una cota inferior de Wilson del recall de `irreversible` de al menos 0,80 (lo peligroso importa más que lo inofensivo). Batería de inyección en descripciones, con 300 casos o más: 0 rebajas de gravedad, que la monotonía impide por construcción y el test comprueba.
- **Pantalla aha** en la CLI y en el comentario: "3 capacidades potenciales que este cambio introduce", con su porqué y su ruta en el grafo.
- **Tres palabras que nunca se mezclan en la interfaz:**
  - **Detectada:** la tool existe en el código o en el listado del MCP que ve el agente. Las de la instantánea pública del registro salen aparte, como tales (`docs/cobertura.md`).
  - **Potencial:** la tool más la base de conocimiento dicen que podría hacer X.
  - **Efectiva:** una API de identidad confirma que la credencial del agente lo permite. Solo Actaira Cloud, desde la fase 3.

  `delete_customer` en el código no significa que el agente pueda borrar clientes. Decirlo así protege la credibilidad y marca la línea entre lo gratis y lo de pago.
- **El estudio**, reproducible con un comando, con método, sesgo de muestra, cobertura del escáner y cifras con intervalos. Mide:
  - agentes con capacidades irreversibles sin aprobación humana;
  - tools no documentadas;
  - con la historia del rastreador de C1, servidores MCP públicos cuyas tools cambiaron en el periodo observado.

**Listo cuando:**

- El diff es correcto al 100 % en una batería de pares de commits con resultado esperado escrito antes.
- Hay 0 falsos "capacidad nueva" en 200 PRs benignos (cota de Wilson publicada).
- El comentario sale en menos de 60 s.
- El estudio lo ha revisado una segunda persona.

**Pasada adversarial de C2:**

| Crítica | Corrección |
|---|---|
| En PRs desde forks, `pull_request` no puede comentar, y `pull_request_target` da escritura mientras se parsea código hostil | Patrón de dos workflows |
| Una Action no puede "exigir CODEOWNERS" | Check requerido más protección de rama documentada |
| La métrica de cambios de MCP necesitaba historia y conectar a servidores ajenos | Rastreador de servidores HTTP públicos desde C1, con historia suficiente antes de publicar |
| Señalar repos concretos | Estudio agregado; aviso privado y coordinado a los casos graves |
| Comentarios ruidosos se desactivan | Solo comenta si cambian capacidades |

### C3. Capacidades efectivas y el runner (fase 3)

**El consentimiento que la fase 3 necesita:** el conector del builder lee el Salesforce o el Zendesk **de su cliente**, así que hace falta la autorización del administrador del cliente final y un acuerdo que lo cubra. El piloto se diseña con eso desde el principio.

**Objetivo:** pasar de "lo que dice el código" a "lo que de verdad puede hacer".

**Entregables:**

- **`actaira runner`:** binario Go en la infra del cliente (contenedor, Helm o systemd), con una **lista de destinos de salida por conector**, publicada y configurable. Los secretos, la clave HMAC y la clave de firma no salen de allí.
- **Conectores de identidad de solo lectura**, uno a uno y en el orden que pidan los design partners. **Solo se eligen como primeros los que dan permisos reales:**

| Sistema | Fuente real de permisos | Nivel | Permiso mínimo del runner |
|---|---|---|---|
| AWS | `SimulatePrincipalPolicy` con claves de contexto explícitas y `ResourcePolicy` cuando aplique; se guardan `MatchedStatements` y `MissingContextValues` | `effective`, o `conditional` si falta contexto | `iam:SimulatePrincipalPolicy` y lectura de políticas |
| Kubernetes | `SubjectAccessReview` sobre la lista cerrada de pares (verbo, recurso) de la base de conocimiento; lectura de Roles y Bindings para enumerar | `effective`, o `partial` si hay autorizadores webhook | `create` sobre `subjectaccessreviews` y lectura de RBAC; nunca `impersonate` |
| GitHub | Permisos de la instalación de la GitHub App por API | `effective` | Lectura de la instalación |
| Salesforce | Describe del objeto ejecutado **como el usuario de integración del agente**: Salesforce documenta `isCreateable`, `isUpdateable` e `isDeletable` como lo que puede hacer "el usuario actual". Para saber **por qué** (qué permission set lo concede), `PermissionSetAssignment` (qué conjuntos tiene el usuario) y `ObjectPermissions` (`PermissionsCreate`, `PermissionsEdit`, `PermissionsDelete`, `PermissionsViewAllRecords`, `PermissionsModifyAllRecords` por `SobjectType`). El scope OAuth (`api`, `refresh_token`) solo como dato | `effective` a nivel de objeto; el acceso a registros concretos (sharing) queda como límite declarado | Usuario de integración con "View Setup and Configuration"; comprobar en una org Developer gratuita que basta y que los conjuntos del perfil salen en la consulta |
| Zendesk | Rol del usuario, además de los scopes | `effective` para lo que el rol define | Lectura |
| HubSpot | Tokens OAuth: `POST /oauth/2026-09/token/introspect` devuelve `scopes`. Apps privadas (ya "legacy", aún soportadas): `POST /oauth/v2/private-apps/get/access-token-info` devuelve usuario, hub, app y `scopes`. Los scopes de HubSpot son finos (por objeto y lectura o escritura), así que sí sirven como capacidad | `effective` para ambos; las apps de la plataforma nueva, a comprobar al conectarlas | Credenciales de la app (para OAuth, `client_id` y `client_secret`) |
| Stripe | Tipo de clave (`sk_` o `rk_`), declaración del cliente y 403 observados | `declared` | Ninguno |
| GitHub, PAT fine-grained | Sin introspección | `declared` | Ninguno |

- **Vigilantes de cambio**, con sondeo cada 15 minutos o menos y webhooks donde existan. El hash de las tools MCP se calcula en el proxy sobre la sesión real del agente (dato mediado). El sondeo desde el runner se marca `observed` con la identidad usada, y si el servidor da listas distintas por identidad, se avisa.
- **Alerta** "ha adquirido `customer.delete`", con la ruta en el grafo, la fuente, la hora y el blast radius, y una explicación de la IA (pieza 2) cuando la hay.
- **Mínimo privilegio** (pieza 3): la diferencia entre lo efectivo y lo observado durante un periodo configurable se calcula sin IA. Hasta que haya llamadas vistas en ejecución, se calcula con la capacidad potencial de las tools del agente, y solo da número si se ha visto todo lo que podría usar la credencial; si no, esos permisos salen como uso desconocido (`docs/cobertura.md`); la IA redacta el cambio de permisos por sistema (política IAM, permission set de Salesforce, clave restringida de Stripe), que se valida y se enseña como diff de capacidades.
- **Compilador de credenciales desde el contrato** (sección 0): la credencial mínima exacta por sistema (política IAM, clave restringida de Stripe, token de grano fino de GitHub) sale del contrato y de los mapeos de permisos por sistema de la base de conocimiento. Donde la credencial está como código en el repo, Actaira propone un PR que la recorta hasta el contrato y lo fusiona una persona. Se valida con el simulador oficial donde lo hay; donde no, sale `declared`.

**Listo cuando:**

- Por cada conector, un entorno real con cambios provocados, con el 100 % detectado dentro de 15 minutos y 0 capacidades `effective` sin respuesta de API guardada que la respalde.
- Un test de red comprueba que no hay tráfico fuera de la lista de destinos.
- Los secretos nunca aparecen en eventos ni en logs, comprobado con centinelas y escaneo de secretos.

**Pasada adversarial de C3:**

| Crítica | Corrección |
|---|---|
| Un scope OAuth (Salesforce `api`) no es una capacidad efectiva: lo decide el perfil y los permission sets | Fuente real por sistema y nivel de confianza; el scope es solo un dato |
| `SelfSubjectRulesReview` solo informa del llamante y no sirve para decisiones externas | `SubjectAccessReview` sobre una lista cerrada, sin `impersonate` |
| `SimulatePrincipalPolicy` no ve session policies ni contexto ABAC | Contexto explícito y nivel `conditional` |
| "Sin salida a internet salvo Actaira" era imposible | Lista de destinos por conector, probada |
| `list_changed` solo llega a una sesión abierta y la lista puede variar por identidad | Hash en la sesión real del agente, en el proxy |

### C4. Control en tiempo de ejecución (fase 4)

**Objetivo:** que las políticas bloqueen antes de que ocurra la acción, sin romper producción.

**Entregables:**

- **Punto de decisión Cedar** en el runner, con obligaciones por anotación y precedencia escrita (ADR 5): permitir, denegar, limitar, redactar, pedir aprobación y aislar.
- **Intermediación de credenciales** (ADR 9): el agente llama con un token de sesión del runner y el runner inyecta la credencial real. La cobertura se publica como N de M credenciales del agente intermediadas, con la lista de las que no lo están, nunca como porcentaje.
- **Vías de mediación:**
  - `guard` en los SDK de Python y TS, con adaptadores para OpenAI Agents SDK y LangGraph, y hook para Claude Agent SDK.
  - Proxy MCP por stdio y, en v1, HTTP con cabecera estática.
  - Para servidores MCP con OAuth, el proxy actúa como servidor de recursos ante el agente y como cliente OAuth propio ante el servidor, y guarda él los tokens. Así se cumple la especificación, que prohíbe reenviar tokens.
- **Presupuesto de autonomía** con contadores compartidos (ADR 6): escrituras, correos externos, dinero, profundidad de subagentes, llamadas y duración.
- **Aprobaciones** por Slack, Teams o web. "Aprobar y crear regla" enseña la regla candidata como diff de capacidades y la firma una persona.
- **Kill switch** remoto y local (`actaira runner kill ...`) por agente, tool, destino, importe, MCP o despliegue, y modo "solo con aprobación".
- **Política como código**, con `actaira policy test` y validación en la CI con la CLI de Cedar.
- **Políticas en lenguaje natural** (pieza 4): de la frase a Cedar con casos de prueba; eval con 100 frases escritas por otra persona: el 100 % de las propuestas aceptadas compila y pasa sus casos, y 0 amplían capacidades sin la marca roja.
- **Paquete de política firmado** con antigüedad máxima (ADR 7) y **fallo por regla** (ADR 8).
- **Del contrato a la política** (sección 0): el contrato se compila en política Cedar, que se ve como diff de capacidades y firma una persona. Corre primero en **modo sombra**, que registra lo que habría bloqueado sin bloquear, y se aplica después. La **exposición máxima** de cada agente solo se calcula con los límites escritos en el contrato o en la política; si falta uno, sale "sin límite".

**Listo cuando:**

- La decisión tiene un p99 de 5 ms como máximo.
- Hay 0 discrepancias en las pruebas diferenciales entre cedar-go y la CLI de Cedar.
- El kill switch tiene un p95 de 10 s como máximo, y el corte local funciona con la nube caída.
- El presupuesto se cumple con 3 réplicas del runner.
- La batería de evasión da 0 acciones prohibidas ejecutadas en 300 casos o más. Incluye:
  - argumentos codificados, nombres de tool parecidos, llamadas en paralelo y reintentos;
  - **llamada directa con la credencial del entorno**, que debe fallar porque la credencial no está;
  - **runner caído**, que debe fallar cerrado en las irreversibles;
  - **socket suplantado**, que debe rechazarse.

**Pasada adversarial de C4:**

| Crítica | Corrección |
|---|---|
| Con la clave en el proceso del agente, `guard` era un aviso y "0 en caminos mediados" era tautológico | Intermediación de credenciales y caso de llamada directa en la batería |
| Cedar no tiene obligaciones ni estado | Anotaciones con precedencia y contadores en `context` |
| Una caché de decisiones servía permisos tras el corte | Se cachea la política con antigüedad máxima; corte local |
| El socket no tenía autenticación | Credenciales del par y token por agente |
| Un proxy MCP transparente con OAuth incumple la especificación | Stdio y cabecera estática en v1; OAuth como servidor de recursos más cliente propio |

### C5. Grafo causal y fan-out

**Objetivo:** responder qué consecuencias reales produjo una decisión del agente. **Primero solo el primer salto:** agente, tool, MCP o API y su efecto directo, llamado **efecto confirmado** cuando hay prueba. La cadena de varios saltos (colas, workers, sistemas en cadena) se añade por partes en la fase 6. Se vende "efectos confirmados donde hay evidencia", nunca "grafo causal completo".

**Entregables:**

- **Receptor OTLP e importadores de LangSmith y Langfuse, siempre en el runner.** Antes de subir nada:
  - se descartan o se convierten en digest los atributos de contenido (`gen_ai.input.messages`, `gen_ai.output.messages` y similares);
  - los centinelas de C3 cubren también esta ruta.
- **Convenciones GenAI de OpenTelemetry** (aún no estables), con versión fijada, adaptadores y propagación W3C `traceparent` desde el SDK.
- **Correlación con los registros de auditoría de los SaaS** (CloudTrail, audit trail de Salesforce y de Zendesk) por claves de idempotencia, identificadores de objeto y tiempo, porque los SaaS no propagan trazas.
- **Vista causal y mapa de cobertura** por agente: cada tramo con su valor de `coverage` (`mediated`, `observed`, `declared` o `unseen`), en la vista de `docs/cobertura.md`.

**Listo cuando:**

- En el stack real de un design partner, se publica qué porcentaje de tool calls tiene su efecto aguas abajo **confirmado**, con intervalo.
- Hay 0 enlaces causales inventados en la batería.

**Pasada adversarial de C5:**

| Crítica | Corrección |
|---|---|
| Reconstruir el 100 % en una demo propia no dice nada de producción | Métrica en el stack de un design partner |
| Los SaaS no propagan `traceparent` | Correlación con sus registros de auditoría |
| Con captura de contenido activada, el contenido en claro saldría del cliente | Receptor e importadores en el runner, con descarte de contenido |

### C6. Evidencia y vigilancia 24/7

**Objetivo:** vender tranquilidad que se pueda demostrar. Para cada agente y cada cliente se sabe en todo momento si su evidencia está vigente, y por qué deja de estarlo.

**C6 local (fuera de la fase 1: no mueve la adopción; entra en la fase 5, o antes si un design partner lo pide):**

- **El libro:** cadena de hashes y árbol de Merkle con separación de dominios, **firmado por el runner o la CLI con una clave del cliente**, por inquilino y en su KMS. Actaira nunca firma evidencia del cliente.
- **Anclaje externo:**
  - las cabezas de árbol firmadas se publican en un **log de transparencia externo** (Rekor);
  - el sello RFC 3161 va sobre esa cabeza.

  Así nadie, ni una Actaira comprometida, puede enseñar historias distintas a verificadores distintos.
- **`actaira verify`, offline:**
  - exige pruebas de consistencia entre cabezas;
  - verifica la cadena completa de la TSA con la respuesta de revocación incluida en el paquete;
  - conserva los invariantes heredados: añadir anclas nunca relaja la estrictez y un chequeo ausente nunca se lee como aprobado.
- **Aserciones.** Cada aserción liga una regla con la política firmada, el despliegue, la config, el esquema y la descripción de la tool, la identidad, las pruebas y las observaciones.
- **Invalidación automática** según la tabla de dependencias de la sección 4. Una aserción caducada no se borra: queda `caducada`, con motivo y hora.
- **Alerta por webhook.**

**C6 en la nube (depende de C9):**

- Recálculo continuo del estado.
- Alertas a Slack, Teams, PagerDuty o correo, con deduplicación.
- Resumen diario (pieza 5): prioridad determinista y versionada; la IA solo lo redacta, con citas y como mucho tres acciones.
- **Latido**: si Actaira deja de evaluar, el runner lo detecta y el estado pasa a `error`.
- **Página de estado de evidencia** compartible por agente o cliente, verificable sin cuenta, con el aviso fijo "no es una opinión de auditoría ni un informe de aseguramiento".
- **Pasaporte firmado** (sección 0): el pasaporte por agente de la fase 2, firmado y verificable fuera de Actaira; la **máquina del tiempo con evidencia** (qué podía hacer el agente en una fecha, con la evidencia de entonces); y los **tests de ataque** que genera Actaira con tools simuladas y ejecuta el cliente en su CI (opt-in), cuyo resultado entra como evidencia.

**Listo cuando:**

- La invalidación acierta en el 100 % de una batería **etiquetada por otra persona** con la tabla de dependencias.
- Un tercero verifica un paquete sin acceso a Actaira.
- El 100 % de las manipulaciones se detectan como fallo: reordenar, borrar, cambiar un byte, reusar una firma, un token RFC 3161 sin firma válida, o una vista dividida con dos cabezas incompatibles.
- La alerta tiene un p95 de 5 minutos como máximo.

**Pasada adversarial de C6:**

| Crítica | Corrección |
|---|---|
| No se decía quién firma; si firmaba la nube, una Actaira comprometida reescribía antes de firmar | Firma el runner con clave del cliente |
| Merkle más RFC 3161 no impide una vista dividida | Log de transparencia externo y pruebas de consistencia |
| Offline no hay OCSP | Respuesta de revocación en el paquete |
| La batería de invalidación era circular | Tabla de dependencias previa y etiquetado de otra persona |
| "Página de assurance" se confunde con un encargo ISAE 3000 | "Estado de evidencia" y aviso fijo |
| "24/7" con un solo operador: si cae Actaira de madrugada, nadie se entera | Latido y estado `error`; SLO sin SLA (sección 9) |

### C7. Capa de cumplimiento

**Objetivo:** que la evidencia entre en las auditorías que la empresa ya pasa.

**Es una capa, no el producto.** Se activa por inquilino. Lee la evidencia de C6 y la traduce a controles de cada marco. El núcleo abierto y la plataforma funcionan igual sin ella, y se puede vender aparte o incluida en planes superiores.

**Cómo se presenta:** como "exportación de evidencia", nunca como la identidad del producto. Si en la web aparecen nueve marcos, Actaira vuelve a parecer una plataforma GRC. En la portada solo salen SOC 2, ISO 27001 e ISO 42001, más el AI Act por posicionamiento europeo; AIUC-1 y CSA AI-CAIQ van en la capa, en páginas secundarias. Los marcos marcados como backlog en la tabla se activan cuando un cliente los pide.

**Entregables:**

- **Catálogo de mapeos versionado**, con cada identificador citado contra el texto oficial en el repo. **SOC 2, ISO 27001, ISO 42001, AI Act, AIUC-1 y CSA AI-CAIQ**, que piden los clientes enterprise de los builders; los de backlog, según demanda.

| Marco | Controles a los que aporta evidencia |
|---|---|
| **AI Act** | Art. 4 (alfabetización, en la redacción del Reglamento 2026/1744, que pide apoyar su desarrollo). Art. 50.1 (divulgación de interacción con IA), solo si la configuración de divulgación está mediada. Para alto riesgo: responsable del despliegue, arts. 26.5 (seguimiento) y 26.6 (registros durante al menos seis meses); proveedor, arts. 9, 12, 14, 15, 72 y 73. Calendario del alto riesgo tras el Ómnibus: 2 de diciembre de 2027 (anexo III) y 2 de agosto de 2028 (anexo I). Cada exportación etiqueta si el builder actúa como proveedor o como responsable del despliegue |
| **ISO/IEC 42001:2023** (comprobado contra la tabla A.1) | A.4.2 a A.4.5 (documentación de recursos: datos, herramientas, sistemas), que es el inventario. A.6.2.4 (verificación y validación), que son las pruebas de política y la batería de evasión. A.6.2.5 (despliegue). A.6.2.6 (operación y monitorización). A.6.2.7 (documentación técnica), que es el gemelo digital. A.6.2.8 (registro de eventos). A.7.5 (procedencia de los datos), con C8, en backlog. A.8.4 (comunicación de incidentes), con las alertas. A.9.4 (uso previsto), que son las políticas frente a las capacidades. A.10.2 y A.10.3 (reparto de responsabilidades y proveedores), que son los servidores MCP y los SaaS. A.10.4 (clientes), que es el modo builder. Las evaluaciones de impacto de A.5 las hace la organización; Actaira solo les aporta datos |
| **ISO/IEC 27001:2022** | 5.9 (inventario), 5.15, 5.16 y 5.18 (acceso e identidades), 8.2 (acceso privilegiado), 5.19 a 5.23 (proveedores y nube), 8.9 (gestión de la configuración, que encaja con el lockfile), 8.15 (registro), 8.16 (monitorización), 8.32 (gestión de cambios) |
| **SOC 2** | CC6.1 a CC6.3 (acceso lógico), CC7.1 y CC7.2 (detección y monitorización), CC8.1 (cambios), CC9.2 (terceros, como los servidores MCP) |
| **AIUC-1** | El "SOC 2 para agentes", con auditoría anual y retests trimestrales; qué controles pueden llevar evidencia de Actaira |
| **CSA AICM y AI-CAIQ** | Cuestionario de seguridad de IA que piden los clientes enterprise; **prerrellenado por cliente del builder** desde el grafo, con cita a cada respuesta |
| *Backlog* **NIST AI RMF** | Funciones Govern, Map, Measure y Manage |
| *Backlog* **ENS (RD 311/2022)** | op.exp.1 (inventario), op.exp.3 (configuración de seguridad), op.exp.5 (cambios), op.exp.8 (registro de actividad), op.acc.2, op.acc.3 y op.acc.4 (acceso, segregación, derechos), op.mon.3 (vigilancia), op.ext.4 (interconexión). Solo obliga al sector público y a sus proveedores; si Actaira les sirve, ella misma necesitará certificarse |
| *Backlog* **NIS2** | Art. 21.2, letras (d) cadena de suministro, (e) adquisición y desarrollo, (f) evaluación de eficacia, (i) control de acceso y gestión de activos. La ley española de transposición se comprueba en el BOE en este bloque |
| *Backlog* **DORA** | Gestión del riesgo de TIC de terceros y registro de información |
| *Backlog* **RGPD** | Arts. 30, 32, 35 y 17 (supresión, enlazado con C8) |

- **Formatos:**
  - CSV y JSON primero;
  - Vanta por su API de documentos y Drata por sus conexiones personalizadas;
  - OSCAL `assessment-results` después.
- **Paquete de auditoría por periodo:**
  - la **población de caminos mediados**, con la cobertura del periodo como N de M capacidades mediadas, N de M credenciales intermediadas y N de M fuentes observadas, con la lista de lo no mediado y lo no visto, nunca como porcentaje;
  - una **conciliación con fuentes independientes** (CloudTrail, registros de auditoría de los SaaS), para que el auditor pueda probar integridad y exactitud.
- **Retención:** mínimo de 6 meses en los planes de pago, con aviso en la exportación si la retención contratada es menor.
- **Aviso fijo:** aporta evidencia a controles; no certifica ni dice "cumples".

**Listo cuando:**

- Cada identificador tiene su cita en el repo.
- Un auditor o consultor de SOC 2, ISO 27001 o ISO 42001 revisa un paquete real y dice qué le falta; su respuesta se convierte en tests.
- La exportación a Vanta y Drata funciona en cuentas de prueba.

**Pasada adversarial de C7:**

| Crítica | Corrección |
|---|---|
| "Población completa" que solo cubre lo mediado: el auditor la rechaza | Población de caminos mediados, cobertura y conciliación |
| Los arts. 4 y 50 se citaban como aplicables y no estaban en la tabla; los arts. 72 y 73 son del proveedor | Tabla corregida con el papel de cada uno |
| ISO por nombre, sin números | Números concretos, comprobados contra la norma |
| Faltaban controles de terceros y de segregación | CC9.2, op.acc.3, op.ext.4, 5.19 a 5.23 |
| 7 días de retención contra los seis meses del art. 26.6 | Mínimo de 6 meses en pago |
| Nueve marcos son un pozo | Seis en la capa (cuatro en portada); el resto en backlog |

### C8. Gobierno de memoria (backlog, no bloque)

**Estado:** backlog; entra en la fase 6 (ampliación). El gobierno de memoria puede ser otra empresa entera (Redis, Postgres, bases vectoriales, memorias de proveedores, checkpointers, copias de seguridad, semántica de borrado). Lo de abajo es el diseño para cuando llegue.

**Objetivo:** responder qué recuerda un agente, de quién, de dónde vino, cuándo caduca y si se puede borrar del todo.

**Entregables:**

- Registro de almacenes de memoria (desde C1 y el runtime).
- Procedencia en escritura vía SDK: origen, sujeto con HMAC (clave en el runner), base legal declarada, caducidad y lectores.
- Políticas de memoria en Cedar.
- Borrado propagado y comprobado en los almacenes conectados, con prueba en el libro.

**Listo cuando:**

- En un entorno con dos almacenes conectados, el 100 % de las escrituras mediadas llevan procedencia.
- Un borrado por sujeto se comprueba con una consulta posterior en los dos.
- Lo no mediado sale con su valor de `coverage` (`observed`, `declared` o `unseen`), nunca como mediado.

**Pasada adversarial de C8:**

| Crítica | Corrección |
|---|---|
| Sin sujeto guardado al escribir no hay borrado por sujeto | La procedencia va en la escritura; lo anterior sale "sin procedencia" |
| Es el módulo más especulativo | Backlog, en la fase 6, detrás de C7 |

### C9. Actaira Cloud: flota, builders y self-serve

**Objetivo:** la plataforma de pago, que una empresa contrata sin hablar contigo.

**Entregables de producto:**

- **Alta y primera pantalla:** alta con GitHub, conexión de repos con la GitHub App y la Action que sube el lockfile, y primera pantalla con valor en menos de 10 minutos; desde la fase 3, runner con un comando.
- **Consola de flota:** cambios de capacidad, políticas violadas, evidencia caducada, dependencias MCP desconocidas y permisos excesivos.
- **Ficha de agente** con el porqué, el blast radius y los botones revocar, pedir aprobación y aceptar cambio.
- **Modo builder multicliente, lo primero:** subinquilinos por cliente, con un **contrato por cliente** y un **pasaporte por agente v1** (capacidades potenciales, contrato y cobertura, con la marca del builder, un enlace verificable y un badge sin estado; nunca dice que el agente "cumple", F-0029). Después, políticas y evidencia propias y una página de estado de evidencia con la marca del builder.
- **Máquina del tiempo** sobre el historial de lockfiles: qué podía hacer cada agente en un commit o una fecha.
- **Aviso por MCP:** cuando el rastreador ve que una versión nueva de un servidor MCP añade una capacidad irreversible, avisa a cada inquilino que lo usa, con los datos de ese inquilino y sin cruzarlos con los de otro.
- **IA incluida por defecto** (las siete piezas) con un modelo alojado en la UE y cuota por plan. Se puede usar clave propia o apagarla por inquilino. El proveedor del modelo figura como subencargado en el DPA, con retención cero donde el proveedor la ofrezca.
- **Investigador de incidentes** (pieza 6).
- **Ask Actaira:**
  - el modelo solo ve el esquema y los identificadores, y la consulta generada se valida contra una gramática;
  - se avisa de que es IA (art. 50.1);
  - el LLM está alojado en la UE.
- **Plataforma:** SSO OIDC, SCIM en Enterprise, RBAC, registro de auditoría propio, alojamiento en la UE, RLS forzado y página de estado con SLO.

**Entregables para vender a escala:**

- **Sociedad:**
  - la forma jurídica y la facturación (compatible con Verifactu) las decide el titular con su asesoría; el código solo depende del puerto `Billing`.
- **Cobro:** un **Merchant of Record** por defecto, que factura y asume el IVA OSS y el sales tax de EE. UU., de modo que tú solo facturas al MoR con un sistema compatible con Verifactu. Stripe directo solo para Enterprise en la UE, con facturación Verifactu aparte.
- **RGPD:**
  - Actaira es subencargada en la cadena responsable, builder y Actaira, con autorización previa de toda la cadena (art. 28.2 y 28.4);
  - DPA con lista de subencargados y aviso de cambios;
  - registro del art. 30.2;
  - la clave HMAC nunca en la nube.
- **DORA:** anexo de cláusulas del art. 30, plan de salida y LEI **solo cuando un cliente financiero lo pida**; mientras tanto, backlog.
- **Confianza:**
  - cuestionario de seguridad estándar (CAIQ o SIG Lite) y trust center propio;
  - seguro de responsabilidad civil profesional y ciber;
  - pentest externo;
  - condiciones con limitación de responsabilidad.
- **CRA:** clasificación del runner frente al anexo III antes de cobrar y previsión del marcado CE para diciembre de 2027.
- **Atestación:** SOC 2 Tipo I o ISO 27001 cuando haya clientes que paguen, como requisito para Enterprise y para quien la exija en su revisión de proveedores. Hasta entonces se vende self-serve y con pilotos, sin prometerla.

**Listo cuando:**

- Un equipo externo se da de alta y ve su primer cambio de capacidad sin ayuda, cronometrado.
- Los tests de fuga entre inquilinos y subinquilinos dan 0 fugas.
- Cuando haya clientes que paguen, el pentest queda sin críticos ni altos abiertos.

**Pasada adversarial de C9:**

| Crítica | Corrección |
|---|---|
| Vender evidencia para auditorías ajenas sin informe propio: se queda fuera en la revisión de proveedores | CAIQ, trust center, seguro y atestación como puerta |
| "SL o alta" no son alternativas | SL más RETA societario, presupuestado |
| Stripe no factura Verifactu y vender en USD a todo el mundo complica el IVA | Merchant of Record por defecto |
| Faltaba la cadena de encargados del RGPD y las cláusulas de DORA | DPA, subencargados, art. 30.2, anexo DORA, plan de salida, LEI |
| Multiinquilino con subinquilinos es donde se fugan datos | RLS forzado, contexto en la transacción y tests de fuga en la CI |

### C10. Escaparate, design partners y socio

**Objetivo:** convertir el producto en prueba pública y en conversaciones con compradores.

**Entregables:**

- **Publicación:** Show HN, GitHub Marketplace, registro MCP, PRs de documentación en los SDK, artículos técnicos y propuestas de charla; el estudio, cuando esté.
- **Ecosistema:**
  - ejemplos y PRs de documentación en OpenAI Agents SDK y LangGraph;
  - entrada en el registro MCP;
  - un exportador para quien ya use LangSmith o Langfuse.
- **Design partners:** tres builders con agentes en producción. Se buscan **desde C2**, con el estudio y el diff en la mano.
- **Cartas de intención:** tres, con precio.
- **Demo de cinco minutos:** lockfile, diff en PR, tool MCP que cambió sin tocar código, evidencia caducada y exportación. Con C4, además un bloqueo.

**Listo cuando:** las señales de la sección 5 están medidas y publicadas.

**Pasada adversarial de C10:**

| Crítica | Corrección |
|---|---|
| Las estrellas no son adopción | Repos con la Action activa, runners conectados y retención |
| 30 repos y 5 runners no mueven a un socio a dejar su sueldo | Umbral para buscar socio: cartas con precio o pilotos pagados, más retención |
| Buscar cartas al final retrasaba todo | Desde C2 |

---

## 8. Los números que se enseñan

Son objetivos hasta que un eval los produce; se guardan con fecha y commit.

| Qué | Umbral |
|---|---|
| Descubrimiento | Cota inferior de Wilson del recall de tools de al menos 0,80; tasa de `unresolved` publicada |
| Diff | 100 % en la batería; 0 de 200 falsos "capacidad nueva" (Wilson hasta el 1,9 %) |
| Efectivas | 0 capacidades `effective` sin respuesta de API guardada |
| Cambios sin código | 100 % detectados en 15 minutos o menos |
| Decisión | p99 de 5 ms como máximo; 0 discrepancias entre cedar-go y la CLI de Cedar |
| Evasión | 0 acciones prohibidas en 300 casos o más, incluidas la llamada directa, el runner caído y el socket suplantado |
| Kill switch | p95 de 10 s como máximo; corte local con la nube caída |
| Cobertura | N de M fuentes observadas, N de M capacidades mediadas y N de M credenciales intermediadas, con lo no visto listado; nunca un porcentaje global (`docs/cobertura.md`) |
| Causal | Porcentaje de efectos confirmados en el stack de un design partner |
| Evidencia | 100 % de manipulaciones detectadas, incluida la vista dividida; invalidación al 100 % sobre etiquetado ajeno |
| Alertas | p95 de 5 minutos como máximo |
| Self-serve | Primer valor en menos de 10 minutos sin ayuda |
| IA: clasificador | Cota inferior de Wilson del recall de `irreversible` de al menos 0,80; 0 rebajas de gravedad en 300 casos de inyección o más |
| IA: explicaciones y resúmenes | 100 % de frases publicadas con cita válida (las que no, se descartan) |
| IA: políticas | 100 % de propuestas aceptadas que compilan y pasan sus casos; 0 ampliaciones sin marca |
| IA: coste | Tokens, coste y latencia por llamada y por inquilino, publicados |

---

## 9. Self-serve, precio y soporte

**Quién paga y quién no** (sección 0): el desarrollador usa el open source gratis y es la distribución. El builder es el primer cliente de pago, por el contrato por cliente y el pasaporte que enseña a sus clientes. Team es el segundo plan. Enterprise no se vende de forma directa: llega por adopción interna o por integraciones que exportan el contrato (JSON estable, SARIF, AI-BOM), y su plan queda en el backlog hasta que haya equipo.

**Unidad de cobro:** agente activo, es decir, un agente con eventos en los últimos 30 días, sin contar versiones ni despliegues.

**Por qué además hay una cuota:** el agente es la unidad mental, pero no mide el coste. Una empresa puede tener 3 agentes y 10 millones de ejecuciones, y otra 80 agentes y 100.000. Por eso cada plan incluye una cuota de **acciones gobernadas** (decisiones de política y eventos ingeridos) y días de evidencia. Al principio la cuota es un límite blando: se avisa y se habla, sin cobro por exceso automático, que complica el self-serve antes de saber cuánto consume un cliente real. El exceso de pago llega cuando haya datos de uso.

**Precios:** los pone Marcos en `config/pricing.yaml`, y el código y el producto de Stripe los leen de ahí. Claude Code no inventa precios. Las cifras de abajo son la referencia de la versión 2.0 del plan, a validar, y el código no las usa.

| Plan | Qué incluye | Precio |
|---|---|---|
| **Open source** | CLI, Action, lockfile con el contrato (`intent`, en formato ACM), `inspect`, diff y check contra el contrato, alcanzabilidad, flujos tóxicos, blast radius potencial, SARIF, JSON estable, AI-BOM, `verify`; y el registro público de servidores MCP | 0 |
| **Prueba (nube, fase 2)** | 7 días de la plataforma, con topes duros de uso (ver abajo); después pasa a solo lectura y vuelve al open source | 0 |
| **Builder (desde la fase 2, el primer plan de pago)** | Subinquilinos por cliente, contrato por cliente y pasaporte por agente v1 (capacidades potenciales, contrato y cobertura, con la marca del builder, enlace verificable y badge sin estado), más todo lo de Team. Desde la fase 3 mejora con capacidades efectivas; desde la 5, pasaporte firmado y página de estado de evidencia | Suscripción, en `config/pricing.yaml`. Referencia 2.0: base de 500 a 1.500 EUR al mes más importe por agente activo |
| **Team (desde la fase 2, el segundo plan)** | Flota, historial y diff de capacidades, máquina del tiempo, alertas, IA incluida, cuota de acciones; desde la fase 3, capacidades efectivas; desde la 4, control | Suscripción, en `config/pricing.yaml`. Referencia 2.0: 299 EUR al mes |
| **Enterprise (backlog hasta que haya equipo)** | BYOC, SCIM, retención larga, capa de cumplimiento completa; además, detrás de la atestación SOC 2 o ISO 27001 | Anual, cuando se abra |

El informe de piloto de pago único de la versión 2.0 (300 a 800 EUR por informe) sale de la tabla: lo sustituye el plan Builder de suscripción. Es una interpretación de Claude Code de la decisión del 2 de octubre de 2026, anotada como discrepancia en `docs/estado/E1.md`; si Marcos lo quiere, vuelve como pago único en el paso de cobro de la E3.

**Qué va en Actaira open source y qué en Actaira Cloud.**

No se recorta el código abierto. Es el motor de adopción y los números de GitHub que convencen a un socio: si el núcleo gratis es flojo, no hay estudio que lo salve. La línea es otra:

- **Código abierto:** todo lo que necesita una persona en un repo.
  - Discover, lockfile, el contrato y su validador, `inspect`, diff, blast radius declarado, `verify`.
  - Base de conocimiento ya clasificada y el registro público de servidores MCP.
  - IA opcional con su clave o con un modelo local.
- **Actaira Cloud:** todo lo que necesita un equipo de forma continua.
  - Flota, capacidades efectivas, control en tiempo de ejecución, evidencia vigilada, exportación y el modo builder, con contrato por cliente y pasaporte.
  - **La IA ya puesta**, sin clave.

**Por qué esa línea y no esconder la IA en Actaira Cloud:**

- **Dónde molesta la clave:** en la CI (un secreto por repo) y en las empresas, que no dejan mandar código a un proveedor cualquiera. Justo eso es lo que Actaira Cloud resuelve: IA incluida, en la UE y con DPA.
- **Cómo se evita que el gratis quede cojo:** con la base de conocimiento ya clasificada, casi nadie en el código abierto necesita clave para ver el aha.
- **Por qué no quitarla del todo del código abierto:** a los desarrolladores que ya tienen clave o Ollama les gusta usarla, y quitárselo solo resta adopción.

**Cuota de IA por plan:**

| Plan | Cuota de IA |
|---|---|
| Prueba | Tope en euros por cuenta y tope global mensual (ver "Cómo la prueba gratuita nunca da pérdidas") |
| Builder y Team | Uso razonable incluido |
| Enterprise (backlog) | Clave propia o modelo propio si lo exige su política |

**Soporte y disponibilidad, dicho con honestidad:**

- **La vigilancia es automática 24/7,** con el latido del runner para que un fallo de Actaira se vea.
- **SLO publicado** del 99,5 %, sin créditos ni SLA contractual hasta que haya equipo.
- **Soporte humano:** horario laboral CET con tiempos de primera respuesta publicados y un canal compartido de Slack con los design partners.
- **Soporte humano 24/7 y SLA** solo cuando haya equipo o socio. Venderlo antes sería mentir.

---

### Cómo la prueba gratuita nunca da pérdidas

**Principio:** el open source es gratis para siempre y no te cuesta nada, porque corre en el repo y en los runners de GitHub del usuario. Lo gratis **en tu nube** es una prueba con fecha de fin y con topes duros, así que se puede limitar sin miedo a frenar la adopción.

**Topes por cuenta (valores iniciales, se ajustan con los datos de uso):**

| Límite | Valor inicial | Qué pasa al llegar |
|---|---|---|
| Duración | 7 días desde el alta | La cuenta pasa a solo lectura; los datos se borran a los 30 días si no contrata, avisando antes |
| Agentes activos | 3 | No se añaden más |
| Repos conectados | 3 | No se conectan más |
| Lockfiles subidos (acciones de la Action) | 200 | Se rechaza la subida con un mensaje claro |
| Historial | 7 días | Lo anterior no se guarda |
| IA | Tope en euros por cuenta (por ejemplo, 0,50 EUR), medido con tokens por precio del modelo | Las piezas de IA se apagan y sale la plantilla fija |
| Almacenamiento | Pocos MB por cuenta | Se rechaza lo que exceda |
| Runner, control, evidencia, modo builder, capa de cumplimiento | No incluidos | Solo en pago |

**Tope global, que es lo que garantiza que nunca pierdes:** un presupuesto mensual fijo para todas las pruebas juntas (por ejemplo, 20 EUR al mes, dentro de los créditos de Azure). Cada acción de una cuenta de prueba descuenta de ese presupuesto. Al agotarse, las pruebas nuevas entran en lista de espera y las activas siguen solo en lectura hasta el mes siguiente. Además:

- presupuestos y alertas de gasto en Azure al 50, 80 y 100 %;
- cuando haya ingresos, el presupuesto de pruebas se fija como un porcentaje de lo que se cobra.

**Contra el abuso:**

- una prueba por organización de GitHub;
- cuentas de GitHub con antigüedad mínima;
- límites de peticiones por IP y por token;
- sin tarjeta al empezar, para no frenar el alta. Si el abuso aparece, se pide tarjeta sin cobrar.

**Cómo se mide que no hay pérdidas:** coste real por cuenta de prueba (Azure, base de datos, IA) registrado cada día en la propia aplicación y comparado con el tope. El objetivo es que el coste de todas las pruebas quede por debajo del presupuesto global el 100 % de los meses.

**Qué ve el usuario al acabar la prueba:** su último diff de capacidades y lo que la plataforma habría detectado en esos 7 días (cambios, flujos tóxicos, alertas), con el botón para contratar. El open source sigue funcionando igual.

### actaira.com: la puerta de todo

La plataforma self-serve se sirve desde el dominio que ya tienes, con subdominios separados:

| Dirección | Qué es | Dónde vive | Coste |
|---|---|---|---|
| `actaira.com` | Web pública: qué hace, demo, precios, blog, el estudio | Página estática en Cloudflare Pages (sustituye al servidor de Hetzner) | 0 |
| `docs.actaira.com` | Documentación de la CLI, la Action y la plataforma | Estática, generada desde el repo | 0 |
| Registro público de servidores MCP | Web estática generada desde `actaira-kb`: qué hace cada tool, lo declarado por el servidor frente a lo potencial según la base de conocimiento y el historial por versión, sin puntuaciones | GitHub Pages de `actaira-kb`; un dominio propio solo si Marcos lo pide | 0 |
| `app.actaira.com` | Actaira Cloud: alta con GitHub, flota, diff, alertas, contrato por cliente y pasaporte, cobro | Azure Container Apps en la UE, con escala a cero (ADR 16) | Casi 0 sin usuarios; cubierto al principio por créditos de Microsoft for Startups |
| `status.actaira.com` | Página de estado con el SLO | Servicio gratuito o estática | 0 |
| `github.com/actaira` | Núcleo abierto | GitHub | 0 |

**Por qué separados:** la web de marketing no comparte cookies ni sesión con la aplicación, y se puede rehacer sin tocar la plataforma. La aplicación tiene su propia política de seguridad de contenido.

**Qué hay que cambiar de la web actual antes de publicar nada:**

- Quitar todo lo que no es verdad o ya no es el producto: "113 artículos", "trazabilidad 100 %", "ROI 88,5 %", ahorros en euros, firmas "simuladas" y los 12 módulos. Además de credibilidad, es un riesgo de publicidad engañosa.
- La portada habla de capacidades de agentes (detectada, potencial, efectiva). El cumplimiento aparece como una capa, en una página secundaria.
- Páginas legales: aviso legal (LSSI) con los datos del titular, privacidad, cookies y, al abrir la fase 2, condiciones y DPA.
- `/.well-known/security.txt` y una página de divulgación de vulnerabilidades.

**Quién despliega y cómo:** la plataforma la desplegamos nosotros, en **tu** cuenta de nube, porque el operador y responsable legal del servicio eres tú.

- **Claude Code construye todo en el repo:**
  - la aplicación;
  - la infraestructura como código (Bicep y az CLI, validada con `az deployment what-if` antes de aplicar) y las imágenes en GitHub Container Registry;
  - los flujos de GitHub Actions que despliegan solos a cada versión: primero a un entorno de pruebas, y a producción solo con aprobación.
- **Tú haces solo lo que exige tu identidad**, una vez y con la lista de comandos exacta:
  - `az login` en tu suscripción de Azure (después Claude Code crea con az CLI la identidad federada OIDC entre GitHub y Azure, así que no hay claves en el repo);
  - crear la cuenta de Stripe o del Merchant of Record y meter los secretos (Stripe, claves del modelo) en Key Vault;
  - apuntar el DNS en Cloudflare.

  Después, cada despliegue sale de un merge, sin que toques nada.
- **Dónde:** Azure en la UE, como decidiste, en la región de España o de Europa occidental:
  - Container Apps para la aplicación;
  - Postgres serverless para el grafo (Neon en la UE al principio, o Azure Database for PostgreSQL con créditos);
  - Key Vault para secretos;
  - Cloudflare delante (DNS; la web, en Pages);
  - Log Analytics con tope diario y retención corta, réplicas mínimas a cero, presupuestos y alertas al 50, 80 y 100 %.

  La región y los tamaños se miden al abrir la fase 2 y se justifican en el ADR 16. Antes de pagar, pedir los créditos de Microsoft for Startups (los primeros caducan a los 90 días de activarlos, así que se activan al abrir la fase 2).
- **Cuándo:**
  - la web de `actaira.com`, ya;
  - la aplicación, al abrir la fase 2, cuando el núcleo abierto ya produzca lockfiles que subir.

  Desplegarla antes es pagar nube y asumir obligaciones de RGPD sin nada que ofrecer.

**Correo:** el buzón de Microsoft 365 caducó. Hacen falta `hola@`, `soporte@` y `security@`:

- **Recibir:** reenvío gratis con Cloudflare Email Routing, o un buzón barato.
- **Enviar como el dominio:** configurar SPF, DKIM y DMARC.
- **Correo de la aplicación** (altas, alertas): un proveedor transaccional con capa gratuita.

**Dominio:** comprobar dónde está registrado `actaira.com` y su renovación, activar el bloqueo de transferencia y la verificación en dos pasos en el registrador y en Cloudflare.

## 10. Cómo llega el socio

- **Antes, la decisión de la sección 0.** Sin ella, ningún socio serio se sienta.
- **Lo que le convence:** cartas de intención con precio o pilotos pagados, retención medida y adopción del código abierto (repos con la Action, runners). La demo sola no basta.
- **Perfil:** alguien que haya vendido seguridad o herramientas de desarrollo a empresas (ex Snyk, Wiz, Datadog, GitGuardian, o del ecosistema de Madrid y Barcelona).
- **Dónde:**
  - **INCIBE Emprende**: Actaira ya fue seleccionada en Sherpa Tribe, su programa;
  - comunidades de agentes y MCP y eventos de IA en Madrid;
  - un asesor con red que entre antes que el socio;
  - YC co-founder matching, como vía secundaria.
- **Cómo:** pacto de socios con vesting a 4 años y cliff de 1 año, una vez exista la SL.
- **Los builders son el primer cliente de pago y el canal que no depende de tu influencia.** Sus clientes les preguntan:
  - qué puede hacer mi agente y qué credenciales tiene;
  - si ha cambiado algo;
  - si puedes probar que no hace X;
  - qué pasó en este incidente y cómo se revoca esta capacidad.

  Actaira les deja responder con el contrato y el pasaporte de cada agente, y más adelante con la página de estado de evidencia, que pueden enseñar y revender, así que mejora su propio producto. La venta es entre técnicos (tú con su CTO), que sí puedes hacer solo. Cada builder que enseña su página a sus clientes vende Actaira por ti.

---

## 11. Coste

**Fases previa, 0 y 1 (núcleo abierto):**

| Concepto | Coste orientativo |
|---|---|
| GitHub, CI, Action, marketplace | 0 |
| Dominio y correo | Unos 50 EUR al año |
| Firma | cosign sin claves 0; firma de Apple y de Windows a 0 hasta que se pidan |
| Búsqueda de la marca Actaira | Búsqueda propia en OEPM y EUIPO gratis; informe de un agente de marcas si hay dudas, unos cientos de euros |
| Cuentas de prueba para C3, en la fase 3 (AWS, Salesforce, Zendesk, HubSpot) | Capas gratuitas o de desarrollador; decenas de euros al mes como mucho |
| Etiquetado de la segunda persona, si no es voluntaria | Unas horas de pago; presupuestar antes de C1 |
| LLM para clasificar la base de conocimiento pública (una vez por tool, cacheado por hash) y para los evals de IA | 0 en las fases 0 y 1 (las 50 tools se revisan a mano); decenas de euros al clasificar el registro MCP en la fase 2; después, marginal |
| Nube (Azure con escala a cero, desde la fase 2) | Casi 0 sin usuarios; cubierto al principio por créditos de Microsoft for Startups |

**Para poder cobrar (C9), primer año:**

| Concepto | Coste orientativo |
|---|---|
| Constitución de la SL | 300 a 600 EUR |
| Gestoría | 60 a 150 EUR al mes |
| Plantillas legales (privacidad, DPA, condiciones; anexo DORA solo si un cliente financiero lo pide) | 500 a 1.500 EUR |
| Pentest externo | 3.000 a 8.000 EUR |
| Seguro de RC profesional y ciber | 1.000 a 3.000 EUR al año |
| Registro de marca de Actaira (OEPM o EUIPO, con búsqueda previa) | De unos 150 EUR por marca y clase en la OEPM a unos 850 EUR en la EUIPO |
| LEI | Solo si un cliente financiero lo pide |
| **Total sin atestación** | **De unos 6.000 a unos 16.000 EUR, sin contar la cuota del RETA** |
| SOC 2 Tipo I o ISO 27001 (requisito para Enterprise, cuando haya clientes que paguen) | 10.000 a 30.000 EUR más |

Cobrar a escala cuesta dinero antes del primer euro. Por eso la sección 5 frena el gasto, no la construcción: SL, pentest, legal y atestación esperan a clientes que paguen.

---

## 12. Riesgos

| Riesgo | Cómo se cubre |
|---|---|
| LangSmith cierra tools y MCP, o Snyk añade semántica de capacidades | Neutralidad, evidencia verificable por terceros, modo builder y velocidad hasta C2 |
| Nadie instala la Action | Señales de la sección 5; se revisa el mensaje y la demo sin parar la construcción |
| Capacidades efectivas inabarcables | Una fuente por vez, solo las que dan permisos reales, con niveles de confianza |
| Actaira como punto de ataque (runner con credenciales, proxy en el camino) | Intermediación, solo lectura, lista de destinos, socket autenticado, binarios firmados, pentest y código abierto |
| CRA y responsabilidad del fabricante | Proceso desde C0, clasificación antes de cobrar, marcado CE previsto |
| Responsabilidad si pasa un daño | Promesa honesta, limitación de responsabilidad y seguro |
| Una persona con once bloques | Orden por dependencias (sección 5), gasto frenado hasta tener clientes, y bloques pequeños y cerrados |

---

## 13. Pasada adversarial del plan en su conjunto

Dos revisiones independientes y hostiles, con comprobación en la web de lo dudoso:

- **Técnica:** arquitectura y C0 a C6. 24 hallazgos: 2 críticos, 8 altos y 14 medios.
- **De inversor, auditor GRC y abogado o gestor español:** mercado, C7 a C10 y el conjunto. 21 hallazgos: 3 críticos, 10 altos y 8 medios.

Las 45 de la 1.1 están aplicadas, y también las de las revisiones de la 1.4 y la 1.5 (tres filas al final, más las decisiones de la 1.6). Las correcciones de cada bloque están en su tabla. Esto es lo que cambió el plan entero:

| Crítica | Corrección |
|---|---|
| **Crítica.** Con la credencial en el proceso del agente, el control era un aviso | Intermediación de credenciales como ADR y en la batería |
| **Crítica.** Scopes OAuth vendidos como capacidades efectivas | Fuente real de permisos por sistema y niveles de confianza |
| **Crítica.** Sin criterio de prioridad ni de gasto | Orden por dependencias, sin plazos; las señales de la sección 5 deciden prioridad y gasto, no paran la construcción |
| **Crítica.** Vender evidencia para auditorías ajenas sin informe propio, seguro ni cuestionario | Paquete de confianza y atestación como puerta para vender fuera de los design partners |
| El alcance mínimo no era mínimo | C0 a C2, estudio y hash de MCP como lanzamiento; libro local en la fase 5; C3 y C4 por orden de dependencias, sin esperar a cartas |
| "Ningún bloque depende de uno posterior" era falso | Dependencias reales escritas |
| La firma y el anclaje de la evidencia no resistían a una Actaira comprometida | Firma del runner con clave del cliente, log de transparencia y consistencia |
| Criterios "publicados" sin umbral | Umbrales de pasa o no pasa en la sección 6 |
| Competencia incompleta (Snyk Agent Scan, Microsoft Agent 365, Noma en tiempo de ejecución) | Tabla ampliada; "dónde se gana" reescrito |
| Faltaban CRA, RETA societario, cadena RGPD, DORA en la cadena y el coste real de cobrar | Integrados en C0, C9 y la sección 11 |
| "Assurance 24/7" y "página de assurance" podían leerse como aseguramiento profesional o SLA | Estado de evidencia, aviso fijo, latido y SLO sin SLA |
| Nombres reales de empresas en el modelo de datos y en los ejemplos | Ejemplos hipotéticos |
| Precio sin unidad ni plan Builder | Unidad definida, informe por cliente para builders, Team self-serve y Builder con base |
| **Revisión externa de la 1.4** (8 puntos): C0 demasiado grande, lanzar el diff y no `discover`, potencial frente a efectiva, C8 fuera, C5 más estrecho, compliance fuera de la portada, precio ligado solo a agentes, builders como primer cliente | Aplicados los 8, con tres matices: cosign y SBOM se quedan porque GoReleaser los da casi gratis; el exceso de uso empieza como límite blando; y como el builder es el primer cliente, su informe por cliente se adelanta a la fase 2 en vez de esperar a la página de estado de evidencia de la fase 5 |
| **Revisión hostil de la 1.5** (25 hallazgos, 5 críticos): decisión pendiente, cuña que ya no es exclusiva, nombre ocupado, demo que en repos reales no saldría, adopción que no se podía medir | Fase previa sin código con decisión escrita, nombre y conversaciones con builders; cuña reescrita en semántica de capacidades; tools de MCP desde el paquete fijado y medición en el corpus; método de medición publicado; primer producto de pago en una frase; precios reducidos a lo vendible; marcos aplazados sacados de C7 y C9; textos viejos alineados |
| **Barrido de mercado de la 1.5** (20 features) | En la fase 1: flujos tóxicos, SARIF, baseline con `accept`, Agent Skills, Vercel AI SDK, OWASP, deriva programada, anotaciones que mienten, procedencia del registro, pre-commit y GitLab, telemetría opt-in. Justo después: servidor MCP, playground, AI-BOM, lockfile firmado. En la fase 2: importar hallazgos de envenenamiento de tools de Snyk y Cisco, tarjetas A2A. En la fase 5, con la capa de cumplimiento: AIUC-1 y AI-CAIQ prerrellenado. Fase 6: registros de plataforma (AWS Agent Registry, Agent 365, Copilot Studio) |
| **Decisiones de Marcos en la 1.6** | Nombre único Actaira (open source y Cloud); sin plazos en ninguna parte; prioridad al núcleo abierto y a la plataforma self-serve, que se adelanta sin runner; las señales de mercado ya no paran la construcción, solo el gasto; cumplimiento como capa (ADR 15) |
| **Decisiones de Marcos en la 2.1** (2 de octubre de 2026) | El contrato de capacidades como idea central, con su doctrina y su reparto por épica (sección 0). Quién es quién: el desarrollador es la distribución, el builder el primer cliente de pago y Enterprise llega sin venta directa, con su plan en el backlog. `actaira inspect` y el registro público como primer lanzamiento (v0.2.0); el registro es producto, no comercial. El plan Builder de suscripción entra en la fase 2, con el precio en `config/pricing.yaml`; Team es el segundo plan. Métricas de producto en la sección 5. Frente a Snyk Agent Scan, la diferencia es la semántica y el contrato (sección 2) |

**Lo que ninguna revisión elimina:**

1. Que LangSmith, Snyk o un grande cierren el hueco antes de que el núcleo abierto tenga adopción. La respuesta es llegar pronto a C2, la neutralidad y la evidencia verificable por terceros.
2. Que el cuello de botella no es técnico sino comercial. Las señales de la sección 5 existen para que el mercado lo diga pronto y barato.

---

## Fuentes

- **Mercado y competencia:**
  - [LangSmith LLM Gateway](https://www.langchain.com/blog/introducing-llm-gateway) y [LangSmith Fleet](https://www.langchain.com/blog/introducing-langsmith-fleet)
  - [Galileo Agent Control](https://galileo.ai/blog/announcing-agent-control)
  - [AgentCore Policy GA](https://aws.amazon.com/about-aws/whats-new/2026/03/policy-amazon-bedrock-agentcore-generally-available/)
  - [Snyk agent-scan](https://github.com/snyk/agent-scan)
  - [Noma, control de acceso de agentes](https://noma.security/products/agent-access-control)
  - [Obsidian AI Blast Radius](https://www.obsidiansecurity.com/ai-blast-radius)
  - [Microsoft Agent 365](https://learn.microsoft.com/en-us/microsoft-agent-365/overview)
  - [Cisco y Astrix](https://www.calcalistech.com/ctechnews/article/dy5obf581)
  - [OpenAI y Promptfoo](https://openai.com/index/openai-to-acquire-promptfoo/)
  - [Las compras de Check Point](https://www.techzine.eu/news/security/138764/check-point-acquires-security-startups-cyclops-cyata-and-rotate/)
  - [Rauda](https://www.rauda.ai/), solo como referencia pública de qué hace un builder
- **Técnica:**
  - [Claves restringidas de Stripe](https://docs.stripe.com/keys/restricted-api-keys)
  - [Introspección OAuth de HubSpot](https://developers.hubspot.com/docs/api-reference/latest/authentication/manage-oauth-tokens)
  - [AWS SimulatePrincipalPolicy](https://docs.aws.amazon.com/IAM/latest/APIReference/API_SimulatePrincipalPolicy.html)
  - [Kubernetes SelfSubjectRulesReview](https://kubernetes.io/docs/reference/kubernetes-api/definitions/self-subject-rules-review-v1-authorization/)
  - [Autorización en MCP](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization) y [anotaciones de tools en MCP](https://blog.modelcontextprotocol.io/posts/2026-03-16-tool-annotations/)
  - [Spans de agente de OTel GenAI](https://github.com/open-telemetry/semantic-conventions-genai/blob/main/docs/gen-ai/gen-ai-agent-spans.md)
  - [cedar-go](https://github.com/cedar-policy/cedar-go)
  - [Vanta, subida de documentos](https://developer.vanta.com/docs/guides/upload-a-document) y [Drata, conexiones personalizadas](https://help.drata.com/en/articles/11995676-part-1-custom-connections-and-tests)
- **Normativa:**
  - [Reglamento (UE) 2026/1744](https://eur-lex.europa.eu/eli/reg/2026/1744/oj/eng) y [su entrada en vigor](https://www.whitecase.com/insight-alert/eu-ai-omnibus-enters-force-amending-ai-act)
  - [DORA, art. 30](https://www.digital-operational-resilience-act.com/Article_30.html)
  - [CRA](https://www.goodwinlaw.com/en/insights/publications/2026/09/alerts-lifesciences-technology-preparing-for-eu-cyber-resilience-act)
  - [Transposición de NIS2 en España](https://angelortegacastro.com/en/ley-coordinacion-gobernanza-ciberseguridad-nis2-estado-boe/)
  - [Aplazamiento de Verifactu (AEAT)](https://sede.agenciatributaria.gob.es/Sede/iva/sistemas-informaticos-facturacion-verifactu/nota-informativa-ampliacion-plazo-adaptacion-facturacion.html)
  - [Stripe y Verifactu](https://beel.es/en/blog/stripe-factura-legal-espana-verifactu)
- **Comprobado en la 1.2:**
  - [Describe en Apex: "by the current user"](https://developer.salesforce.com/docs/atlas.en-us.apexref.meta/apexref/apex_methods_system_sobject_describe.htm), [sObject Describe en REST](https://developer.salesforce.com/docs/atlas.en-us.api_rest.meta/api_rest/resources_sobject_describe.htm), [ObjectPermissions](https://developer.salesforce.com/docs/atlas.en-us.object_reference.meta/object_reference/sforce_api_objects_objectpermissions.htm), [PermissionSetAssignment](https://developer.salesforce.com/docs/atlas.en-us.object_reference.meta/object_reference/sforce_api_objects_permissionsetassignment.htm)
  - [Apps privadas de HubSpot y su endpoint de información del token](https://developers.hubspot.com/docs/apps/legacy-apps/private-apps/overview)
  - ISO/IEC 42001:2023, anexo A, tabla A.1, contra el ejemplar aportado
- **Queda para la org de prueba de C3** (no se puede cerrar leyendo documentación):
  - que el describe por REST refleja el usuario igual que en Apex;
  - el permiso mínimo para consultar `ObjectPermissions`;
  - que los conjuntos del perfil salen en la consulta;
  - el rol de Zendesk.

No es asesoramiento legal ni fiscal.
