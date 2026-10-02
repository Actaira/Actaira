package lock

import (
	"bytes"
	"math/rand/v2"
	"os"
	"strings"
	"testing"

	"github.com/actaira/actaira/pkg/coverage"
	"github.com/actaira/actaira/pkg/intent"
	"github.com/actaira/actaira/pkg/model"
)

// sample is a lockfile with one of everything: two agents with a handoff,
// tools (one unresolved), an MCP server, a skill, a secret reference, the
// coverage computed from them and a contract.
func sample(t *testing.T) Lockfile {
	t.Helper()
	const fw, file = "openai-agents-python", "support/agent.py"
	at := func(line, col int) model.Location { return model.Location{File: file, Line: line, Column: col} }
	support := model.NewID("agent", fw, file, "support")
	billing := model.NewID("agent", fw, file, "billing")
	refund := model.NewID("tool", fw, file, "refund")
	lookup := model.NewID("tool", fw, file, "lookup")
	stripe := model.NewID("mcp_server", fw, file, "stripe")
	key := model.NewID("env_ref", "", "", "STRIPE_API_KEY")
	skill := model.NewID("skill", "agent-skills", "skills/triage/SKILL.md", "triage")
	l := Lockfile{
		SchemaVersion: SchemaVersion,
		Agents: []model.Agent{
			{ID: support, Name: "support", Framework: fw, Source: at(40, 1), Model: &model.Model{Name: "gpt-5"}, Prompt: &model.PromptRef{Hash: "sha256:" + strings.Repeat("a", 64)}, Confidence: model.Declared},
			{ID: billing, Name: "billing", Framework: fw, Source: at(60, 1), Confidence: model.Declared},
		},
		Tools: []model.Tool{
			{ID: refund, Name: "refund", Framework: fw, Source: at(10, 1), SchemaHash: "sha256:" + strings.Repeat("b", 64), DescriptionHash: "sha256:" + strings.Repeat("c", 64), Effect: model.EffectUnknown, Confidence: model.Declared},
			{ID: lookup, Name: "lookup", Framework: fw, Source: at(20, 1), Effect: model.EffectUnknown, Confidence: model.Unresolved},
		},
		MCPServers: []model.MCPServer{
			{ID: stripe, Name: "stripe", Transport: model.TransportStdio, Command: "npx", Package: &model.Package{Ecosystem: "npm", Name: "@stripe/mcp", Version: "0.2.4"}, Pinned: true, ToolsSource: model.ToolsSourceNone, Source: at(15, 5), Confidence: model.Declared},
		},
		Skills: []model.Skill{
			{ID: skill, Name: "triage", Source: model.Location{File: "skills/triage/SKILL.md", Line: 1}, AllowedTools: []string{"Read", "Grep"}, Confidence: model.Declared},
		},
		SecretRefs: []model.SecretRef{{ID: key, Name: "STRIPE_API_KEY", Locations: []model.Location{at(8, 12), at(9, 3)}}},
		Edges: []model.Edge{
			{From: support, To: refund, Kind: model.CanCall, Source: at(41, 9), Confidence: model.Declared},
			{From: support, To: lookup, Kind: model.CanCall, Source: at(41, 17), Confidence: model.Declared},
			{From: support, To: billing, Kind: model.DelegatesTo, Source: at(42, 9), Confidence: model.Declared},
			{From: support, To: stripe, Kind: model.UsesMCPServer, Source: at(43, 9), Confidence: model.Declared},
			{From: refund, To: key, Kind: model.ReferencesEnv, Source: at(8, 12), Confidence: model.Declared},
		},
	}
	cov, err := coverage.Compute(coverage.Input{
		Extractors: []string{"openai-agents-python/1"},
		Agents:     l.Agents, Tools: l.Tools, MCPServers: l.MCPServers, SecretRefs: l.SecretRefs, Edges: l.Edges,
		Skipped: []coverage.Skipped{{Path: "support/prompts.py", Reason: "file_over_1mb"}},
	})
	if err != nil {
		t.Fatalf("coverage.Compute: %v", err)
	}
	l.Coverage = cov
	m, err := intent.Parse([]byte(`{"acm_version": 0, "contracts": [{"agent": "` + string(support) + `", "status": "accepted",
	  "accepted_by": "@ana", "accepted_at": "2026-10-01", "owner": "@ana", "expires": "2027-04-01",
	  "allow": ["money.refund", "customer.read"], "deny": ["customer.delete"],
	  "limits": [{"capability": "money.refund", "per_operation": {"amount": 50000, "currency": "EUR"}}],
	  "egress": ["api.stripe.com"]}]}`))
	if err != nil {
		t.Fatalf("intent.Parse: %v", err)
	}
	l.Intent = &m
	return l
}

func encode(t *testing.T, l Lockfile) []byte {
	t.Helper()
	b, err := Encode(l)
	if err != nil {
		t.Fatalf("Encode: %v", err)
	}
	return b
}

// shuffled returns a copy of l with every list in a random order.
func shuffled(l Lockfile, r *rand.Rand) Lockfile {
	s := l
	s.Agents = append([]model.Agent(nil), l.Agents...)
	s.Tools = append([]model.Tool(nil), l.Tools...)
	s.Edges = append([]model.Edge(nil), l.Edges...)
	s.SecretRefs = []model.SecretRef{l.SecretRefs[0]}
	s.SecretRefs[0].Locations = append([]model.Location(nil), l.SecretRefs[0].Locations...)
	r.Shuffle(len(s.Agents), func(i, j int) { s.Agents[i], s.Agents[j] = s.Agents[j], s.Agents[i] })
	r.Shuffle(len(s.Tools), func(i, j int) { s.Tools[i], s.Tools[j] = s.Tools[j], s.Tools[i] })
	r.Shuffle(len(s.Edges), func(i, j int) { s.Edges[i], s.Edges[j] = s.Edges[j], s.Edges[i] })
	locs := s.SecretRefs[0].Locations
	r.Shuffle(len(locs), func(i, j int) { locs[i], locs[j] = locs[j], locs[i] })
	return s
}

// The same model gives the same bytes whatever the order of its lists
// (docs/cobertura.md, total order; E1 step 1.3).
func TestLockIsTheSameWhateverTheOrderOfItsInputs(t *testing.T) {
	l := sample(t)
	want := encode(t, l)
	r := rand.New(rand.NewPCG(1, 2))
	for i := 0; i < 20; i++ {
		if got := encode(t, shuffled(l, r)); !bytes.Equal(got, want) {
			t.Fatalf("run %d: the lockfile depends on the order of its inputs", i)
		}
	}
}

// Backward compatibility from the first day (E1 step 1.3): a v1 lockfile
// written by this version is read and written again byte for byte. A change
// of the format breaks this test and needs a new schema_version.
func TestLockV1RoundTripsByteForByte(t *testing.T) {
	data, err := os.ReadFile("testdata/v1/sample.lock")
	if err != nil {
		t.Fatalf("reading the v1 fixture: %v", err)
	}
	l, err := Decode(data)
	if err != nil {
		t.Fatalf("Decode: %v", err)
	}
	if got := encode(t, l); !bytes.Equal(got, data) {
		t.Fatalf("v1 fixture does not round-trip:\nread    %s\nwritten %s", data, got)
	}
	if !bytes.Equal(encode(t, sample(t)), data) {
		t.Fatal("the sample lockfile no longer encodes as the v1 fixture")
	}
}

func TestLockRejectsAnotherSchemaVersion(t *testing.T) {
	data := bytes.Replace(encode(t, sample(t)), []byte(`"schema_version":1`), []byte(`"schema_version":2`), 1)
	if _, err := Decode(data); err == nil || !strings.Contains(err.Error(), "schema_version") {
		t.Fatalf("Decode of schema_version 2: err = %v, want an error naming schema_version", err)
	}
}

func TestLockRejectsUnknownFields(t *testing.T) {
	data := bytes.Replace(encode(t, sample(t)), []byte(`{"agents":`), []byte(`{"agentz":[],"agents":`), 1)
	if _, err := Decode(data); err == nil || !strings.Contains(err.Error(), "agentz") {
		t.Fatalf("Decode with an unknown field: err = %v, want an error naming it", err)
	}
}

// ADR 0004: the intent block is the canonical copy of actaira.intent.json, and
// the lockfile keeps coming out the same.
func TestLockKeepsTheIntentBlock(t *testing.T) {
	l := sample(t)
	b := encode(t, l)
	want, err := Marshal(l.Intent.Value())
	if err != nil {
		t.Fatalf("Marshal of the manifest: %v", err)
	}
	if !bytes.Contains(b, append([]byte(`"intent":`), want...)) {
		t.Fatalf("the intent block is not the canonical copy of the manifest:\n%s", b)
	}
	back, err := Decode(b)
	if err != nil {
		t.Fatalf("Decode: %v", err)
	}
	if !bytes.Equal(encode(t, back), b) {
		t.Fatal("the lockfile with a contract does not round-trip")
	}
}

func TestLockWithoutIntentHasNoIntentBlock(t *testing.T) {
	l := sample(t)
	l.Intent = nil
	if b := encode(t, l); bytes.Contains(b, []byte(`"intent"`)) {
		t.Fatalf("a lockfile without actaira.intent.json has an intent block:\n%s", b)
	}
}

func TestLockRejectsWhatTheModelDoesNotAllow(t *testing.T) {
	cases := map[string]func(*Lockfile){
		"confidence":  func(l *Lockfile) { l.Tools[0].Confidence = "verified" },
		"transport":   func(l *Lockfile) { l.MCPServers[0].Transport = "grpc" },
		"edge kind":   func(l *Lockfile) { l.Edges[0].Kind = "owns" },
		"effect":      func(l *Lockfile) { l.Tools[0].Effect = "irreversible" },
		"empty id":    func(l *Lockfile) { l.Agents[0].ID = "" },
		"source file": func(l *Lockfile) { l.Agents[0].Source.File = "" },
	}
	for name, mutate := range cases {
		t.Run(name, func(t *testing.T) {
			l := sample(t)
			mutate(&l)
			if _, err := Encode(l); err == nil {
				t.Fatalf("Encode accepted a lockfile with a bad %s", name)
			}
		})
	}
}
