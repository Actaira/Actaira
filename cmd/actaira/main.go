// Command actaira tells what each AI agent in a repository can do. The
// commands live in internal/cli; this file only wires them to the process.
package main

import (
	"os"

	"github.com/actaira/actaira/internal/cli"
)

func main() {
	os.Exit(cli.Run(os.Args[1:], os.Stdout, os.Stderr))
}
