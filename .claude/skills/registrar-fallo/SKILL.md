---
name: registrar-fallo
description: Registra un fallo con causa raíz y le pone una guardia permanente (test, lint, hook o regla) para que no vuelva a pasar. Úsala con cada test rojo inesperado, bug, hallazgo crítico o alto, o error de despliegue.
---

# Registrar un fallo ($ARGUMENTS)

1. **Siguiente id:** `F-NNNN`, correlativo en `docs/harness/FALLOS.md`.
2. **Síntoma:** la salida real, recortada.
3. **Causa raíz:** pregunta "por qué" hasta llegar a algo que se pueda impedir, no solo el sitio donde falló.
4. **Guardia**, la más barata que impida que se repita:
   - **test** que reproduce el fallo (`test:<ruta>::<Nombre>`), casi siempre;
   - **lint o comprobación** en `scripts/harness/` metida en `make check`, si el fallo es de un patrón;
   - **hook** en `.claude/settings.json`, si el fallo lo provoca una acción de Claude Code;
   - **regla** en `.claude/rules/`, solo si no se puede comprobar de forma automática.
5. **Prueba de la guardia:** ejecútala **sin** la corrección (debe fallar) y **con** la corrección (debe pasar). Pega las dos salidas en el PR.
6. **Escribe la entrada** con el formato de `FALLOS.md`.
7. **Lección:** si el fallo revela una regla general que afecta a más sitios, añade o actualiza una entrada en `docs/harness/LECCIONES.md` y aplícala a los otros sitios en el mismo paso, o déjalos en backlog con su lista.

`make check` ejecuta `scripts/harness/check-fallos.sh`: una entrada sin guardia real pone la CI en rojo.
