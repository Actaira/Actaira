package cli

import (
	"bytes"
	"strings"
	"testing"

	"github.com/actaira/actaira/internal/version"
)

func run(args ...string) (code int, stdout, stderr string) {
	var out, errOut bytes.Buffer
	code = Run(args, &out, &errOut)
	return code, out.String(), errOut.String()
}

// The exit codes are part of the CLI contract (docs/epicas/E1.md, step 1.5).
func TestExitCodesAreTheDocumentedOnes(t *testing.T) {
	got := []int{ExitOK, ExitDiff, ExitUsage, ExitInternal}
	want := []int{0, 1, 2, 3}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("exit codes = %v, want %v", got, want)
		}
	}
}

func TestVersionPrintsTheBuildVersion(t *testing.T) {
	code, out, errOut := run("version")
	if code != ExitOK {
		t.Fatalf("exit code = %d, want %d (stderr %q)", code, ExitOK, errOut)
	}
	if want := "actaira " + version.Version + "\n"; out != want {
		t.Fatalf("stdout = %q, want %q", out, want)
	}
	if errOut != "" {
		t.Fatalf("stderr = %q, want nothing", errOut)
	}
}

func TestVersionRejectsArguments(t *testing.T) {
	code, out, errOut := run("version", "extra")
	if code != ExitUsage {
		t.Fatalf("exit code = %d, want %d", code, ExitUsage)
	}
	if out != "" {
		t.Fatalf("stdout = %q, want nothing", out)
	}
	if !strings.Contains(errOut, `actaira: "version" takes no arguments`) {
		t.Fatalf("stderr = %q, want the reason", errOut)
	}
}

func TestNoCommandPrintsUsageAndIsAUsageError(t *testing.T) {
	code, out, errOut := run()
	if code != ExitUsage {
		t.Fatalf("exit code = %d, want %d", code, ExitUsage)
	}
	if out != "" {
		t.Fatalf("stdout = %q, want nothing", out)
	}
	if !strings.Contains(errOut, "usage: actaira <command>") {
		t.Fatalf("stderr = %q, want the usage", errOut)
	}
}

func TestUnknownCommandIsAUsageError(t *testing.T) {
	code, out, errOut := run("nada")
	if code != ExitUsage {
		t.Fatalf("exit code = %d, want %d", code, ExitUsage)
	}
	if out != "" {
		t.Fatalf("stdout = %q, want nothing", out)
	}
	for _, want := range []string{`actaira: unknown command "nada"`, "usage: actaira <command>"} {
		if !strings.Contains(errOut, want) {
			t.Fatalf("stderr = %q, want %q", errOut, want)
		}
	}
}

func TestHelpPrintsUsageAndSucceeds(t *testing.T) {
	for _, arg := range []string{"help", "-h", "--help"} {
		code, out, errOut := run(arg)
		if code != ExitOK {
			t.Fatalf("%s: exit code = %d, want %d", arg, code, ExitOK)
		}
		if !strings.Contains(out, "usage: actaira <command>") {
			t.Fatalf("%s: stdout = %q, want the usage", arg, out)
		}
		if errOut != "" {
			t.Fatalf("%s: stderr = %q, want nothing", arg, errOut)
		}
	}
}

// Commands is what the READMEs may name (internal/repotest): every name it
// lists has to be a command that Run implements, and the usage lists them all.
func TestCommandsAreImplementedAndListedInTheUsage(t *testing.T) {
	names := Commands()
	if len(names) == 0 {
		t.Fatal("Commands() is empty")
	}
	_, usage, _ := run("help")
	for _, name := range names {
		if _, _, errOut := run(name); strings.Contains(errOut, "unknown command") {
			t.Errorf("Commands() lists %q, but Run does not implement it", name)
		}
		if !strings.Contains(usage, "\n  "+name+" ") {
			t.Errorf("the usage does not list %q:\n%s", name, usage)
		}
	}
}
