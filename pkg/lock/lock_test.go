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

// parts is what a lockfile is built from: the model, the rest of the input of
// coverage.Compute and the contract. Every list has at least two elements, so
// that a missing sort shows up when they are shuffled (F-0033).
type parts struct {
	agents     []model.Agent
	tools      []model.Tool
	servers    []model.MCPServer
	skills     []model.Skill
	secrets    []model.SecretRef
	edges      []model.Edge
	extractors []string
	unresolved []coverage.Finding
	skipped    []coverage.Skipped
	intent     string
}

func sampleParts() parts {
	const fw, file = "openai-agents-python", "support/agent.py"
	at := func(line, col int) model.Location { return model.Location{File: file, Line: line, Column: col} }
	support := model.NewID("agent", fw, file, "support", 0)
	billing := model.NewID("agent", fw, file, "billing", 0)
	refund := model.NewID("tool", fw, file, "refund", 0)
	lookup := model.NewID("tool", fw, file, "lookup", 0)
	invoice := model.NewID("tool", fw, file, "invoice", 0)
	stripe := model.NewID("mcp_server", fw, file, "stripe", 0)
	github := model.NewID("mcp_server", "mcp-config", ".mcp.json", "github", 0)
	key := model.NewID("env_ref", "", "", "STRIPE_API_KEY", 0)
	token := model.NewID("env_ref", "", "", "GITHUB_TOKEN", 0)
	triage := model.NewID("skill", "agent-skills", "skills/triage/SKILL.md", "triage", 0)
	review := model.NewID("skill", "agent-skills", "skills/review/SKILL.md", "review", 0)
	return parts{
		agents: []model.Agent{
			{ID: support, Name: "support", Framework: fw, Source: at(40, 1), Model: &model.Model{Name: "gpt-5"}, Prompt: &model.PromptRef{Hash: "sha256:" + strings.Repeat("a", 64)}, Confidence: model.Declared},
			{ID: billing, Name: "billing", Framework: fw, Source: at(60, 1), Confidence: model.Declared},
		},
		tools: []model.Tool{
			{ID: refund, Name: "refund", Framework: fw, Source: at(10, 1), SchemaHash: "sha256:" + strings.Repeat("b", 64), DescriptionHash: "sha256:" + strings.Repeat("c", 64), Effect: model.EffectUnknown, Confidence: model.Declared},
			{ID: lookup, Name: "lookup", Framework: fw, Source: at(20, 1), Effect: model.EffectUnknown, Confidence: model.Unresolved},
			{ID: invoice, Name: "invoice", Framework: fw, Source: at(25, 1), Effect: model.EffectUnknown, Confidence: model.Unresolved},
		},
		servers: []model.MCPServer{
			{ID: stripe, Name: "stripe", Transport: model.TransportStdio, Command: "npx", Package: &model.Package{Ecosystem: "npm", Name: "@stripe/mcp", Version: "0.2.4"}, Pinned: true, ToolsSource: model.ToolsSourceNone, Source: at(15, 5), Confidence: model.Declared},
			{ID: github, Name: "github", Transport: model.TransportHTTP, URL: "https://api.example.invalid/mcp", ToolsSource: model.ToolsSourceNone, Source: model.Location{File: ".mcp.json", Line: 3, Column: 5}, Confidence: model.Declared},
		},
		skills: []model.Skill{
			{ID: triage, Name: "triage", Source: model.Location{File: "skills/triage/SKILL.md", Line: 1}, AllowedTools: []string{"Read", "Grep"}, Confidence: model.Declared},
			{ID: review, Name: "review", Source: model.Location{File: "skills/review/SKILL.md", Line: 1}, AllowedTools: []string{"Bash", "Edit"}, Confidence: model.Declared},
		},
		secrets: []model.SecretRef{
			{ID: key, Name: "STRIPE_API_KEY", Locations: []model.Location{at(8, 12), at(9, 3)}},
			{ID: token, Name: "GITHUB_TOKEN", Locations: []model.Location{{File: ".mcp.json", Line: 6, Column: 9}, {File: ".mcp.json", Line: 7, Column: 9}}},
		},
		edges: []model.Edge{
			{From: support, To: refund, Kind: model.CanCall, Source: at(41, 9), Confidence: model.Declared},
			{From: support, To: lookup, Kind: model.CanCall, Source: at(41, 17), Confidence: model.Declared},
			{From: support, To: billing, Kind: model.DelegatesTo, Source: at(42, 9), Confidence: model.Declared},
			{From: support, To: stripe, Kind: model.UsesMCPServer, Source: at(43, 9), Confidence: model.Declared},
			{From: refund, To: key, Kind: model.ReferencesEnv, Source: at(8, 12), Confidence: model.Declared},
			{From: github, To: token, Kind: model.ReferencesEnv, Source: model.Location{File: ".mcp.json", Line: 6, Column: 9}, Confidence: model.Declared},
		},
		extractors: []string{"openai-agents-python/1", "mcp-config/1"},
		unresolved: []coverage.Finding{
			{Agent: support, Entry: coverage.Entry{Location: at(30, 11), Kind: "tool_list", Reason: "list_built_at_runtime"}},
			{Agent: support, Entry: coverage.Entry{Location: at(22, 9), Kind: "tool_schema", Reason: "schema_built_at_runtime"}},
			{Entry: coverage.Entry{Location: model.Location{File: "support/extra.py", Line: 2, Column: 1}, Kind: coverage.SourceDeclaration, Reason: "params_built_at_runtime"}},
		},
		skipped: []coverage.Skipped{{Path: "support/prompts.py", Reason: "file_over_1mb"}, {Path: "vendor/sub", Reason: "submodule"}},
		intent: `{"acm_version": 0, "contracts": [{"agent": "` + string(support) + `", "status": "accepted",
	  "accepted_by": "@ana", "accepted_at": "2026-10-01", "owner": "@ana", "expires": "2027-04-01",
	  "allow": ["money.refund", "customer.read"], "deny": ["customer.delete"],
	  "limits": [{"capability": "money.refund", "per_operation": {"amount": 50000, "currency": "EUR"}}],
	  "egress": ["api.stripe.com"]}]}`,
	}
}

// build makes the lockfile of p, computing its coverage.
func build(t *testing.T, p parts) Lockfile {
	t.Helper()
	cov, err := coverage.Compute(coverage.Input{
		Extractors: p.extractors, Agents: p.agents, Tools: p.tools, MCPServers: p.servers,
		SecretRefs: p.secrets, Edges: p.edges, Unresolved: p.unresolved, Skipped: p.skipped,
	})
	if err != nil {
		t.Fatalf("coverage.Compute: %v", err)
	}
	m, err := intent.Parse([]byte(p.intent))
	if err != nil {
		t.Fatalf("intent.Parse: %v", err)
	}
	return Lockfile{SchemaVersion: SchemaVersion, Agents: p.agents, Tools: p.tools, MCPServers: p.servers,
		Skills: p.skills, SecretRefs: p.secrets, Edges: p.edges, Coverage: cov, Intent: &m}
}

// sample is a lockfile with two of everything: two agents with a handoff,
// tools (two unresolved, one of them called by no agent), MCP servers (one
// used by no agent), skills, secret references, unresolved entries, skipped
// parts, the coverage computed from them and a contract.
func sample(t *testing.T) Lockfile {
	t.Helper()
	return build(t, sampleParts())
}

func encode(t *testing.T, l Lockfile) []byte {
	t.Helper()
	b, err := Encode(l)
	if err != nil {
		t.Fatalf("Encode: %v", err)
	}
	return b
}

func shuffle[T any](r *rand.Rand, in []T) []T {
	out := append([]T(nil), in...)
	r.Shuffle(len(out), func(i, j int) { out[i], out[j] = out[j], out[i] })
	return out
}

// shuffledParts returns a copy of p with every list, nested ones included, in
// a random order.
func shuffledParts(p parts, r *rand.Rand) parts {
	s := p
	s.agents = shuffle(r, p.agents)
	s.tools = shuffle(r, p.tools)
	s.servers = shuffle(r, p.servers)
	s.skills = shuffle(r, p.skills)
	for i := range s.skills {
		s.skills[i].AllowedTools = shuffle(r, s.skills[i].AllowedTools)
	}
	s.secrets = shuffle(r, p.secrets)
	for i := range s.secrets {
		s.secrets[i].Locations = shuffle(r, s.secrets[i].Locations)
	}
	s.edges = shuffle(r, p.edges)
	s.extractors = shuffle(r, p.extractors)
	s.unresolved = shuffle(r, p.unresolved)
	s.skipped = shuffle(r, p.skipped)
	return s
}

// shuffledCoverage shuffles the lists of a computed coverage block, as another
// caller of Encode could hand them over.
func shuffledCoverage(c coverage.Coverage, r *rand.Rand) coverage.Coverage {
	s := c
	s.Agents = shuffle(r, c.Agents)
	for i := range s.Agents {
		s.Agents[i].Axes = shuffle(r, s.Agents[i].Axes)
		s.Agents[i].Unresolved = shuffle(r, s.Agents[i].Unresolved)
		s.Agents[i].Sources = shuffle(r, s.Agents[i].Sources)
		for j := range s.Agents[i].Sources {
			s.Agents[i].Sources[j].Locations = shuffle(r, s.Agents[i].Sources[j].Locations)
		}
	}
	s.Repo.Sources = shuffle(r, c.Repo.Sources)
	for j := range s.Repo.Sources {
		s.Repo.Sources[j].Locations = shuffle(r, s.Repo.Sources[j].Locations)
		s.Repo.Sources[j].Extractors = shuffle(r, s.Repo.Sources[j].Extractors)
	}
	s.Repo.Unresolved = shuffle(r, c.Repo.Unresolved)
	s.Repo.Skipped = shuffle(r, c.Repo.Skipped)
	return s
}

// F-0033: the same model gives the same bytes whatever the order of every
// list: the input is shuffled and the coverage computed again from it, and
// then the lists of the computed coverage are shuffled too
// (docs/cobertura.md, total order; E1 step 1.3).
func TestLockIsTheSameWhateverTheOrderOfItsInputs(t *testing.T) {
	p := sampleParts()
	want := encode(t, build(t, p))
	r := rand.New(rand.NewPCG(1, 2))
	for i := 0; i < 50; i++ {
		l := build(t, shuffledParts(p, r))
		l.Coverage = shuffledCoverage(l.Coverage, r)
		if got := encode(t, l); !bytes.Equal(got, want) {
			t.Fatalf("run %d: the lockfile depends on the order of its inputs:\nwant %s\ngot  %s", i, want, got)
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

// F-0031: the file is the canonical JSON and one newline; reading accepts the
// newline a tool adds or a CRLF checkout gives, and nothing else.
func TestLockFileEndsWithOneNewline(t *testing.T) {
	b := encode(t, sample(t))
	if !bytes.HasSuffix(b, []byte("}\n")) || bytes.HasSuffix(b, []byte("\n\n")) {
		t.Fatalf("the lockfile does not end with exactly one newline: %q", b[len(b)-3:])
	}
	body := bytes.TrimSuffix(b, []byte("\n"))
	for name, data := range map[string][]byte{"LF": b, "CRLF": append(append([]byte{}, body...), '\r', '\n'), "none": body} {
		if _, err := Decode(data); err != nil {
			t.Fatalf("Decode with %s at the end: %v", name, err)
		}
	}
	for name, data := range map[string][]byte{"two LF": append(append([]byte{}, b...), '\n'), "space": append(append([]byte{}, body...), ' ', '\n'), "leading LF": append([]byte{'\n'}, b...)} {
		if _, err := Decode(data); err == nil {
			t.Fatalf("Decode accepted %s", name)
		}
	}
}

// F-0032: two things with one id make every reference to it ambiguous.
func TestLockRejectsTwoThingsWithOneID(t *testing.T) {
	l := sample(t)
	l.Tools = append(l.Tools, l.Tools[0])
	if _, err := Encode(l); err == nil || !strings.Contains(err.Error(), string(l.Tools[0].ID)) {
		t.Fatalf("Encode with a repeated tool id: err = %v, want an error naming it", err)
	}
	l = sample(t)
	l.Agents[1].ID = l.Agents[0].ID
	if _, err := Encode(l); err == nil || !strings.Contains(err.Error(), string(l.Agents[0].ID)) {
		t.Fatalf("Encode with a repeated agent id: err = %v, want an error naming it", err)
	}
}

// The seven axes once each: the three of the repo with a value of 0 or more,
// the four that are never written in actaira.lock with no_source
// (docs/cobertura.md).
func TestLockRejectsBadAxes(t *testing.T) {
	cases := map[string]func(*Lockfile){
		"no axes": func(l *Lockfile) { l.Coverage.Agents[0].Axes = nil },
		"axis twice": func(l *Lockfile) {
			l.Coverage.Agents[0].Axes = append(l.Coverage.Agents[0].Axes, l.Coverage.Agents[0].Axes[0])
		},
		"effective with value": func(l *Lockfile) {
			setAxis(l, coverage.Effective, coverage.Axis{Name: coverage.Effective, Value: intp(0)})
		},
		"detected without value": func(l *Lockfile) {
			setAxis(l, coverage.Detected, coverage.Axis{Name: coverage.Detected, NoSource: coverage.NotFromRepo})
		},
		"negative value": func(l *Lockfile) {
			setAxis(l, coverage.Detected, coverage.Axis{Name: coverage.Detected, Value: intp(-1)})
		},
	}
	for name, mutate := range cases {
		t.Run(name, func(t *testing.T) {
			l := sample(t)
			mutate(&l)
			if _, err := Encode(l); err == nil || !strings.Contains(err.Error(), "ax") {
				t.Fatalf("Encode with %s: err = %v", name, err)
			}
		})
	}
}

func intp(n int) *int { return &n }

func setAxis(l *Lockfile, name coverage.AxisName, x coverage.Axis) {
	for i, a := range l.Coverage.Agents[0].Axes {
		if a.Name == name {
			l.Coverage.Agents[0].Axes[i] = x
		}
	}
}

// ADR 0004: the lockfile never carries an invalid contract nor one whose agent
// is gone, in either direction.
func TestLockRejectsAnOrphanOrInvalidContract(t *testing.T) {
	l := sample(t)
	l.Intent.Contracts[0].Agent = "fedcba9876543210"
	if _, err := Encode(l); err == nil || !strings.Contains(err.Error(), "fedcba9876543210") {
		t.Fatalf("Encode with an orphan contract: err = %v", err)
	}
	l = sample(t)
	l.Intent.Contracts[0].Allow = append(l.Intent.Contracts[0].Allow, "customer.delete")
	if _, err := Encode(l); err == nil || !strings.Contains(err.Error(), "customer.delete") {
		t.Fatalf("Encode with a capability in allow and deny: err = %v", err)
	}
	b := encode(t, sample(t))
	orphan := bytes.Replace(b, []byte(`"contracts":[{"accepted_at":"2026-10-01","accepted_by":"@ana","agent":"`+string(sample(t).Agents[0].ID)), []byte(`"contracts":[{"accepted_at":"2026-10-01","accepted_by":"@ana","agent":"fedcba9876543210`), 1)
	if bytes.Equal(orphan, b) {
		t.Fatal("the orphan mutation did not change the lockfile")
	}
	if _, err := Decode(orphan); err == nil || !strings.Contains(err.Error(), "fedcba9876543210") {
		t.Fatalf("Decode with an orphan contract: err = %v", err)
	}
}

// A lockfile of a newer version says its version, not an unknown field.
func TestLockAnotherSchemaVersionIsReportedFirst(t *testing.T) {
	data := bytes.Replace(encode(t, sample(t)), []byte(`{"agents":`), []byte(`{"agents_v2":[],"agents":`), 1)
	data = bytes.Replace(data, []byte(`"schema_version":1`), []byte(`"schema_version":2`), 1)
	if _, err := Decode(data); err == nil || !strings.Contains(err.Error(), "schema_version 2") {
		t.Fatalf("Decode of a v2 lockfile with a new field: err = %v, want the version", err)
	}
}
