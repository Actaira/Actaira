package coverage

import (
	"fmt"
	"sort"
	"strings"

	"github.com/actaira/actaira/pkg/model"
)

// Version is the version of the coverage block. It only goes up together with
// the schema_version of actaira.lock (docs/cobertura.md).
const Version = 1

// SourceKind is the kind of a source: something Actaira learns capabilities from.
type SourceKind string

// Source kinds of E1.
const (
	SourceRepo      SourceKind = "repo"
	SourceMCPServer SourceKind = "mcp_server"
	SourceEnvRef    SourceKind = "env_ref"
)

// State is the state of a source.
type State string

// Source states (docs/cobertura.md, part 2).
const (
	Observed      State = "observed"
	NotConfigured State = "not_configured"
	StateError    State = "error"
	Stale         State = "stale"
)

// Reasons for the sources that E1 knows and cannot look at.
const (
	ReasonMCPToolsNotListed = "mcp_tools_not_listed"
	ReasonNoRunnerConfig    = "no_runner_config"
)

// Source is a source of an agent or of the repo block, with its state. A
// source that is not observed always carries its reason.
type Source struct {
	Kind       SourceKind
	Name       string
	Locations  []model.Location
	State      State
	Reason     string
	Extractors []string // only for the repo: the extractors and versions that read it
}

// AxisName is an axis of the capability part of the view.
type AxisName string

// The axes (docs/cobertura.md, part 1). E1 gives a number for the first three;
// the others have no source in the lockfile.
const (
	Detected        AxisName = "detected"
	Resolved        AxisName = "resolved"
	UnresolvedAxis  AxisName = "unresolved"
	Effective       AxisName = "effective"
	EffectiveUnused AxisName = "effective_unused"
	Mediated        AxisName = "mediated"
	Governed        AxisName = "governed"
)

// NotFromRepo is why an axis has no number in actaira.lock: it is computed in
// the cloud or the runner, never from the repository.
const NotFromRepo = "not_from_repo"

// Axis is one axis: a number, or no number with the reason.
type Axis struct {
	Name     AxisName
	Value    *int
	NoSource string
}

// SourceDeclaration is the kind of an unresolved entry for a source that could
// not be understood (an MCP server built with params=load()): it does not
// create a source, and the summary lists it.
const SourceDeclaration = "source_declaration"

// Entry is an unresolved entry: a place the extractor read and did not
// understand.
type Entry struct {
	Location model.Location
	Kind     string
	Reason   string
}

// Skipped is a part of the repository that was not read, with why.
type Skipped struct {
	Path   string
	Reason string
}

// Agent is the coverage block of one agent.
type Agent struct {
	ID         model.ID
	Name       string
	Sources    []Source
	Axes       []Axis
	Unresolved []Entry
}

// Repo is the block of what belongs to no agent.
type Repo struct {
	Sources    []Source
	Unresolved []Entry
	Skipped    []Skipped
}

// Coverage is the coverage block of actaira.lock.
type Coverage struct {
	Version int
	Agents  []Agent
	Repo    Repo
}

// Finding is an unresolved entry and the agent it belongs to ("" for the repo block).
type Finding struct {
	Agent model.ID
	Entry Entry
}

// Input is what the extractors found in the repository.
type Input struct {
	Extractors []string
	Agents     []model.Agent
	Tools      []model.Tool
	MCPServers []model.MCPServer
	SecretRefs []model.SecretRef
	Edges      []model.Edge
	Unresolved []Finding
	Skipped    []Skipped
}

// Compute builds the coverage block. Each agent gets the tools it can call,
// the MCP servers it uses and the variables that it, its tools or its MCP
// servers reference; what no agent reaches goes to the repo block, also a tool
// that no agent calls. A source is one per kind and name, with all its
// locations, and an unresolved entry counts once per place, kind and reason.
// Compute fails, naming what is wrong, if two things share an id, an edge or a
// finding points to something that is not in the input, or an unresolved
// entry falls in a skipped part (unseen and unresolved never mix).
func Compute(in Input) (Coverage, error) {
	known := map[model.ID]string{}
	add := func(id model.ID, kind, name string, src model.Location) error {
		if prev, ok := known[id]; ok {
			return fmt.Errorf("coverage: id %s is both a %s and a %s %s; two things cannot share an id (F-0032)", id, prev, kind, name)
		}
		known[id] = kind
		for _, k := range in.Skipped {
			if src.File != "" && under(src.File, k.Path) {
				return fmt.Errorf("coverage: %s %s was read in %s, which is skipped; seen and unseen never mix", kind, name, src.File)
			}
		}
		return nil
	}
	agents := map[model.ID]bool{}
	for _, a := range in.Agents {
		if err := add(a.ID, "agent", a.Name, a.Source); err != nil {
			return Coverage{}, err
		}
		agents[a.ID] = true
	}
	tools := map[model.ID]model.Tool{}
	for _, t := range in.Tools {
		if err := add(t.ID, "tool", t.Name, t.Source); err != nil {
			return Coverage{}, err
		}
		tools[t.ID] = t
	}
	servers := map[model.ID]model.MCPServer{}
	for _, s := range in.MCPServers {
		if err := add(s.ID, "mcp_server", s.Name, s.Source); err != nil {
			return Coverage{}, err
		}
		servers[s.ID] = s
	}
	secrets := map[model.ID]model.SecretRef{}
	for _, s := range in.SecretRefs {
		if err := add(s.ID, "env_ref", s.Name, model.Location{}); err != nil {
			return Coverage{}, err
		}
		secrets[s.ID] = s
	}
	out := map[model.ID][]model.Edge{}
	for _, e := range in.Edges {
		if err := CheckEdge(e, known); err != nil {
			return Coverage{}, fmt.Errorf("coverage: %w", err)
		}
		out[e.From] = append(out[e.From], e)
	}
	for _, f := range in.Unresolved {
		if f.Agent != "" && !agents[f.Agent] {
			return Coverage{}, fmt.Errorf("coverage: unresolved entry at %s belongs to unknown agent %s", f.Entry.Location, f.Agent)
		}
		for _, k := range in.Skipped {
			if under(f.Entry.Location.File, k.Path) {
				return Coverage{}, fmt.Errorf("coverage: %s is unresolved inside %s, which is skipped; unseen and unresolved never mix", f.Entry.Location.File, k.Path)
			}
		}
	}

	usedServers := map[model.ID]bool{}
	usedSecrets := map[model.ID]bool{}
	calledTools := map[model.ID]bool{}
	c := Coverage{Version: Version}
	for _, a := range in.Agents {
		callTools := map[model.ID]bool{}
		useServers := map[model.ID]bool{}
		for _, e := range out[a.ID] {
			switch e.Kind {
			case model.CanCall:
				if _, ok := tools[e.To]; ok {
					callTools[e.To] = true
					calledTools[e.To] = true
				}
			case model.UsesMCPServer:
				if _, ok := servers[e.To]; ok {
					useServers[e.To] = true
				}
			}
		}
		envs := map[model.ID]bool{}
		for _, from := range append(append([]model.ID{a.ID}, keys(callTools)...), keys(useServers)...) {
			for _, e := range out[from] {
				if _, ok := secrets[e.To]; ok && e.Kind == model.ReferencesEnv {
					envs[e.To] = true
				}
			}
		}

		var entries []Entry
		for _, f := range in.Unresolved {
			if f.Agent == a.ID {
				entries = addEntry(entries, f.Entry)
			}
		}
		resolved := 0
		for _, id := range keys(callTools) {
			t := tools[id]
			if t.Resolved() {
				resolved++
				continue
			}
			// A detected tool that is not resolved leaves its own entry.
			if !hasEntryAt(entries, t.Source) {
				entries = addEntry(entries, Entry{Location: t.Source, Kind: "tool", Reason: "definition_not_resolved"})
			}
		}

		var sources []Source
		for _, id := range keys(useServers) {
			usedServers[id] = true
			s := servers[id]
			sources = addSource(sources, Source{Kind: SourceMCPServer, Name: s.Name, Locations: []model.Location{s.Source}, State: NotConfigured, Reason: ReasonMCPToolsNotListed})
		}
		for _, id := range keys(envs) {
			usedSecrets[id] = true
			s := secrets[id]
			sources = addSource(sources, Source{Kind: SourceEnvRef, Name: s.Name, Locations: s.Locations, State: NotConfigured, Reason: ReasonNoRunnerConfig})
		}

		c.Agents = append(c.Agents, Agent{
			ID:         a.ID,
			Name:       a.Name,
			Sources:    sources,
			Axes:       axes(len(callTools), resolved, len(entries)),
			Unresolved: entries,
		})
	}

	c.Repo.Sources = append(c.Repo.Sources, Source{Kind: SourceRepo, Name: ".", State: Observed, Extractors: in.Extractors})
	for _, s := range in.MCPServers {
		if !usedServers[s.ID] {
			c.Repo.Sources = addSource(c.Repo.Sources, Source{Kind: SourceMCPServer, Name: s.Name, Locations: []model.Location{s.Source}, State: NotConfigured, Reason: ReasonMCPToolsNotListed})
		}
	}
	for _, s := range in.SecretRefs {
		if !usedSecrets[s.ID] {
			c.Repo.Sources = addSource(c.Repo.Sources, Source{Kind: SourceEnvRef, Name: s.Name, Locations: s.Locations, State: NotConfigured, Reason: ReasonNoRunnerConfig})
		}
	}
	for _, f := range in.Unresolved {
		if f.Agent == "" {
			c.Repo.Unresolved = addEntry(c.Repo.Unresolved, f.Entry)
		}
	}
	// A tool that no agent calls belongs to the repo block, and if it is not
	// resolved its entry goes there (docs/cobertura.md).
	for _, t := range in.Tools {
		if !calledTools[t.ID] && !t.Resolved() && !hasEntryAt(c.Repo.Unresolved, t.Source) {
			c.Repo.Unresolved = addEntry(c.Repo.Unresolved, Entry{Location: t.Source, Kind: "tool", Reason: "definition_not_resolved"})
		}
	}
	c.Repo.Skipped = append(c.Repo.Skipped, in.Skipped...)
	return c, nil
}

// edgeEnds lists, for each edge kind, the kinds its two ends can have.
var edgeEnds = map[model.EdgeKind]struct{ from, to []string }{
	model.CanCall:       {[]string{"agent"}, []string{"tool"}},
	model.DelegatesTo:   {[]string{"agent"}, []string{"agent"}},
	model.UsesMCPServer: {[]string{"agent"}, []string{"mcp_server"}},
	model.ReferencesEnv: {[]string{"agent", "tool", "mcp_server"}, []string{"env_ref"}},
}

// CheckEdge fails if e joins things that are not in kinds (id to "agent",
// "tool", "mcp_server" or "env_ref"), or of kinds its kind does not allow: an
// edge it cannot understand is never dropped in silence (L-009).
func CheckEdge(e model.Edge, kinds map[model.ID]string) error {
	ends, ok := edgeEnds[e.Kind]
	if !ok {
		return fmt.Errorf("edge %q at %s: not one of the closed list", e.Kind, e.Source)
	}
	for _, end := range []struct {
		id      model.ID
		allowed []string
		side    string
	}{{e.From, ends.from, "from"}, {e.To, ends.to, "to"}} {
		kind, ok := kinds[end.id]
		if !ok {
			return fmt.Errorf("edge %s at %s: %s %s is not in the model", e.Kind, e.Source, end.side, end.id)
		}
		if !contains(end.allowed, kind) {
			return fmt.Errorf("edge %s at %s: %s %s is a %s, not a %s", e.Kind, e.Source, end.side, end.id, kind, strings.Join(end.allowed, " or "))
		}
	}
	return nil
}

func contains(list []string, s string) bool {
	for _, x := range list {
		if x == s {
			return true
		}
	}
	return false
}

// under reports whether file is path or inside the directory path.
func under(file, path string) bool {
	return file == path || strings.HasPrefix(file, strings.TrimSuffix(path, "/")+"/")
}

// addSource adds s, or joins its locations to the source of the same kind and
// name: a source is identified by both (docs/cobertura.md).
func addSource(sources []Source, s Source) []Source {
	for i := range sources {
		if sources[i].Kind == s.Kind && sources[i].Name == s.Name {
			for _, l := range s.Locations {
				if !hasLocation(sources[i].Locations, l) {
					sources[i].Locations = append(sources[i].Locations, l)
				}
			}
			return sources
		}
	}
	s.Locations = append([]model.Location(nil), s.Locations...)
	return append(sources, s)
}

func hasLocation(ls []model.Location, l model.Location) bool {
	for _, x := range ls {
		if x == l {
			return true
		}
	}
	return false
}

// addEntry adds e unless the same entry (place, kind and reason) is already
// there: entries count places, not reports (docs/cobertura.md).
func addEntry(entries []Entry, e Entry) []Entry {
	for _, x := range entries {
		if x == e {
			return entries
		}
	}
	return append(entries, e)
}

// axes returns the seven axes, in name order: the three that E1 counts and the
// four that have no source in the lockfile (never 0, never left out).
func axes(detected, resolved, unresolved int) []Axis {
	v := func(n int) *int { return &n }
	return []Axis{
		{Name: Detected, Value: v(detected)},
		{Name: Effective, NoSource: NotFromRepo},
		{Name: EffectiveUnused, NoSource: NotFromRepo},
		{Name: Governed, NoSource: NotFromRepo},
		{Name: Mediated, NoSource: NotFromRepo},
		{Name: Resolved, Value: v(resolved)},
		{Name: UnresolvedAxis, Value: v(unresolved)},
	}
}

func hasEntryAt(entries []Entry, l model.Location) bool {
	for _, e := range entries {
		if e.Location == l {
			return true
		}
	}
	return false
}

// keys returns the keys of m in a fixed order.
func keys(m map[model.ID]bool) []model.ID {
	out := make([]model.ID, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Slice(out, func(i, j int) bool { return out[i] < out[j] })
	return out
}

// Unseen is something not looked at: a source that is not observed, or a
// skipped part of an observed source.
type Unseen struct {
	Kind   string // "source" or "skipped"
	Name   string
	State  State
	Reason string
}

// Summary is "N of M known sources observed" plus what was not seen, and the
// source declarations that could not be understood. Never a percentage.
type Summary struct {
	Observed                     int
	Known                        int
	Unseen                       []Unseen
	UnresolvedSourceDeclarations []model.Location
}

// Summary returns the summary of one agent: its sources plus those of the repo
// block, which can belong to any agent.
func (c Coverage) Summary(agent model.ID) (Summary, error) {
	for _, a := range c.Agents {
		if a.ID == agent {
			var all []Source
			for _, s := range append(append([]Source{}, a.Sources...), c.Repo.Sources...) {
				all = addSource(all, s)
			}
			return summarize(all, c.Repo.Skipped,
				append(append([]Entry{}, a.Unresolved...), c.Repo.Unresolved...)), nil
		}
	}
	return Summary{}, fmt.Errorf("coverage: no block for agent %s", agent)
}

// RepoSummary returns the summary of the repo block alone, for a repository
// with no agents.
func (c Coverage) RepoSummary() (Summary, error) {
	return summarize(c.Repo.Sources, c.Repo.Skipped, c.Repo.Unresolved), nil
}

func summarize(sources []Source, skipped []Skipped, entries []Entry) Summary {
	s := Summary{Known: len(sources)}
	for _, src := range sources {
		if src.State == Observed {
			s.Observed++
			continue
		}
		s.Unseen = append(s.Unseen, Unseen{Kind: "source", Name: src.Name, State: src.State, Reason: src.Reason})
	}
	for _, k := range skipped {
		s.Unseen = append(s.Unseen, Unseen{Kind: "skipped", Name: k.Path, Reason: k.Reason})
	}
	for _, e := range entries {
		if e.Kind == SourceDeclaration {
			s.UnresolvedSourceDeclarations = append(s.UnresolvedSourceDeclarations, e.Location)
		}
	}
	return s
}
