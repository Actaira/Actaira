---
paths:
  - "**/*_test.go"
  - "scripts/harness/tests/**"
  - "evals/**"
---

# Reglas de tests

- Un test nuevo o corregido se da por bueno solo cuando se ha visto en rojo con la corrección quitada (mutación del código que dice cubrir). La salida en rojo y en verde va al PR (L-002, F-0005).
- Un test compara con el valor exacto que protege, no con algo que casualmente no aparece: rutas, huellas y códigos de salida exactos.
- Un test que espera un fallo comprueba también el motivo (mensaje o hallazgo), para no pasar por un error de otro tipo.
- Los fixtures nunca parecen credenciales reales: centinelas como `ACTAIRA_TEST_SENTINEL_123456` con una regla propia.
- Un script que genera evidencia (mutaciones, ejecuciones reales) escribe sus temporales en `mktemp -d`, nunca junto a sí mismo ni en el repo, y valida su propio resultado (rojo con la mutación, verde sin ella) antes de guardarlo; si algo no cuadra, sale con error (F-0008).
- Un test de un fichero que define una comprobación obligatoria (un workflow, los prerrequisitos de `check`) compara su contenido exacto: cualquier línea de más (un `if:`, un paso, un job) lo pone en rojo (L-006, F-0014).
