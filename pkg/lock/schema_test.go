package lock

import (
	"bytes"
	"encoding/json"
	"os"
	"strings"
	"testing"

	"github.com/santhosh-tekuri/jsonschema/v6"

	"github.com/actaira/actaira/pkg/intent"
)

const (
	acmID  = "https://actaira.com/schemas/acm.v0.json"
	lockID = "https://actaira.com/schemas/actaira.lock.v1.json"
)

// schemas compiles the two published JSON Schemas from the repository, with no
// network: the 2020-12 metaschema is embedded in the library, and both files
// are registered under their $id (verificador-apis, E1 step 1.3).
func schemas(t *testing.T) (acm, lock *jsonschema.Schema) {
	t.Helper()
	c := jsonschema.NewCompiler()
	for id, path := range map[string]string{acmID: "../../schemas/acm.v0.json", lockID: "../../schemas/actaira.lock.v1.json"} {
		f, err := os.Open(path)
		if err != nil {
			t.Fatalf("opening %s: %v", path, err)
		}
		doc, err := jsonschema.UnmarshalJSON(f)
		if cerr := f.Close(); cerr != nil {
			t.Fatalf("closing %s: %v", path, cerr)
		}
		if err != nil {
			t.Fatalf("reading %s: %v", path, err)
		}
		if err := c.AddResource(id, doc); err != nil {
			t.Fatalf("adding %s: %v", path, err)
		}
	}
	var err error
	if acm, err = c.Compile(acmID); err != nil {
		t.Fatalf("compiling the ACM schema: %v", err)
	}
	if lock, err = c.Compile(lockID); err != nil {
		t.Fatalf("compiling the lockfile schema: %v", err)
	}
	return acm, lock
}

func schemaAccepts(t *testing.T, s *jsonschema.Schema, doc string) bool {
	t.Helper()
	v, err := jsonschema.UnmarshalJSON(strings.NewReader(doc))
	if err != nil {
		t.Fatalf("the fixture is not JSON: %v\n%s", err, doc)
	}
	return s.Validate(v) == nil
}

// The ACM schema and intent.Parse give the same answer on every fixture,
// except the rules a schema cannot express, listed one by one (L-012:
// a check that mirrors another tool is tested against that tool).
func TestACMSchemaAndGoAgree(t *testing.T) {
	acm, _ := schemas(t)
	const valid = `{"acm_version": 0, "contracts": [{"agent": "0123456789abcdef", "status": "accepted",
	  "accepted_by": "@ana", "accepted_at": "2026-10-01", "owner": "@ana", "expires": "2027-04-01",
	  "allow": ["customer.read", "money.refund"], "deny": ["customer.delete"],
	  "limits": [{"capability": "money.refund", "per_operation": {"amount": 50000, "currency": "EUR"}},
	             {"capability": "money.refund", "per_period": {"period": "month", "count": 100}}],
	  "egress": ["api.stripe.com", "*.zendesk.com"]}]}`
	draft := strings.Replace(valid, `"status": "accepted",
	  "accepted_by": "@ana", "accepted_at": "2026-10-01",`, `"status": "draft", "confidence": "inferred",`, 1)
	cases := []struct {
		name         string
		doc          string
		schema, goOK bool
		why          string // why schema and Go differ, when they do
	}{
		{"valid accepted", valid, true, true, ""},
		{"valid draft", draft, true, true, ""},
		{"no contracts", `{"acm_version": 0, "contracts": []}`, true, true, ""},
		{"other acm_version", strings.Replace(valid, `"acm_version": 0`, `"acm_version": 1`, 1), false, false, ""},
		{"unknown field", strings.Replace(valid, `"owner": "@ana",`, `"owner": "@ana", "ownr": "x",`, 1), false, false, ""},
		{"decimal amount", strings.Replace(valid, `"amount": 50000`, `"amount": 500.5`, 1), false, false, ""},
		{"wildcard capability", strings.Replace(valid, `"customer.read"`, `"customer.*"`, 1), false, false, ""},
		{"accepted without who", strings.Replace(valid, `"accepted_by": "@ana", `, ``, 1), false, false, ""},
		{"accepted with confidence", strings.Replace(valid, `"status": "accepted",`, `"status": "accepted", "confidence": "inferred",`, 1), false, false, ""},
		{"draft without confidence", strings.Replace(draft, ` "confidence": "inferred",`, ``, 1), false, false, ""},
		{"draft accepted by someone", strings.Replace(draft, `"confidence": "inferred",`, `"confidence": "inferred", "accepted_by": "@ana",`, 1), false, false, ""},
		{"egress with scheme", strings.Replace(valid, `"api.stripe.com"`, `"https://api.stripe.com"`, 1), false, false, ""},
		{"period without amount or count", strings.Replace(valid, `"period": "month", "count": 100`, `"period": "month"`, 1), false, false, ""},
		{"limit without bound", strings.Replace(valid, `{"capability": "money.refund", "per_operation": {"amount": 50000, "currency": "EUR"}},`, `{"capability": "money.refund"},`, 1), false, false, ""},
		{"bad date", strings.Replace(valid, `"expires": "2027-04-01"`, `"expires": "2027-4-1"`, 1), false, false, ""},
		{"exponent amount", strings.Replace(valid, `"amount": 50000`, `"amount": 5e4`, 1), true, false, "JSON Schema reads 5e4 as the integer 50000; actaira wants the digits of ADR 0002"},
		{"zero fraction amount", strings.Replace(valid, `"amount": 50000`, `"amount": 50000.0`, 1), true, false, "JSON Schema reads 50000.0 as an integer; actaira wants the digits of ADR 0002"},
		{"capability allowed and denied", strings.Replace(valid, `"deny": ["customer.delete"]`, `"deny": ["customer.delete", "money.refund"]`, 1), true, false, "a schema cannot compare two lists"},
		{"two contracts for one agent", strings.Replace(valid, `}]}`, `}, {"agent": "0123456789abcdef", "status": "draft", "confidence": "inferred", "owner": "@b", "expires": "2027-01-01"}]}`, 1), true, false, "a schema cannot compare a field across items"},
		{"not nfc owner", strings.Replace(valid, `"owner": "@ana"`, "\"owner\": \"@aná\"", 1), true, true, ""},
		{"null list", strings.Replace(valid, `"deny": ["customer.delete"]`, `"deny": null`, 1), false, false, ""},
		{"empty confidence", strings.Replace(valid, `"status": "accepted",`, `"status": "accepted", "confidence": "",`, 1), false, false, ""},
		{"amount as a string", strings.Replace(valid, `"amount": 50000`, `"amount": "50000"`, 1), false, false, ""},
		{"miscased key", strings.Replace(valid, `"deny":`, `"Deny":`, 1), false, false, ""},
		{"duplicate key", strings.Replace(valid, `"deny": ["customer.delete"],`, `"deny": ["customer.delete"], "deny": [],`, 1), true, false, "a JSON Schema validator reads the decoded value, where the last duplicate key wins (F-0030)"},
		{"invalid utf-8", strings.Replace(valid, `"owner": "@ana"`, "\"owner\": \"@an\xff\"", 1), true, false, "the validator replaces invalid UTF-8 before validating; actaira rejects it (ADR 0002, rule 4)"},
		{"limit on a capability not allowed", strings.Replace(valid, `{"capability": "money.refund", "per_operation"`, `{"capability": "money.refnd", "per_operation"`, 1), true, false, "a schema cannot compare two lists"},
		{"day that does not exist", strings.Replace(valid, `"expires": "2027-04-01"`, `"expires": "2027-02-31"`, 1), true, false, "the schema only checks the form of a day; actaira checks that it exists"},
		{"acm_version written 0.0", strings.Replace(valid, `"acm_version": 0`, `"acm_version": 0.0`, 1), true, false, "JSON Schema reads 0.0 as 0; actaira wants the digits of ADR 0002"},
		{"two per_operation limits", strings.Replace(valid, `{"capability": "money.refund", "per_operation": {"amount": 50000, "currency": "EUR"}},`, `{"capability": "money.refund", "per_operation": {"amount": 50000, "currency": "EUR"}}, {"capability": "money.refund", "per_operation": {"amount": 1, "currency": "EUR"}},`, 1), true, false, "a schema cannot compare a field across items"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := schemaAccepts(t, acm, c.doc); got != c.schema {
				t.Fatalf("JSON Schema accepts = %v, want %v", got, c.schema)
			}
			_, err := intent.Parse([]byte(c.doc))
			if got := err == nil; got != c.goOK {
				t.Fatalf("intent.Parse accepts = %v, want %v (err: %v)", got, c.goOK, err)
			}
			if (c.schema != c.goOK) != (c.why != "") {
				t.Fatalf("the schema and Go differ without a reason written down, or a reason is written for no difference")
			}
		})
	}
}

// The lockfile schema and Decode give the same answer, except the canonical
// form, which a schema cannot express.
func TestLockSchemaAndGoAgree(t *testing.T) {
	_, lock := schemas(t)
	sample, err := os.ReadFile("testdata/v1/sample.lock")
	if err != nil {
		t.Fatalf("reading the v1 fixture: %v", err)
	}
	var pretty bytes.Buffer
	if err := json.Indent(&pretty, sample, "", "  "); err != nil {
		t.Fatalf("indenting the fixture: %v", err)
	}
	s := string(sample)
	cases := []struct {
		name         string
		doc          string
		schema, goOK bool
		why          string
	}{
		{"v1 sample", s, true, true, ""},
		{"schema_version 2", strings.Replace(s, `"schema_version":1`, `"schema_version":2`, 1), false, false, ""},
		{"unknown field", strings.Replace(s, `{"agents":`, `{"agentz":[],"agents":`, 1), false, false, ""},
		{"no coverage", strings.Replace(strings.Replace(s, `"coverage":`, `"coveragx":`, 1), `"coveragx":`, `"coveragx":`, 1), false, false, ""},
		{"stored effect", strings.Replace(s, `"effect":"unknown"`, `"effect":"write"`, 1), false, false, ""},
		{"axis with value and no source", strings.Replace(s, `{"axis":"detected","value":2}`, `{"axis":"detected","no_source":"x","value":2}`, 1), false, false, ""},
		{"not observed without reason", strings.Replace(s, `"reason":"no_runner_config",`, ``, 1), false, false, ""},
		{"bad capability in intent", strings.Replace(s, `"customer.read"`, `"customer.*"`, 1), false, false, ""},
		{"bad id", upperFirstID(s), false, false, ""},
		{"no axes", strings.Replace(s, axesOf(s), `"axes":[]`, 1), false, false, ""},
		{"effective with a value", strings.Replace(s, `{"axis":"effective","no_source":"not_from_repo"}`, `{"axis":"effective","value":0}`, 1), false, false, ""},
		{"detected twice", strings.Replace(s, `{"axis":"detected","value":2},`, `{"axis":"detected","value":2},{"axis":"detected","value":2},`, 1), false, false, ""},
		{"negative value", strings.Replace(s, `{"axis":"detected","value":2}`, `{"axis":"detected","value":-2}`, 1), false, false, ""},
		{"url with a query", strings.Replace(s, `"url":"https://api.example.invalid/mcp"`, `"url":"https://api.example.invalid/mcp?api_key=TEST_SENTINEL_NOT_A_KEY"`, 1), false, false, ""},
		{"url with a user", strings.Replace(s, `"url":"https://api.example.invalid/mcp"`, `"url":"https://u:p@api.example.invalid/mcp"`, 1), false, false, ""},
		{"command with arguments", strings.Replace(s, `"command":"npx"`, `"command":"npx -y @stripe/mcp"`, 1), false, false, ""},
		{"absolute path", strings.Replace(s, `"path":"support/prompts.py"`, `"path":"/home/someone/support/prompts.py"`, 1), true, false, "the schema cannot express a clean relative path; pkg/lock checks it"},
		{"pretty printed", pretty.String(), true, false, "the schema cannot express the canonical form of ADR 0002"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if c.doc == s && c.name != "v1 sample" {
				t.Fatal("the mutation did not change the fixture")
			}
			if got := schemaAccepts(t, lock, c.doc); got != c.schema {
				t.Fatalf("JSON Schema accepts = %v, want %v", got, c.schema)
			}
			_, err := Decode([]byte(c.doc))
			if got := err == nil; got != c.goOK {
				t.Fatalf("Decode accepts = %v, want %v (err: %v)", got, c.goOK, err)
			}
			if (c.schema != c.goOK) != (c.why != "") {
				t.Fatalf("the schema and Go differ without a reason written down, or a reason is written for no difference")
			}
		})
	}
}

// upperFirstID writes the first id of the lockfile in capitals.
func upperFirstID(s string) string {
	i := strings.Index(s, `"id":"`) + len(`"id":"`)
	return s[:i] + strings.ToUpper(s[i:i+16]) + s[i+16:]
}

// axesOf returns the first "axes":[...] of the lockfile.
func axesOf(s string) string {
	i := strings.Index(s, `"axes":[`)
	j := strings.Index(s[i:], "]")
	return s[i : i+j+1]
}
