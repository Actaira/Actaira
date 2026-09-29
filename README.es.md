# Actaira

Actaira se está construyendo para decir qué puede hacer cada agente de IA de un repositorio, dejar decidir qué se le permite y dar la prueba.

**Estado: en desarrollo.** Hoy la línea de comandos solo imprime su versión. Este README solo describe lo que ya funciona; el plan está en [docs/PLAN.md](docs/PLAN.md).

[Read in English](README.md)

## Compilar desde el código

Hace falta Go 1.27.1 o posterior.

```sh
go build -o actaira ./cmd/actaira
./actaira version
```

`./actaira help` lista los comandos. Los códigos de salida son 0 cuando el comando ha funcionado, 2 cuando los argumentos no son válidos y 3 cuando algo ha fallado dentro de actaira, como escribir su salida.

## Seguridad

Para avisar de una vulnerabilidad, mira [SECURITY.md](SECURITY.md).

## Licencia

Apache License 2.0: mira [LICENSE](LICENSE).
