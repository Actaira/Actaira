// Command paso3real is the real run of E1 step 1.3: the model of a small agent
// repository and its actaira.intent.json, written as actaira.lock ten times.
// In each run every list of the input is shuffled (agents, tools, MCP servers,
// variables and their locations, edges, extractors, unresolved entries and
// skipped parts) and the coverage is computed again from it (F-0033). It
// prints the hash of each run, where each agent stands with its contract and
// the lockfile pretty-printed. Usage, from the repo root:
//
//	go run ./evals/sessions/2026-10-02-e1-paso-3-real
package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"math/rand/v2"
	"os"
	"time"

	"github.com/actaira/actaira/pkg/coverage"
	"github.com/actaira/actaira/pkg/intent"
	"github.com/actaira/actaira/pkg/lock"
	"github.com/actaira/actaira/pkg/model"
)

const intentJSON = `{
  "acm_version": 0,
  "contracts": [
    {
      "agent": "%s",
      "status": "accepted",
      "accepted_by": "@example-owner",
      "accepted_at": "2026-10-02",
      "owner": "@example-owner",
      "expires": "2027-04-01",
      "allow": ["customer.read", "money.refund"],
      "deny": ["customer.delete"],
      "limits": [
        {"capability": "money.refund", "per_operation": {"amount": 50000, "currency": "EUR"}},
        {"capability": "money.refund", "per_period": {"period": "month", "amount": 200000, "currency": "EUR"}}
      ],
      "egress": ["api.stripe.com"]
    },
    {
      "agent": "%s",
      "status": "draft",
      "confidence": "inferred",
      "owner": "@example-owner",
      "expires": "2026-12-31",
      "allow": ["ticket.read"],
      "deny": [],
      "limits": [],
      "egress": []
    }
  ]
}`

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "paso3real:", err)
		os.Exit(1)
	}
}

func run() error {
	const fw = "openai-agents-python"
	at := func(file string, line, col int) model.Location {
		return model.Location{File: file, Line: line, Column: col}
	}
	support := model.NewID("agent", fw, "agents/support.py", "support", 0)
	triage := model.NewID("agent", fw, "agents/triage.py", "triage", 0)
	refund := model.NewID("tool", fw, "agents/tools.py", "issue_refund", 0)
	lookup := model.NewID("tool", fw, "agents/tools.py", "lookup_customer", 0)
	tickets := model.NewID("tool", fw, "agents/tools.py", "list_tickets", 0)
	stripe := model.NewID("mcp_server", fw, "agents/support.py", "stripe", 0)
	key := model.NewID("env_ref", "", "", "STRIPE_API_KEY", 0)
	h := func(c byte) string { return "sha256:" + string(bytes.Repeat([]byte{c}, 64)) }
	l := lock.Lockfile{
		SchemaVersion: lock.SchemaVersion,
		Agents: []model.Agent{
			{ID: support, Name: "support", Framework: fw, Source: at("agents/support.py", 30, 11), Model: &model.Model{Name: "gpt-5"}, Confidence: model.Declared},
			{ID: triage, Name: "triage", Framework: fw, Source: at("agents/triage.py", 12, 10), Confidence: model.Declared},
		},
		Tools: []model.Tool{
			{ID: refund, Name: "issue_refund", Framework: fw, Source: at("agents/tools.py", 20, 1), SchemaHash: h('1'), DescriptionHash: h('2'), Effect: model.EffectUnknown, Confidence: model.Declared},
			{ID: lookup, Name: "lookup_customer", Framework: fw, Source: at("agents/tools.py", 8, 1), SchemaHash: h('3'), DescriptionHash: h('4'), Effect: model.EffectUnknown, Confidence: model.Declared},
			{ID: tickets, Name: "list_tickets", Framework: fw, Source: at("agents/tools.py", 34, 1), Effect: model.EffectUnknown, Confidence: model.Unresolved},
		},
		MCPServers: []model.MCPServer{{ID: stripe, Name: "stripe", Transport: model.TransportStdio, Command: "npx", Package: &model.Package{Ecosystem: "npm", Name: "@stripe/mcp"}, ToolsSource: model.ToolsSourceNone, Source: at("agents/support.py", 18, 5), Confidence: model.Declared}},
		SecretRefs: []model.SecretRef{{ID: key, Name: "STRIPE_API_KEY", Locations: []model.Location{at("agents/tools.py", 22, 14)}}},
		Edges: []model.Edge{
			{From: support, To: refund, Kind: model.CanCall, Source: at("agents/support.py", 31, 12), Confidence: model.Declared},
			{From: support, To: lookup, Kind: model.CanCall, Source: at("agents/support.py", 31, 26), Confidence: model.Declared},
			{From: support, To: stripe, Kind: model.UsesMCPServer, Source: at("agents/support.py", 32, 17), Confidence: model.Declared},
			{From: triage, To: tickets, Kind: model.CanCall, Source: at("agents/triage.py", 13, 12), Confidence: model.Declared},
			{From: triage, To: support, Kind: model.DelegatesTo, Source: at("agents/triage.py", 14, 14), Confidence: model.Declared},
			{From: refund, To: key, Kind: model.ReferencesEnv, Source: at("agents/tools.py", 22, 14), Confidence: model.Declared},
		},
	}
	extractors := []string{"openai-agents-python/1", "mcp-config/1"}
	unresolved := []coverage.Finding{
		{Agent: triage, Entry: coverage.Entry{Location: at("agents/triage.py", 20, 9), Kind: "tool_list", Reason: "list_built_at_runtime"}},
		{Agent: support, Entry: coverage.Entry{Location: at("agents/support.py", 40, 3), Kind: "tool_schema", Reason: "schema_built_at_runtime"}},
	}
	skipped := []coverage.Skipped{{Path: "data/fixtures.json", Reason: "file_over_1mb"}, {Path: "vendor/sdk", Reason: "submodule"}}
	compute := func(l lock.Lockfile, extractors []string, unresolved []coverage.Finding, skipped []coverage.Skipped) (coverage.Coverage, error) {
		return coverage.Compute(coverage.Input{Extractors: extractors, Agents: l.Agents, Tools: l.Tools, MCPServers: l.MCPServers,
			SecretRefs: l.SecretRefs, Edges: l.Edges, Unresolved: unresolved, Skipped: skipped})
	}
	cov, err := compute(l, extractors, unresolved, skipped)
	if err != nil {
		return err
	}
	l.Coverage = cov
	m, err := intent.Parse([]byte(fmt.Sprintf(intentJSON, support, triage)))
	if err != nil {
		return err
	}
	agents := map[string]bool{string(support): true, string(triage): true}
	if err := m.Check(agents); err != nil {
		return err
	}
	l.Intent = &m

	r := rand.New(rand.NewPCG(7, 11))
	var first []byte
	for i := 1; i <= 10; i++ {
		s := l
		s.Agents = shuffle(r, l.Agents)
		s.Tools = shuffle(r, l.Tools)
		s.MCPServers = shuffle(r, l.MCPServers)
		s.SecretRefs = shuffle(r, l.SecretRefs)
		for j := range s.SecretRefs {
			s.SecretRefs[j].Locations = shuffle(r, s.SecretRefs[j].Locations)
		}
		s.Edges = shuffle(r, l.Edges)
		cov, err := compute(s, shuffle(r, extractors), shuffle(r, unresolved), shuffle(r, skipped))
		if err != nil {
			return err
		}
		s.Coverage = cov
		b, err := lock.Encode(s)
		if err != nil {
			return err
		}
		fmt.Printf("run %2d: %d bytes, sha256 %x\n", i, len(b), sha256.Sum256(b))
		if first == nil {
			first = b
		} else if !bytes.Equal(b, first) {
			return fmt.Errorf("run %d differs from run 1", i)
		}
	}
	back, err := lock.Decode(first)
	if err != nil {
		return fmt.Errorf("reading the lockfile back: %w", err)
	}
	fmt.Printf("read back with lock.Decode: %d agents, %d tools, intent with %d contracts\n\n", len(back.Agents), len(back.Tools), len(back.Intent.Contracts))

	for _, today := range []string{"2026-10-02", "2027-04-02"} {
		d, err := time.Parse(time.DateOnly, today)
		if err != nil {
			return err
		}
		sup, err := m.StateOf(string(support), d)
		if err != nil {
			return err
		}
		tri, err := m.StateOf(string(triage), d)
		if err != nil {
			return err
		}
		fmt.Printf("contracts on %s: support %s, triage %s\n", today, sup, tri)
	}
	orphan := map[string]bool{string(support): true}
	fmt.Printf("contract of an agent that is gone: %v\n", m.Check(orphan))
	s, err := l.Coverage.Summary(support)
	if err != nil {
		return err
	}
	fmt.Printf("coverage of support: %d of %d known sources observed; not seen: %d\n\n", s.Observed, s.Known, len(s.Unseen))

	var pretty bytes.Buffer
	if err := json.Indent(&pretty, first, "", "  "); err != nil {
		return err
	}
	fmt.Println("actaira.lock, indented here for reading (the file itself is one canonical line and a newline):")
	fmt.Println(pretty.String())
	return nil
}

func shuffle[T any](r *rand.Rand, in []T) []T {
	out := append([]T(nil), in...)
	r.Shuffle(len(out), func(i, j int) { out[i], out[j] = out[j], out[i] })
	return out
}
