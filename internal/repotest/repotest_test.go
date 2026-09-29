package repotest

import (
	"crypto/sha256"
	"encoding/hex"
	"go/parser"
	"go/token"
	"io/fs"
	"os"
	"os/exec"
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

// pkg/ is public API with semantic versioning that actaira-cloud imports. No
// package under pkg/, directly or through another package of this module,
// depends on internal/: a change there would change the public API without a
// version bump, and an internal type in it could not be named by the caller
// (docs/epicas/E1.md, step 1.1). Go itself would allow it, since its rule on
// internal/ only looks at the direct importer.
func TestPkgDoesNotDependOnInternal(t *testing.T) {
	cmd := exec.Command("go", "list", "-deps", "-f", `{{.ImportPath}}`, "./pkg/...")
	cmd.Dir = root
	out, err := cmd.Output()
	if err != nil {
		t.Fatalf("go list -deps ./pkg/...: %v", err)
	}
	for _, p := range strings.Fields(string(out)) {
		if p == module+"/internal" || strings.HasPrefix(p, module+"/internal/") {
			t.Errorf("pkg/ depends on %s: pkg/ cannot depend on internal/", p)
		}
	}
}

// Every package that step 1.1 lays out under pkg/ exists, so the test above
// does not pass on an empty pkg/, and none of them imports internal/ directly.
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
	// Code in Markdown: fenced blocks (``` or ~~~), inline code, and the HTML
	// code and pre elements.
	codeInMarkdown = regexp.MustCompile("(?s)```.*?```|~~~.*?~~~|`[^`\n]+`|<code>.*?</code>|<pre>.*?</pre>")
	// actaira, any options, then the command.
	commandInCode = regexp.MustCompile(`(?:^|[\s/>\x60])actaira(?:[ \t]+-{1,2}[a-z][a-z0-9-]*(?:=\S*)?)*[ \t]+([a-z][a-z0-9-]*)`)
)

// commandsShown returns the actaira commands that a Markdown text shows in code.
func commandsShown(markdown string) []string {
	var names []string
	for _, code := range codeInMarkdown.FindAllString(markdown, -1) {
		for _, m := range commandInCode.FindAllStringSubmatch(code, -1) {
			names = append(names, m[1])
		}
	}
	return names
}

func TestCommandsShownFindsEveryFormOfCode(t *testing.T) {
	markdown := "Run `actaira version`.\n\n```sh\n./actaira discover .\n```\n\n~~~\nactaira lock --check\n~~~\n\n" +
		"<code>actaira policy apply</code> and <pre>actaira --json diff main</pre>, `actaira -v blast x`.\n" +
		"The actaira binary is not code, and neither is github.com/actaira/actaira.\n"
	got := commandsShown(markdown)
	want := []string{"version", "discover", "lock", "policy", "diff", "blast"}
	if !slices.Equal(got, want) {
		t.Fatalf("commandsShown = %v, want %v", got, want)
	}
}

// The READMEs only say what already works (docs/epicas/E1.md, step 1.1): every
// "actaira <command>" they show in code is a command the CLI implements.
func TestReadmesOnlyNameImplementedCommands(t *testing.T) {
	implemented := cli.Commands()
	for _, name := range []string{"README.md", "README.es.md"} {
		data, err := os.ReadFile(filepath.Join(root, name))
		if err != nil {
			t.Fatal(err)
		}
		shown := commandsShown(string(data))
		for _, c := range shown {
			if !slices.Contains(implemented, c) {
				t.Errorf("%s shows \"actaira %s\", which the CLI does not implement (it has %v)", name, c, implemented)
			}
		}
		if len(shown) == 0 {
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

// outsideDotDotDot returns the packages of the module in dir that are built,
// by the code or by its tests, but that ./... leaves out: a directory named
// testdata or starting with _, imported from elsewhere (F-0021).
func outsideDotDotDot(t *testing.T, dir, module string) []string {
	t.Helper()
	list := func(args ...string) []string {
		cmd := exec.Command("go", append([]string{"list", "-f", "{{.ImportPath}}"}, args...)...)
		cmd.Dir = dir
		out, err := cmd.Output()
		if err != nil {
			t.Fatalf("go list %v in %s: %v", args, dir, err)
		}
		return strings.Split(strings.TrimSpace(string(out)), "\n")
	}
	all := map[string]bool{}
	for _, p := range list("./...") {
		all[p] = true
	}
	var outside []string
	for _, p := range list("-deps", "-test", "./...") {
		// Test variants ("p [p.test]") and test mains ("p.test") are not packages.
		if strings.Contains(p, " [") || strings.HasSuffix(p, ".test") {
			continue
		}
		if (p == module || strings.HasPrefix(p, module+"/")) && !all[p] {
			outside = append(outside, p)
		}
	}
	return outside
}

func TestOutsideDotDotDotFindsAPackageOnlyTheTestsImport(t *testing.T) {
	got := outsideDotDotDot(t, filepath.Join("testdata", "testonly"), "example.invalid/testonly")
	want := []string{"example.invalid/testonly/a/testdata/h"}
	if !slices.Equal(got, want) {
		t.Fatalf("outsideDotDotDot = %v, want %v", got, want)
	}
}

// Everything the module builds is in ./..., so go test, go vet, golangci-lint
// and check-skips.sh see it: no ignore directive in go.mod, and no package of
// the module, built by the code or by its tests, that ./... leaves out (a
// directory starting with _ or named testdata, imported from elsewhere;
// review rounds 2 and 3 of step 1.1, F-0021).
func TestEveryPackageOfTheModuleIsInDotDotDot(t *testing.T) {
	mod := exec.Command("go", "mod", "edit", "-json")
	mod.Dir = root
	out, err := mod.Output()
	if err != nil {
		t.Fatalf("go mod edit -json: %v", err)
	}
	if strings.Contains(string(out), `"Ignore"`) {
		t.Errorf("go.mod has an ignore directive: the code it names escapes the checks")
	}
	for _, p := range outsideDotDotDot(t, root, module) {
		t.Errorf("%s is built, by the code or its tests, but ./... leaves it out", p)
	}
}
