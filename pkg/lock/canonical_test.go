package lock

import (
	"encoding/json/jsontext"
	"strings"
	"testing"
)

// Fixed vectors of the canonical JSON of ADR 0002: the strict subset of JCS
// (RFC 8785) that actaira.lock uses.
func TestCanonicalVectors(t *testing.T) {
	cases := []struct {
		name string
		in   any
		want string
	}{
		{"empty object", map[string]any{}, `{}`},
		{"empty array", []any{}, `[]`},
		{"null true false", []any{nil, true, false}, `[null,true,false]`},
		{"integers at the limits", []any{0, int64(-1), int64(1<<53 - 1), int64(-(1<<53 - 1))}, `[0,-1,9007199254740991,-9007199254740991]`},
		{"no spaces and sorted keys", map[string]any{"b": 1, "a": []any{"x", "y"}}, `{"a":["x","y"],"b":1}`},
		{"nested objects sorted", map[string]any{"z": map[string]any{"b": true, "a": nil}}, `{"z":{"a":null,"b":true}}`},
		// RFC 8785, section 3.2.3: keys sort by UTF-16 code units. U+1F600 is
		// the surrogate pair D83D DE00, which sorts before U+FF21 in UTF-16
		// and after it in UTF-8 bytes (F0 9F... against EF BC A1). U+FF21 is
		// in NFC; U+FB33, the usual example, is not.
		{"utf-16 key order", map[string]any{"\uFF21": 2, "\U0001F600": 1}, "{\"\U0001F600\":1,\"\uFF21\":2}"},
		{"escapes of RFC 8785 3.2.2.2", "\"\\\b\t\n\f\r\u0001\u001f", `"\"\\\b\t\n\f\r\u0001\u001f"`},
		{"no html escape", "<>&", `"<>&"`},
		{"line separators as they are", "\u2028\u2029", "\"\u2028\u2029\""},
		{"delete and non-ascii as they are", "\u007f é €", "\"\u007f é €\""},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got, err := Marshal(c.in)
			if err != nil {
				t.Fatalf("Marshal: %v", err)
			}
			if string(got) != c.want {
				t.Fatalf("Marshal = %s, want %s", got, c.want)
			}
		})
	}
}

// The vectors of the JCS reference repository that fall in the subset
// (https://github.com/cyberphone/json-canonicalization/tree/master/testdata,
// Apache-2.0, cited by RFC 8785, appendix I): arrays, french and structures
// (whose input writes 56.0; here the tree holds the integer 56), and the 0 of
// RFC 8785, appendix B.
func TestCanonicalReferenceVectorsInTheSubset(t *testing.T) {
	cases := []struct {
		name string
		in   any
		want string
	}{
		{"arrays", []any{56, map[string]any{"d": true, "10": nil, "1": []any{}}}, `[56,{"1":[],"10":null,"d":true}]`},
		{"french", map[string]any{
			"peach": "This sorting order",
			"péché": "is wrong according to French",
			"pêche": "but canonicalization MUST",
			"sin":   "ignore locale",
		}, `{"peach":"This sorting order","péché":"is wrong according to French","pêche":"but canonicalization MUST","sin":"ignore locale"}`},
		{"structures", map[string]any{
			"1":   map[string]any{"f": map[string]any{"f": "hi", "F": 5}, "\n": 56},
			"10":  map[string]any{},
			"":    "empty",
			"a":   map[string]any{},
			"111": []any{map[string]any{"e": "yes", "E": "no"}},
			"A":   map[string]any{},
		}, `{"":"empty","1":{"\n":56,"f":{"F":5,"f":"hi"}},"10":{},"111":[{"E":"no","e":"yes"}],"A":{},"a":{}}`},
		{"rfc 8785 appendix B zero", int64(0), `0`},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got, err := Marshal(c.in)
			if err != nil {
				t.Fatalf("Marshal: %v", err)
			}
			if string(got) != c.want {
				t.Fatalf("Marshal = %s, want %s", got, c.want)
			}
		})
	}
}

// Every output is byte for byte what the JCS of the standard library gives,
// an independent oracle (ADR 0002).
func TestCanonicalMatchesTheStandardLibraryJCS(t *testing.T) {
	inputs := []any{
		map[string]any{
			"z":    []any{3, "é", map[string]any{"\U0001F600": nil, "\uFF21": true}},
			"a":    "line\u2028sep <tag> \"q\" \\ \t",
			"€":    int64(-(1<<53 - 1)),
			"\x01": "control in a key",
		},
		[]any{map[string]any{}, []any{}, "", 0},
	}
	for i, in := range inputs {
		got, err := Marshal(in)
		if err != nil {
			t.Fatalf("input %d: Marshal: %v", i, err)
		}
		v := jsontext.Value(append([]byte(nil), got...))
		if err := v.Canonicalize(); err != nil {
			t.Fatalf("input %d: Canonicalize: %v", i, err)
		}
		if string(v) != string(got) {
			t.Fatalf("input %d:\nMarshal = %s\nJCS     = %s", i, got, v)
		}
	}
}

// What is outside the subset is an error that names the field, never a value
// rounded or changed in silence.
func TestCanonicalRejectsWhatIsOutsideTheSubset(t *testing.T) {
	cases := []struct {
		name string
		in   any
		want []string
	}{
		{"float", map[string]any{"x": 1.5}, []string{"$.x", "float"}},
		{"integer out of range", []any{int64(1 << 53)}, []string{"$[0]", "range"}},
		{"negative integer out of range", []any{int64(-(1 << 53))}, []string{"$[0]", "range"}},
		{"invalid utf-8", map[string]any{"s": "\xff"}, []string{"$.s", "UTF-8"}},
		{"invalid utf-8 inside", map[string]any{"s": "a\xffb"}, []string{"$.s", "UTF-8"}},
		{"encoded surrogate half", map[string]any{"s": "\xed\xa0\x80"}, []string{"$.s", "UTF-8"}},
		{"not nfc", map[string]any{"s": "e\u0301"}, []string{"$.s", "NFC"}},
		{"key not nfc", map[string]any{"e\u0301": 1}, []string{"NFC"}},
		// Out of the subset in the reference repository: unicode ("A" and a
		// combining ring, kept as is by JCS) and the U+FB33 key of weird and
		// of the ordering example of RFC 8785, section 3.2.3 (a composition
		// exclusion, not NFC).
		{"reference unicode", map[string]any{"Unnormalized Unicode": "A\u030a"}, []string{"NFC"}},
		{"reference weird key", map[string]any{"\ufb33": "Hebrew Letter Dalet With Dagesh"}, []string{"NFC"}},
		{"unsupported type", []any{struct{}{}}, []string{"$[0]", "type"}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			_, err := Marshal(c.in)
			if err == nil {
				t.Fatal("Marshal accepted a value outside the subset")
			}
			for _, w := range c.want {
				if !strings.Contains(err.Error(), w) {
					t.Fatalf("error %q does not say %q", err, w)
				}
			}
		})
	}
}
