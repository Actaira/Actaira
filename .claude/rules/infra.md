---
paths:
  - "infra/**"
  - ".github/workflows/**"
---

# Reglas de infraestructura y CI

- Antes de aplicar Bicep: `az deployment sub what-if`, y la salida se pega en el PR.
- Nunca se crean ni se borran recursos de Azure fuera de `infra/deploy.sh` y `infra/destroy.sh`. `az group delete` está prohibido en `settings.json`.
- Réplicas mínimas a 0, `maxReplicas` bajo y tope diario de Log Analytics: un cambio que los suba exige un ADR con el coste calculado.
- Acciones de GitHub fijadas por SHA. Permisos mínimos por job (`permissions:` explícito en cada workflow).
- Nada de secretos en workflows: OIDC hacia Azure y Key Vault para lo demás.
- Todo lo que cuesta dinero se comprueba contra el presupuesto antes de desplegar.
