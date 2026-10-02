---
paths:
  - "docs/adr/**"
  - "docs/estado/**"
---

# Reglas de los ADR y del estado

- Toda cifra o afirmación de tiempo, memoria, tamaño o coste de un ADR o del estado cita el fichero de `evals/results/` que la mide. Ese fichero lleva fecha, commit, entorno y comando (CLAUDE.md, "Todo se mide"). Lo que no está medido se escribe como hipótesis, con lo que haría falta para medirlo, nunca como hecho (F-0025).
- Una afirmación general (lo que acota un límite, cómo escala algo con el tamaño o el tiempo) se mide en todo el rango que cubre. Con un solo punto medido, se escribe el punto y no la regla (F-0026).
- Cuando una medición cambia, el ADR y el estado se ponen al día en el mismo PR: una cifra que el JSON ya no dice es una afirmación falsa.
