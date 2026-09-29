// Package cli is the command line of actaira: it parses the arguments, runs
// a command and returns the exit code. Only cmd/actaira uses it.
package cli

import (
	"fmt"
	"io"
	"strings"

	"github.com/actaira/actaira/internal/version"
)

// Exit codes of the actaira command (docs/epicas/E1.md, step 1.5).
const (
	ExitOK       = 0 // the command did what was asked
	ExitDiff     = 1 // lock --check found differences
	ExitUsage    = 2 // the arguments are wrong
	ExitInternal = 3 // something failed inside actaira
)

type command struct {
	name    string
	summary string
	run     func(args []string, stdout, stderr io.Writer) int
}

// commands, in the order the usage lists them. Filled in init because help
// prints this same table.
var commands []command

func init() {
	commands = []command{
		{name: "version", summary: "print the version of actaira", run: runVersion},
		{name: "help", summary: "print this help", run: runHelp},
	}
}

// Commands returns the names of the commands that Run implements.
func Commands() []string {
	names := make([]string, len(commands))
	for i, c := range commands {
		names[i] = c.name
	}
	return names
}

// Run runs the command named by args[0] and returns its exit code.
func Run(args []string, stdout, stderr io.Writer) int {
	if len(args) == 0 {
		writeUsage(stderr)
		return ExitUsage
	}
	switch args[0] {
	case "-h", "--help":
		return runHelp(args[1:], stdout, stderr)
	}
	for _, c := range commands {
		if c.name == args[0] {
			return c.run(args[1:], stdout, stderr)
		}
	}
	say(stderr, "actaira: unknown command %q\n", args[0])
	writeUsage(stderr)
	return ExitUsage
}

func runVersion(args []string, stdout, stderr io.Writer) int {
	if len(args) > 0 {
		say(stderr, "actaira: %q takes no arguments\n", "version")
		return ExitUsage
	}
	if _, err := fmt.Fprintf(stdout, "actaira %s\n", version.Version); err != nil {
		say(stderr, "actaira: writing the version: %v\n", err)
		return ExitInternal
	}
	return ExitOK
}

func runHelp(_ []string, stdout, _ io.Writer) int {
	writeUsage(stdout)
	return ExitOK
}

func writeUsage(w io.Writer) {
	var b strings.Builder
	b.WriteString("usage: actaira <command>\n\ncommands:\n")
	for _, c := range commands {
		fmt.Fprintf(&b, "  %-8s %s\n", c.name, c.summary)
	}
	say(w, "%s", b.String())
}

// say writes a message for the person running actaira. If that write fails
// the terminal is gone and there is no one left to tell, so the error is
// dropped on purpose.
func say(w io.Writer, format string, args ...any) {
	_, _ = fmt.Fprintf(w, format, args...)
}
