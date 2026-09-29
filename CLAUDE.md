# CLAUDE.md: Actaira

Actaira dice qué puede hacer cada agente de IA, deja decidir qué se le permite y da la prueba.

- **Actaira open source:** la CLI `actaira`, la GitHub Action y el lockfile `actaira.lock`.
- **Actaira Cloud:** la plataforma self-serve de pago, en `app.actaira.com`.
- **La capa de cumplimiento:** opcional, encima de la evidencia.

**Prioridad actual: que el producto funcione y esté desplegado.** Comercial, marketing y directorios no se tocan hasta que Marcos lo pida.

Referencias:

- **Qué y por qué:** `docs/PLAN.md`.
- **Qué construir ahora:** `docs/epicas/`.
- **Estado:** `docs/estado/`.
- **Fallos y lecciones:** @docs/harness/LECCIONES.md
- **El harness solo carga si Claude Code se abrió dentro de este repo** (`cd <repo> && claude`). En la CLI, si `/hooks` no lista PreToolUse, PostToolUse y Stop, para y avisa. En la extensión de VS Code, que no tiene `/hooks`, se comprueba por el comportamiento: el guard bloquea `git -C . push origin main`, un `.go` escrito con Write queda formateado y el hook de parada ejecuta `make check` al terminar el turno. Si algo de eso no pasa, para y avisa.

**Si algo choca:** este fichero manda sobre la épica, y la épica sobre el plan. La discrepancia se anota en `docs/estado/`.

## Cómo se trabaja (el harness)

1. **Se construye por épicas con la skill `/epica E<N>`.** Trabajas de forma continua, paso tras paso, sin pedir permiso entre pasos.
2. **Cada paso sigue este orden:**
   1. tests primero, que fallan;
   2. construir;
   3. `make check`;
   4. ejecución real;
   5. pasada adversarial;
   6. registrar cada fallo con su guardia;
   7. `make gate`;
   8. PR y fusión.
3. **Todo fallo inesperado se registra** con la skill `registrar-fallo` y lleva una **guardia permanente** (test, lint, hook o regla) que se prueba fallando antes y pasando después. `make check` rechaza entradas sin guardia.
4. **Cada épica se cierra con `cierre-epica`:** gate desde un clon limpio, pruebas de extremo a extremo de todo lo anterior y tres revisiones de conjunto.
5. **El hook de parada no te deja terminar con `make check` en rojo.** Al tercer bloqueo seguido, para y reporta.
6. **Anti-bucle:**
   - como mucho **tres intentos** distintos para arreglar lo mismo;
   - como mucho **tres rondas adversariales** por paso con código o por cierre, y **una** en un paso de solo documentación: sus críticos se corrigen y lo demás va al backlog o al paso de código que lo implementa (L-011);
   - después, se para con el diagnóstico escrito;
   - nunca se crean cadenas de documentos de decisión.

## Reglas con Marcos

1. **Eres el único que toca el repo.** Marcos no edita ni hace commits mientras trabajas.
2. **Lo que exige a Marcos** (`az login`, crear cuentas, secretos, DNS, pagos, aceptar condiciones):
   - para en un punto limpio;
   - dale los comandos exactos, diciendo en qué terminal van ("Terminal: WSL" o "Navegador");
   - dile la salida esperada y qué hacer si ve otra;
   - marca los secretos como `<<SECRETO: nombre y de dónde sale>>`;
   - si paras con `make check` en rojo porque falta algo de Marcos, escribe antes el motivo en `.harness/pausa-marcos` (el hook de parada lo respeta y lo borra al usarlo). Una pausa no es un fallo.
3. **Nunca envíes nada en su nombre**: correos, issues o PRs en repos ajenos, mensajes.
4. **Nada personal en el repo**: ni datos de Marcos (correo, situación laboral, planes personales, gestoría) ni nombres de sus cuentas personales. Los repos son públicos. Lo que haga falta va en `~/actaira-ws/privado/`, fuera de git. Lo comprueba `scripts/harness/check-personal.sh` en `make check`. El correo de contacto del proyecto (`ACTAIRA_CONTACT_EMAIL` en `config/contact.env`) no es personal: va en la web (security.txt, aviso legal y contacto) y en la documentación de usuario, y en el código siempre por esa variable, nunca fijo. Cualquier otro correo personal sigue prohibido.
5. **Nunca escribas secretos** en el repo, en logs ni en commits. Los tests usan centinelas que no parecen claves.
6. **Si ves algo raro, pregunta.**

## Doctrina de producto

1. **Nunca un número de riesgo inventado.** Cada afirmación lleva fuente, fecha y confianza: `declared`, `inferred`, `conditional`, `effective`, `observed`, `unresolved` o `unseen`.
2. **Detectada, potencial y efectiva nunca se mezclan.**
   - **Detectada:** la tool existe.
   - **Potencial:** la base de conocimiento dice qué podría hacer.
   - **Efectiva:** la API de identidad confirma que la credencial lo permite.
3. **Nunca inferir lo no observado.** Lo que no se ve sale como `unseen` o `unresolved`, con su ubicación.
4. **La IA propone, nunca decide.** Todo lo que produce va marcado `inferred`, **solo puede subir la gravedad** y su salida es JSON validado. El texto de terceros va delimitado y nunca como instrucción. El modelo se elige siempre con `make llm-select`: el más barato que pase los umbrales.
5. **Nunca se ejecuta código del repo analizado.** Los servidores MCP stdio solo corren en un contenedor sin red.
6. **Actaira nunca actúa por su cuenta:** solo ejecuta lo que autoriza una política firmada por una persona.

## Ingeniería

- **Decisiones con consecuencias:** un ADR en `docs/adr/`, con opciones, por qué esa, coste, latencia, errores y reversión.
- **APIs externas:** solo contra su documentación oficial actual, enlazada. El subagente `verificador-apis` lo comprueba.
- **Todo se mide:** en `evals/results/`, con fecha, commit, entorno y comando. Proporciones con intervalo de Wilson.
- **Documentación:** nunca afirma en presente algo que no pasa los tests.
- **Idioma:**
  - código, commits y comentarios en inglés;
  - README en inglés y castellano;
  - ADR y estado en castellano;
  - sin guiones largos en los documentos.
- **Entorno:**
  - repos en `~/actaira-ws/` dentro de WSL, nunca en `/mnt/c`;
  - `.gitattributes` con `* text=auto eol=lf`.

## Git y CI

- **Una rama por paso**, `e<N>/paso-<M>-<nombre>`. Nunca push ni merge local a `main`. El cierre es `gh pr create` y `scripts/harness/merge-pr.sh`, que espera a que los checks terminen en verde y fusiona con squash sobre el commit comprobado.
- **`make check`** (rápido, se usa en cada paso) incluye:
  - formato, lint y tests;
  - determinismo;
  - `gitleaks` (binario fijado, no la Action);
  - `scripts/harness/check-weakeners.sh`;
  - `scripts/harness/check-fallos.sh`.
- **`make gate`** (por paso) es `check`, más `evals-paso`, más `e2e-rapido`.
- **`make e2e-completo`** solo en `cierre-epica`: todo lo construido hasta ahora, de punta a punta.
- **Nunca se debilita la CI:**
  - nada de `|| true`, prefijos `-`, `-i` o `-k` de make, ni `continue-on-error`;
  - nada de tests saltados sin una entrada en `FALLOS.md`.
- **Repos públicos:** `main` protegida con el check obligatorio `check`, 0 aprobaciones y `enforce_admins`.
- **La frontera de seguridad es esa protección de `main` en GitHub**, no los hooks locales (ADR 0000).
- **Hooks `guard-git` y `pre-push`:** son una red contra errores accidentales, best-effort, y **no una frontera de seguridad**. `guard-git` intenta parar antes de ejecutarse los push con force, no-verify, refspec `+` o hacia `main`, y los push desde `main`; `pre-push` rechaza `main`. Sus límites conocidos están en `docs/adr/0000-hooks-locales-red-no-frontera.md` y no se persiguen más variantes (L-005).
- **Repo privado en plan gratuito:** hook `pre-push` que rechaza `main`. Donde GitHub no protege la rama, no hay frontera: solo la red.
