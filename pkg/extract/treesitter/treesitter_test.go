package treesitter

import (
	"testing"
)

func TestParsesEachLanguage(t *testing.T) {
	tests := []struct {
		name string
		lang Language
		src  string
		root string
	}{
		{"python", Python, "def f(x):\n    return x + 1\n", "module"},
		{"typescript", TypeScript, "const x: number = 1;\nexport function f(a: string): string { return a; }\n", "program"},
		{"tsx", TSX, "const a = <div className=\"x\">hi</div>;\n", "program"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			tree, err := Parse(tc.lang, []byte(tc.src))
			if err != nil {
				t.Fatalf("Parse: %v", err)
			}
			defer tree.Close()
			if got := tree.RootKind(); got != tc.root {
				t.Errorf("root kind = %q, want %q", got, tc.root)
			}
			if tree.HasError() {
				t.Errorf("valid %s parsed with errors", tc.name)
			}
		})
	}
}

// TSX needs its own grammar: the TypeScript one reads JSX as an error. The
// extractors pick the grammar by extension (.ts or .tsx).
func TestTSXIsNotTypeScript(t *testing.T) {
	tree, err := Parse(TypeScript, []byte("const a = <div className=\"x\">hi</div>;\n"))
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	defer tree.Close()
	if !tree.HasError() {
		t.Fatal("JSX parsed without errors by the TypeScript grammar: TSX and TypeScript are the same grammar")
	}
}

// Broken code is data from an analysed repo, never a reason to panic: the
// tree comes back with its errors marked (ERROR and MISSING nodes).
func TestBrokenSyntaxIsATreeWithErrors(t *testing.T) {
	for _, lang := range []Language{Python, TypeScript, TSX} {
		tree, err := Parse(lang, []byte("def (:\n  ]]] const = ;\n"))
		if err != nil {
			t.Fatalf("%v: Parse: %v", lang, err)
		}
		if !tree.HasError() {
			t.Errorf("%v: broken code parsed without errors", lang)
		}
		tree.Close()
	}
}

func TestUnknownLanguageIsAnError(t *testing.T) {
	if _, err := Parse(Language(99), []byte("x")); err == nil {
		t.Fatal("Parse with an unknown language returned no error")
	}
}

func TestCloseTwiceIsSafe(t *testing.T) {
	tree, err := Parse(Python, []byte("x = 1\n"))
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	tree.Close()
	tree.Close()
}
