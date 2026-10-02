package coverage

import (
	"fmt"
	"sort"

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
// servers reference; what no agent reaches goes to the repo block. It fails if
// an unresolved entry falls in a skipped part (unseen and unresolved never
// mix) or belongs to an agent that does not exist.
func Compute(in Input) (Coverage, error) {
	agents := map[model.ID]bool{}
	for _, a := range in.Agents {
		agents[a.ID] = true
	}
	skipped := map[string]bool{}
	for _, s := range in.Skipped {
		skipped[s.Path] = true
	}
	for _, f := range in.Unresolved {
		if f.Agent != "" && !agents[f.Agent] {
			return Coverage{}, fmt.Errorf("coverage: unresolved entry at %s belongs to unknown agent %s", f.Entry.Location, f.Agent)
		}
		if skipped[f.Entry.Location.File] {
			return Coverage{}, fmt.Errorf("coverage: %s is both skipped and unresolved; unseen and unresolved never mix", f.Entry.Location.File)
		}
	}

	tools := map[model.ID]model.Tool{}
	for _, t := range in.Tools {
		tools[t.ID] = t
	}
	servers := map[model.ID]model.MCPServer{}
	for _, s := range in.MCPServers {
		servers[s.ID] = s
	}
	secrets := map[model.ID]model.SecretRef{}
	for _, s := range in.SecretRefs {
		secrets[s.ID] = s
	}
	out := map[model.ID][]model.Edge{}
	for _, e := range in.Edges {
		out[e.From] = append(out[e.From], e)
	}

	usedServers := map[model.ID]bool{}
	usedSecrets := map[model.ID]bool{}
	c := Coverage{Version: Version}
	for _, a := range in.Agents {
		callTools := map[model.ID]bool{}
		useServers := map[model.ID]bool{}
		for _, e := range out[a.ID] {
			switch e.Kind {
			case model.CanCall:
				if _, ok := tools[e.To]; ok {
					callTools[e.To] = true
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
				entries = append(entries, f.Entry)
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
				entries = append(entries, Entry{Location: t.Source, Kind: "tool", Reason: "definition_not_resolved"})
			}
		}

		var sources []Source
		for _, id := range keys(useServers) {
			usedServers[id] = true
			s := servers[id]
			sources = append(sources, Source{Kind: SourceMCPServer, Name: s.Name, Locations: []model.Location{s.Source}, State: NotConfigured, Reason: ReasonMCPToolsNotListed})
		}
		for _, id := range keys(envs) {
			usedSecrets[id] = true
			s := secrets[id]
			sources = append(sources, Source{Kind: SourceEnvRef, Name: s.Name, Locations: s.Locations, State: NotConfigured, Reason: ReasonNoRunnerConfig})
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
			c.Repo.Sources = append(c.Repo.Sources, Source{Kind: SourceMCPServer, Name: s.Name, Locations: []model.Location{s.Source}, State: NotConfigured, Reason: ReasonMCPToolsNotListed})
		}
	}
	for _, s := range in.SecretRefs {
		if !usedSecrets[s.ID] {
			c.Repo.Sources = append(c.Repo.Sources, Source{Kind: SourceEnvRef, Name: s.Name, Locations: s.Locations, State: NotConfigured, Reason: ReasonNoRunnerConfig})
		}
	}
	for _, f := range in.Unresolved {
		if f.Agent == "" {
			c.Repo.Unresolved = append(c.Repo.Unresolved, f.Entry)
		}
	}
	c.Repo.Skipped = append(c.Repo.Skipped, in.Skipped...)
	return c, nil
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
			return summarize(append(append([]Source{}, a.Sources...), c.Repo.Sources...), c.Repo.Skipped,
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
