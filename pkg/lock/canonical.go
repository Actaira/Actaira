package lock

import (
	"bytes"
	"fmt"
	"sort"
	"strconv"
	"unicode/utf16"
	"unicode/utf8"

	"golang.org/x/text/unicode/norm"
)

// maxInt is the largest magnitude of an integer in the canonical JSON: what a
// double represents without loss (ADR 0002, rule 3).
const maxInt = 1<<53 - 1

// Marshal writes v in the canonical JSON of ADR 0002, a strict subset of JCS
// (RFC 8785): object keys sorted by UTF-16 code units, no whitespace, integers
// only, and strings in valid UTF-8 and NFC with the escapes of JCS. v is a tree
// of nil, bool, string, int, int64, []any and map[string]any. Anything outside
// the subset is an error that names its path ($.a[0].b); nothing is rounded or
// changed in silence.
func Marshal(v any) ([]byte, error) {
	var b bytes.Buffer
	if err := write(&b, v, "$"); err != nil {
		return nil, err
	}
	return b.Bytes(), nil
}

func write(b *bytes.Buffer, v any, path string) error {
	switch x := v.(type) {
	case nil:
		b.WriteString("null")
	case bool:
		if x {
			b.WriteString("true")
		} else {
			b.WriteString("false")
		}
	case int:
		return writeInt(b, int64(x), path)
	case int64:
		return writeInt(b, x, path)
	case string:
		return writeString(b, x, path)
	case []any:
		b.WriteByte('[')
		for i, e := range x {
			if i > 0 {
				b.WriteByte(',')
			}
			if err := write(b, e, path+"["+strconv.Itoa(i)+"]"); err != nil {
				return err
			}
		}
		b.WriteByte(']')
	case map[string]any:
		keys := make([]string, 0, len(x))
		for k := range x {
			keys = append(keys, k)
		}
		sort.Slice(keys, func(i, j int) bool { return lessUTF16(keys[i], keys[j]) })
		b.WriteByte('{')
		for i, k := range keys {
			if i > 0 {
				b.WriteByte(',')
			}
			if err := writeString(b, k, path+" (key)"); err != nil {
				return err
			}
			b.WriteByte(':')
			if err := write(b, x[k], path+"."+k); err != nil {
				return err
			}
		}
		b.WriteByte('}')
	case float32, float64:
		return fmt.Errorf("canonical JSON: %s: float %v; only integers are allowed (ADR 0002)", path, x)
	default:
		return fmt.Errorf("canonical JSON: %s: unsupported type %T", path, v)
	}
	return nil
}

func writeInt(b *bytes.Buffer, n int64, path string) error {
	if n > maxInt || n < -maxInt {
		return fmt.Errorf("canonical JSON: %s: integer %d out of range (±%d)", path, n, int64(maxInt))
	}
	b.WriteString(strconv.FormatInt(n, 10))
	return nil
}

// writeString writes s with the escapes of RFC 8785, section 3.2.2.2: quote
// and backslash escaped, controls as \b \t \n \f \r or \u00xx in lowercase,
// everything else as it is (also <, >, &, U+2028 and U+2029).
func writeString(b *bytes.Buffer, s, path string) error {
	if !utf8.ValidString(s) {
		return fmt.Errorf("canonical JSON: %s: string is not valid UTF-8", path)
	}
	if !norm.NFC.IsNormalString(s) {
		return fmt.Errorf("canonical JSON: %s: string is not in Unicode NFC", path)
	}
	const hex = "0123456789abcdef"
	b.WriteByte('"')
	for _, r := range s {
		switch r {
		case '"':
			b.WriteString(`\"`)
		case '\\':
			b.WriteString(`\\`)
		case '\b':
			b.WriteString(`\b`)
		case '\t':
			b.WriteString(`\t`)
		case '\n':
			b.WriteString(`\n`)
		case '\f':
			b.WriteString(`\f`)
		case '\r':
			b.WriteString(`\r`)
		default:
			if r < 0x20 {
				b.WriteString(`\u00`)
				b.WriteByte(hex[r>>4])
				b.WriteByte(hex[r&0xf])
			} else {
				b.WriteRune(r)
			}
		}
	}
	b.WriteByte('"')
	return nil
}

// lessUTF16 orders object keys by their UTF-16 code units (RFC 8785, section
// 3.2.3), which is not the order of their UTF-8 bytes above U+FFFF.
func lessUTF16(a, b string) bool {
	ua, ub := utf16.Encode([]rune(a)), utf16.Encode([]rune(b))
	for i := 0; i < len(ua) && i < len(ub); i++ {
		if ua[i] != ub[i] {
			return ua[i] < ub[i]
		}
	}
	return len(ua) < len(ub)
}
