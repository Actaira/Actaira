package treesitter

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"
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
			tree, err := Parse(context.Background(), tc.lang, []byte(tc.src))
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
	tree, err := Parse(context.Background(), TypeScript, []byte("const a = <div className=\"x\">hi</div>;\n"))
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
		tree, err := Parse(context.Background(), lang, []byte("def (:\n  ]]] const = ;\n"))
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
	_, err := Parse(context.Background(), Language(99), []byte("x"))
	if err == nil || !strings.Contains(err.Error(), "unknown language") {
		t.Fatalf("Parse with an unknown language: err = %v, want an unknown language error", err)
	}
}

func TestCloseTwiceIsSafe(t *testing.T) {
	tree, err := Parse(context.Background(), Python, []byte("x = 1\n"))
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	tree.Close()
	tree.Close()
}

// A hostile file costs seconds and a GB of memory to parse (review round 1 of
// step 1.2a: 1 MB of "a<" in TypeScript). The caller's deadline stops it, and
// the error says why, so the extractors can record it as unresolved.
func TestADeadlineStopsAHostileParse(t *testing.T) {
	src := []byte(strings.Repeat("a<", 1<<19))
	ctx, cancel := context.WithTimeout(context.Background(), 50*time.Millisecond)
	defer cancel()
	start := time.Now()
	tree, err := Parse(ctx, TypeScript, src)
	if err == nil {
		tree.Close()
		t.Fatal("a 1 MB hostile file was parsed within 50 ms: the deadline was not used")
	}
	if !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("err = %v, want one that wraps context.DeadlineExceeded", err)
	}
	if took := time.Since(start); took > time.Second {
		t.Fatalf("the parse stopped %v after starting, want well under a second", took)
	}
}

func TestACanceledContextParsesNothing(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := Parse(ctx, Python, []byte("x = 1\n")); !errors.Is(err, context.Canceled) {
		t.Fatalf("err = %v, want one that wraps context.Canceled", err)
	}
}
