package coverage

import (
	"strings"
	"testing"

	"github.com/actaira/actaira/pkg/model"
)

// fixture: one agent ("support") that calls two tools, one of them twice, uses
// one MCP server and references one environment variable, plus an MCP server
// and a variable that no agent uses. The repo is read by one extractor.
type fixture struct {
	in      Input
	agent   model.ID
	refund  model.ID
	lookup  model.ID
	stripe  model.ID
	orphanM model.ID
}

func newFixture() fixture {
	const fw, file = "openai-agents-python", "support/agent.py"
	f := fixture{
		agent:   model.NewID("agent", fw, file, "support", 0),
		refund:  model.NewID("tool", fw, file, "refund", 0),
		lookup:  model.NewID("tool", fw, file, "lookup", 0),
		stripe:  model.NewID("mcp_server", fw, file, "stripe", 0),
		orphanM: model.NewID("mcp_server", "mcp-config", ".mcp.json", "github", 0),
	}
	key := model.NewID("env_ref", "", "", "STRIPE_API_KEY", 0)
	other := model.NewID("env_ref", "", "", "GITHUB_TOKEN", 0)
	at := func(line int) model.Location { return model.Location{File: file, Line: line, Column: 1} }
	f.in = Input{
		Extractors: []string{"openai-agents-python/1"},
		Agents:     []model.Agent{{ID: f.agent, Name: "support", Framework: fw, Source: at(40), Confidence: model.Declared}},
		Tools: []model.Tool{
			{ID: f.refund, Name: "refund", Framework: fw, Source: at(10), SchemaHash: "sha256:01", DescriptionHash: "sha256:02", Effect: "unknown", Confidence: model.Declared},
			{ID: f.lookup, Name: "lookup", Framework: fw, Source: at(20), SchemaHash: "sha256:03", Effect: "unknown", Confidence: model.Unresolved},
		},
		MCPServers: []model.MCPServer{
			{ID: f.stripe, Name: "stripe", Transport: "stdio", Command: "npx", ToolsSource: "none", Source: at(15), Confidence: model.Declared},
			{ID: f.orphanM, Name: "github", Transport: "http", URL: "https://api.example.invalid/mcp", ToolsSource: "none", Source: model.Location{File: ".mcp.json", Line: 3, Column: 5}, Confidence: model.Declared},
		},
		SecretRefs: []model.SecretRef{
			{ID: key, Name: "STRIPE_API_KEY", Locations: []model.Location{at(8)}},
			{ID: other, Name: "GITHUB_TOKEN", Locations: []model.Location{{File: ".mcp.json", Line: 6, Column: 9}}},
		},
		Edges: []model.Edge{
			{From: f.agent, To: f.refund, Kind: model.CanCall, Source: at(41), Confidence: model.Declared},
			{From: f.agent, To: f.refund, Kind: model.CanCall, Source: at(42), Confidence: model.Declared},
			{From: f.agent, To: f.lookup, Kind: model.CanCall, Source: at(41), Confidence: model.Declared},
			{From: f.agent, To: f.stripe, Kind: model.UsesMCPServer, Source: at(43), Confidence: model.Declared},
			{From: f.refund, To: key, Kind: model.ReferencesEnv, Source: at(8), Confidence: model.Declared},
			{From: f.orphanM, To: other, Kind: model.ReferencesEnv, Source: model.Location{File: ".mcp.json", Line: 6, Column: 9}, Confidence: model.Declared},
		},
	}
	return f
}

func compute(t *testing.T, in Input) Coverage {
	t.Helper()
	c, err := Compute(in)
	if err != nil {
		t.Fatalf("Compute: %v", err)
	}
	if c.Version != Version {
		t.Fatalf("Version = %d, want %d", c.Version, Version)
	}
	return c
}

func agentOf(t *testing.T, c Coverage, id model.ID) Agent {
	t.Helper()
	for _, a := range c.Agents {
		if a.ID == id {
			return a
		}
	}
	t.Fatalf("no coverage block for agent %s", id)
	return Agent{}
}

func axis(t *testing.T, a Agent, name AxisName) Axis {
	t.Helper()
	for _, x := range a.Axes {
		if x.Name == name {
			return x
		}
	}
	t.Fatalf("agent %s has no axis %s", a.ID, name)
	return Axis{}
}

func value(t *testing.T, a Agent, name AxisName) int {
	t.Helper()
	x := axis(t, a, name)
	if x.Value == nil {
		t.Fatalf("axis %s has no value (no_source %q)", name, x.NoSource)
	}
	return *x.Value
}

func TestCoverageDetectedCountsEachToolOnce(t *testing.T) {
	f := newFixture()
	a := agentOf(t, compute(t, f.in), f.agent)
	if got := value(t, a, Detected); got != 2 {
		t.Fatalf("detected = %d, want 2 (refund is referenced twice and counts once)", got)
	}
}

func TestCoverageResolvedNeedsTheWholeDefinition(t *testing.T) {
	f := newFixture()
	a := agentOf(t, compute(t, f.in), f.agent)
	if got := value(t, a, Resolved); got != 1 {
		t.Fatalf("resolved = %d, want 1 (lookup has no description hash)", got)
	}
	// The detected tool that is not resolved leaves its own unresolved entry.
	lookupAt := "support/agent.py:20:1"
	for _, e := range a.Unresolved {
		if e.Location.String() == lookupAt {
			return
		}
	}
	t.Fatalf("no unresolved entry at %s for the unresolved tool; entries: %+v", lookupAt, a.Unresolved)
}

func TestCoverageUnresolvedCountsLocations(t *testing.T) {
	f := newFixture()
	f.in.Unresolved = []Finding{
		{Agent: f.agent, Entry: Entry{Location: model.Location{File: "support/agent.py", Line: 30, Column: 11}, Kind: "tool_list", Reason: "list_built_at_runtime"}},
		{Agent: f.agent, Entry: Entry{Location: model.Location{File: "support/agent.py", Line: 22, Column: 9}, Kind: "tool_schema", Reason: "schema_built_at_runtime"}},
	}
	a := agentOf(t, compute(t, f.in), f.agent)
	// Two entries from the extractor plus the one of the unresolved tool.
	if got := value(t, a, UnresolvedAxis); got != 3 {
		t.Fatalf("unresolved = %d, want 3 locations", got)
	}
}

func TestCoverageAxisWithoutSourceIsNotZero(t *testing.T) {
	f := newFixture()
	a := agentOf(t, compute(t, f.in), f.agent)
	for _, name := range []AxisName{Effective, EffectiveUnused, Mediated, Governed} {
		x := axis(t, a, name)
		if x.Value != nil {
			t.Fatalf("axis %s has value %d, want no value", name, *x.Value)
		}
		if x.NoSource != NotFromRepo {
			t.Fatalf("axis %s no_source = %q, want %q", name, x.NoSource, NotFromRepo)
		}
	}
	if len(a.Axes) != 7 {
		t.Fatalf("agent has %d axes, want all 7, none omitted", len(a.Axes))
	}
}

func TestCoverageSourcesCountObservedOfKnown(t *testing.T) {
	f := newFixture()
	c := compute(t, f.in)
	s, err := c.Summary(f.agent)
	if err != nil {
		t.Fatalf("Summary: %v", err)
	}
	// The agent's MCP server and variable, plus the repo block: the repo,
	// the unused MCP server and the unused variable. Only the repo is observed.
	if s.Observed != 1 || s.Known != 5 {
		t.Fatalf("summary = %d of %d known sources observed, want 1 of 5", s.Observed, s.Known)
	}
}

func TestCoverageSourceNotObservedCarriesReason(t *testing.T) {
	f := newFixture()
	c := compute(t, f.in)
	all := append([]Source{}, c.Repo.Sources...)
	for _, a := range c.Agents {
		all = append(all, a.Sources...)
	}
	for _, s := range all {
		if s.State != Observed && s.Reason == "" {
			t.Fatalf("source %s %q is %s without a reason", s.Kind, s.Name, s.State)
		}
	}
	reasons := map[SourceKind]string{}
	for _, s := range agentOf(t, c, f.agent).Sources {
		reasons[s.Kind] = s.Reason
	}
	if reasons[SourceMCPServer] != "mcp_tools_not_listed" || reasons[SourceEnvRef] != "no_runner_config" {
		t.Fatalf("agent source reasons = %v", reasons)
	}
}

func TestCoverageSkippedPartsAreUnseen(t *testing.T) {
	f := newFixture()
	f.in.Skipped = []Skipped{{Path: "support/prompts.py", Reason: "file_over_1mb"}}
	c := compute(t, f.in)
	s, err := c.Summary(f.agent)
	if err != nil {
		t.Fatalf("Summary: %v", err)
	}
	for _, u := range s.Unseen {
		if u.Kind == "skipped" && u.Name == "support/prompts.py" && u.Reason == "file_over_1mb" {
			return
		}
	}
	t.Fatalf("the skipped file is not in the unseen list: %+v", s.Unseen)
}

func TestCoverageUnseenAndUnresolvedNeverMix(t *testing.T) {
	f := newFixture()
	f.in.Skipped = []Skipped{{Path: "support/prompts.py", Reason: "file_over_1mb"}}
	f.in.Unresolved = []Finding{{Entry: Entry{Location: model.Location{File: "support/prompts.py", Line: 1}, Kind: "file", Reason: "not_decodable"}}}
	_, err := Compute(f.in)
	if err == nil || !strings.Contains(err.Error(), "support/prompts.py") {
		t.Fatalf("Compute with an unresolved entry in a skipped file: err = %v, want an error naming the file", err)
	}
}

func TestCoverageUnresolvedSourceDeclarationsAppearInTheSummary(t *testing.T) {
	f := newFixture()
	decl := model.Location{File: "support/agent.py", Line: 50, Column: 5}
	f.in.Unresolved = []Finding{{Agent: f.agent, Entry: Entry{Location: decl, Kind: SourceDeclaration, Reason: "params_built_at_runtime"}}}
	c := compute(t, f.in)
	s, err := c.Summary(f.agent)
	if err != nil {
		t.Fatalf("Summary: %v", err)
	}
	if len(s.UnresolvedSourceDeclarations) != 1 || s.UnresolvedSourceDeclarations[0] != decl {
		t.Fatalf("unresolved source declarations = %v, want [%v]", s.UnresolvedSourceDeclarations, decl)
	}
	// It does not create a source: M stays at 5.
	if s.Known != 5 {
		t.Fatalf("known sources = %d, want 5", s.Known)
	}
}

func TestCoverageRepoBlockIsShownWithoutAgents(t *testing.T) {
	in := Input{Extractors: []string{"mcp-config/1"}}
	c := compute(t, in)
	if len(c.Agents) != 0 {
		t.Fatalf("agents = %d, want 0", len(c.Agents))
	}
	if len(c.Repo.Sources) != 1 || c.Repo.Sources[0].Kind != SourceRepo || c.Repo.Sources[0].State != Observed {
		t.Fatalf("repo sources = %+v, want the observed repo", c.Repo.Sources)
	}
	s, err := c.RepoSummary()
	if err != nil {
		t.Fatalf("RepoSummary: %v", err)
	}
	if s.Observed != 1 || s.Known != 1 {
		t.Fatalf("repo summary = %d of %d, want 1 of 1", s.Observed, s.Known)
	}
}

// What no agent uses goes to the repo block, never to an agent.
func TestCoverageUnattributedSourcesGoToTheRepoBlock(t *testing.T) {
	f := newFixture()
	c := compute(t, f.in)
	names := map[string]SourceKind{}
	for _, s := range c.Repo.Sources {
		names[s.Name] = s.Kind
	}
	if names["github"] != SourceMCPServer || names["GITHUB_TOKEN"] != SourceEnvRef || names["."] != SourceRepo {
		t.Fatalf("repo sources = %+v", c.Repo.Sources)
	}
	for _, s := range agentOf(t, c, f.agent).Sources {
		if s.Name == "github" || s.Name == "GITHUB_TOKEN" {
			t.Fatalf("agent has the unused source %q", s.Name)
		}
	}
}

func TestCoverageRejectsAFindingOfAnUnknownAgent(t *testing.T) {
	f := newFixture()
	ghost := model.NewID("agent", "x", "x.py", "ghost", 0)
	f.in.Unresolved = []Finding{{Agent: ghost, Entry: Entry{Location: model.Location{File: "x.py", Line: 1}, Kind: "tool_list", Reason: "r"}}}
	if _, err := Compute(f.in); err == nil || !strings.Contains(err.Error(), string(ghost)) {
		t.Fatalf("err = %v, want an error naming %s", err, ghost)
	}
}

// F-0032: two tools with one id would make the counters depend on the order of
// the input. Compute refuses them, naming the id.
func TestCoverageRejectsTwoToolsWithOneID(t *testing.T) {
	f := newFixture()
	dup := f.in.Tools[1]
	dup.SchemaHash, dup.DescriptionHash = "", ""
	f.in.Tools = append(f.in.Tools, dup)
	if _, err := Compute(f.in); err == nil || !strings.Contains(err.Error(), string(dup.ID)) {
		t.Fatalf("Compute with two tools of one id: err = %v, want an error naming %s", err, dup.ID)
	}
}

// An edge to something that is not in the model is not dropped in silence:
// the counters would give a number without having seen it (L-009).
func TestCoverageRejectsAnEdgeToNothing(t *testing.T) {
	f := newFixture()
	ghost := model.NewID("tool", "openai-agents-python", "support/agent.py", "ghost", 0)
	f.in.Edges = append(f.in.Edges, model.Edge{From: f.agent, To: ghost, Kind: model.CanCall, Source: model.Location{File: "support/agent.py", Line: 44}, Confidence: model.Declared})
	if _, err := Compute(f.in); err == nil || !strings.Contains(err.Error(), string(ghost)) {
		t.Fatalf("Compute with an edge to nothing: err = %v, want an error naming %s", err, ghost)
	}
}

// A tool that no agent calls and that is not resolved leaves its entry in the
// repo block (docs/cobertura.md).
func TestCoverageUnattachedUnresolvedToolGoesToTheRepoBlock(t *testing.T) {
	f := newFixture()
	loose := model.Tool{ID: model.NewID("tool", "openai-agents-python", "support/helpers.py", "loose", 0), Name: "loose", Framework: "openai-agents-python",
		Source: model.Location{File: "support/helpers.py", Line: 3, Column: 1}, Effect: "unknown", Confidence: model.Unresolved}
	f.in.Tools = append(f.in.Tools, loose)
	c := compute(t, f.in)
	for _, e := range c.Repo.Unresolved {
		if e.Location == loose.Source {
			return
		}
	}
	t.Fatalf("the unattached unresolved tool left no entry in the repo block: %+v", c.Repo.Unresolved)
}

// A source is identified by its kind and its name, with all its locations: the
// same MCP server in .mcp.json and .cursor/mcp.json is one source (docs/cobertura.md).
func TestCoverageGroupsSourcesByKindAndName(t *testing.T) {
	f := newFixture()
	again := model.MCPServer{ID: model.NewID("mcp_server", "mcp-config", ".cursor/mcp.json", "github", 0), Name: "github", Transport: "http", URL: "https://api.example.invalid/mcp",
		ToolsSource: "none", Source: model.Location{File: ".cursor/mcp.json", Line: 3, Column: 5}, Confidence: model.Declared}
	f.in.MCPServers = append(f.in.MCPServers, again)
	c := compute(t, f.in)
	n := 0
	for _, s := range c.Repo.Sources {
		if s.Kind == SourceMCPServer && s.Name == "github" {
			n++
			if len(s.Locations) != 2 {
				t.Fatalf("github has %d locations, want 2", len(s.Locations))
			}
		}
	}
	if n != 1 {
		t.Fatalf("github is %d sources, want 1", n)
	}
	if s, _ := c.Summary(f.agent); s.Known != 5 {
		t.Fatalf("known sources = %d, want 5", s.Known)
	}
}

// The same finding twice (two extractors that read the same file) is one
// location (docs/cobertura.md: entries count places).
func TestCoverageCountsEachUnresolvedLocationOnce(t *testing.T) {
	f := newFixture()
	e := Entry{Location: model.Location{File: "support/agent.py", Line: 30, Column: 11}, Kind: "tool_list", Reason: "list_built_at_runtime"}
	f.in.Unresolved = []Finding{{Agent: f.agent, Entry: e}, {Agent: f.agent, Entry: e}}
	a := agentOf(t, compute(t, f.in), f.agent)
	if got := value(t, a, UnresolvedAxis); got != 2 {
		t.Fatalf("unresolved = %d, want 2 (the repeated finding and the unresolved tool)", got)
	}
}

// A skipped directory (a submodule, a depth limit) covers everything under it.
func TestCoverageUnresolvedInsideASkippedDirectoryIsRejected(t *testing.T) {
	f := newFixture()
	f.in.Skipped = []Skipped{{Path: "vendor/sub", Reason: "submodule"}}
	f.in.Unresolved = []Finding{{Entry: Entry{Location: model.Location{File: "vendor/sub/x.py", Line: 1}, Kind: "file", Reason: "not_decodable"}}}
	if _, err := Compute(f.in); err == nil || !strings.Contains(err.Error(), "vendor/sub") {
		t.Fatalf("Compute with an entry inside a skipped directory: err = %v", err)
	}
	f.in.Unresolved = []Finding{{Entry: Entry{Location: model.Location{File: "vendor/subway.py", Line: 1}, Kind: "file", Reason: "not_decodable"}}}
	if _, err := Compute(f.in); err != nil {
		t.Fatalf("a file that only shares a prefix with a skipped directory was rejected: %v", err)
	}
}
