# Actaira

Actaira is being built to tell what each AI agent in a repository can do, let people decide what it is allowed to do, and give the proof.

**Status: early development.** Today the command line only prints its version. This README only describes what already works; the plan, in Spanish, is in [docs/PLAN.md](docs/PLAN.md).

[Leer en español](README.es.md)

## Build from source

You need Go 1.27.1 or later.

```sh
go build -o actaira ./cmd/actaira
./actaira version
```

`./actaira help` lists the commands. The exit codes are 0 when the command worked, 2 when the arguments are wrong and 3 when something failed inside actaira, such as writing its output.

## Security

To report a vulnerability, see [SECURITY.md](SECURITY.md).

## License

Apache License 2.0: see [LICENSE](LICENSE).
