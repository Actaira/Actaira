package model

import (
	"regexp"
	"testing"
)

// An id depends only on what names the thing (kind, framework, relative file
// and name), so the same code gives the same id on any machine and run.
func TestIDIsStableAndDependsOnEveryPart(t *testing.T) {
	base := NewID("tool", "openai-agents-python", "support/agent.py", "refund", 0)
	if again := NewID("tool", "openai-agents-python", "support/agent.py", "refund", 0); again != base {
		t.Fatalf("NewID is not stable: %s then %s", base, again)
	}
	if !regexp.MustCompile(`^[0-9a-f]{16}$`).MatchString(string(base)) {
		t.Fatalf("id %q is not 16 lowercase hex characters", base)
	}
	others := map[string]ID{
		"kind":      NewID("agent", "openai-agents-python", "support/agent.py", "refund", 0),
		"framework": NewID("tool", "langgraph-python", "support/agent.py", "refund", 0),
		"file":      NewID("tool", "openai-agents-python", "billing/agent.py", "refund", 0),
		"name":      NewID("tool", "openai-agents-python", "support/agent.py", "refunds", 0),
	}
	for part, id := range others {
		if id == base {
			t.Fatalf("changing the %s does not change the id", part)
		}
	}
}

// Fields are separated without ambiguity: moving characters from one part to
// the next gives another id.
func TestIDSeparatesItsParts(t *testing.T) {
	if NewID("tool", "ab", "c", "d", 0) == NewID("tool", "a", "bc", "d", 0) {
		t.Fatal(`"ab"+"c" and "a"+"bc" give the same id`)
	}
}

// Two definitions with the same name in one file (two Agent(name="test") in a
// test file) get different ids through their ordinal (F-0032).
func TestIDDependsOnTheOrdinal(t *testing.T) {
	first := NewID("agent", "openai-agents-python", "tests/test_x.py", "test", 0)
	second := NewID("agent", "openai-agents-python", "tests/test_x.py", "test", 1)
	if first == second {
		t.Fatal("two definitions with the same name get the same id")
	}
}

// The same name, composed or decomposed, gives the same id (ADR 0002, rule 4).
func TestIDIsTheSameForNFCAndNFD(t *testing.T) {
	nfc := NewID("tool", "langgraph-python", "caf\u00e9.py", "r\u00e9sum\u00e9", 0)
	nfd := NewID("tool", "langgraph-python", "cafe\u0301.py", "re\u0301sume\u0301", 0)
	if nfc != nfd {
		t.Fatalf("NFC %s and NFD %s give different ids", nfc, nfd)
	}
}

func TestConfidenceIsAClosedList(t *testing.T) {
	for _, c := range []Confidence{Declared, Inferred, Conditional, Effective, Observed, Unresolved} {
		if !c.Valid() {
			t.Fatalf("%q is not valid", c)
		}
	}
	for _, c := range []Confidence{"", "verified", "Declared"} {
		if c.Valid() {
			t.Fatalf("%q is valid", c)
		}
	}
}

func TestLocationString(t *testing.T) {
	cases := map[string]Location{
		"support/agent.py:8:12": {File: "support/agent.py", Line: 8, Column: 12},
		"support/agent.py:8":    {File: "support/agent.py", Line: 8},
		"support/prompts.py":    {File: "support/prompts.py"},
	}
	for want, loc := range cases {
		if got := loc.String(); got != want {
			t.Fatalf("Location%+v.String() = %q, want %q", loc, got, want)
		}
	}
}

// A tool is resolved only when both hashes are known (docs/cobertura.md).
func TestToolResolvedNeedsBothHashes(t *testing.T) {
	cases := []struct {
		schema, description string
		want                bool
	}{
		{"sha256:aa", "sha256:bb", true},
		{"sha256:aa", "", false},
		{"", "sha256:bb", false},
		{"", "", false},
	}
	for _, c := range cases {
		tool := Tool{SchemaHash: c.schema, DescriptionHash: c.description}
		if got := tool.Resolved(); got != c.want {
			t.Fatalf("Resolved() with %q and %q = %v, want %v", c.schema, c.description, got, c.want)
		}
	}
}
