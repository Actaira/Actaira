package repotest

import (
	"crypto/sha256"
	"encoding/hex"
	"go/parser"
	"go/token"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"testing"

	"github.com/actaira/actaira/internal/cli"
)

const module = "github.com/actaira/actaira"

// root is the repository root: go test runs a package's tests in its directory.
var root = filepath.Join("..", "..")

// pkg/ is public API that actaira-cloud imports; Go forbids importing
// internal/ from another module, so no package under pkg/ may import it
// (docs/epicas/E1.md, step 1.1).
func TestPkgDoesNotImportInternal(t *testing.T) {
	packages := map[string]bool{}
	err := filepath.WalkDir(filepath.Join(root, "pkg"), func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() && d.Name() == "testdata" {
			return filepath.SkipDir
		}
		if d.IsDir() || !strings.HasSuffix(path, ".go") || strings.HasSuffix(path, "_test.go") {
			return nil
		}
		rel, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		packages[filepath.ToSlash(filepath.Dir(rel))] = true
		f, err := parser.ParseFile(token.NewFileSet(), path, nil, parser.ImportsOnly)
		if err != nil {
			return err
		}
		for _, imp := range f.Imports {
			p, err := strconv.Unquote(imp.Path.Value)
			if err != nil {
				return err
			}
			if p == module+"/internal" || strings.HasPrefix(p, module+"/internal/") {
				t.Errorf("%s imports %s: pkg/ cannot depend on internal/", filepath.ToSlash(rel), p)
			}
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{"pkg/model", "pkg/extract", "pkg/lock"} {
		if !packages[want] {
			t.Errorf("no Go files in %s", want)
		}
	}
}

// LICENSE is the Apache License 2.0 exactly as published by the ASF
// (https://www.apache.org/licenses/LICENSE-2.0.txt).
func TestLicenseIsTheOfficialApache2(t *testing.T) {
	const want = "cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30"
	data, err := os.ReadFile(filepath.Join(root, "LICENSE"))
	if err != nil {
		t.Fatal(err)
	}
	sum := sha256.Sum256(data)
	if got := hex.EncodeToString(sum[:]); got != want {
		t.Fatalf("sha256(LICENSE) = %s, want %s (the official Apache-2.0 text)", got, want)
	}
}

var (
	codeInMarkdown = regexp.MustCompile("(?s)```.*?```|`[^`\n]+`")
	commandInCode  = regexp.MustCompile(`(?:^|[\s/])actaira[ \t]+([a-z][a-z0-9-]*)`)
)

// The READMEs only say what already works (docs/epicas/E1.md, step 1.1): every
// "actaira <command>" they show in code is a command the CLI implements.
func TestReadmesOnlyNameImplementedCommands(t *testing.T) {
	implemented := cli.Commands()
	for _, name := range []string{"README.md", "README.es.md"} {
		data, err := os.ReadFile(filepath.Join(root, name))
		if err != nil {
			t.Fatal(err)
		}
		found := 0
		for _, code := range codeInMarkdown.FindAllString(string(data), -1) {
			for _, m := range commandInCode.FindAllStringSubmatch(code, -1) {
				found++
				if !slices.Contains(implemented, m[1]) {
					t.Errorf("%s shows \"actaira %s\", which the CLI does not implement (it has %v)", name, m[1], implemented)
				}
			}
		}
		if found == 0 {
			t.Errorf("%s shows no actaira command: nothing to check", name)
		}
	}
}

// SECURITY.md sends reports to the project contact address, the one set in
// config/contact.env (CLAUDE.md, rule 4), so both change together.
func TestSecurityPolicyGivesTheProjectContact(t *testing.T) {
	config, err := os.ReadFile(filepath.Join(root, "config", "contact.env"))
	if err != nil {
		t.Fatal(err)
	}
	contact := ""
	for _, line := range strings.Split(string(config), "\n") {
		if v, ok := strings.CutPrefix(line, "ACTAIRA_CONTACT_EMAIL="); ok {
			contact = v
		}
	}
	if contact == "" {
		t.Fatal("config/contact.env does not set ACTAIRA_CONTACT_EMAIL")
	}
	policy, err := os.ReadFile(filepath.Join(root, "SECURITY.md"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(policy), contact) {
		t.Fatal("SECURITY.md does not give the project contact address of config/contact.env")
	}
}
