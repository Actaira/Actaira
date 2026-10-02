package lock

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"regexp"
	"sort"

	"github.com/actaira/actaira/pkg/coverage"
	"github.com/actaira/actaira/pkg/intent"
	"github.com/actaira/actaira/pkg/model"
)

// SchemaVersion is the version of actaira.lock that this code writes and reads
// (schemas/actaira.lock.v1.json). Reading another one is an error.
const SchemaVersion = 1

// Lockfile is actaira.lock: what the extractors found in the repository, its
// coverage block and, if the repository has actaira.intent.json, the canonical
// copy of its contracts (ADR 0004). Nothing in it depends on time, machine or
// order: every list is sorted by the canonical bytes of its elements, except
// the intent block, which keeps the order of actaira.intent.json.
type Lockfile struct {
	SchemaVersion int
	Agents        []model.Agent
	Tools         []model.Tool
	MCPServers    []model.MCPServer
	Skills        []model.Skill
	SecretRefs    []model.SecretRef
	Edges         []model.Edge
	Coverage      coverage.Coverage
	Intent        *intent.Manifest
}

var (
	idRE   = regexp.MustCompile(`^[0-9a-f]{16}$`)
	hashRE = regexp.MustCompile(`^sha256:[0-9a-f]{64}$`)
)

// Encode writes the file actaira.lock: the canonical JSON of ADR 0002 and one
// newline (F-0031). It fails, naming the field, if l breaks the model: an id
// outside its form or shared by two things, a confidence, a transport or an
// edge kind outside its closed list, a location without a file, a source that
// is not observed and has no reason, axes that are not the seven of
// docs/cobertura.md, or a contract that Parse would reject or whose agent is
// not in the lockfile (ADR 0004).
func Encode(l Lockfile) ([]byte, error) {
	v, err := value(l)
	if err != nil {
		return nil, err
	}
	b, err := Marshal(v)
	if err != nil {
		return nil, err
	}
	return append(b, '\n'), nil
}

func value(l Lockfile) (map[string]any, error) {
	if l.SchemaVersion != SchemaVersion {
		return nil, fmt.Errorf("lock: schema_version %d; this version writes %d", l.SchemaVersion, SchemaVersion)
	}
	agents, tools, servers, skills, secrets, edges := []any{}, []any{}, []any{}, []any{}, []any{}, []any{}
	// Two things never share an id (F-0032).
	ids := map[model.ID]string{}
	unique := func(id model.ID, what string) error {
		if prev, ok := ids[id]; ok {
			return fmt.Errorf("lock: id %s is both %s and %s; two things cannot share an id (F-0032)", id, prev, what)
		}
		ids[id] = what
		return nil
	}
	for i, a := range l.Agents {
		if err := unique(a.ID, fmt.Sprintf("agents[%d]", i)); err != nil {
			return nil, err
		}
	}
	for i, t := range l.Tools {
		if err := unique(t.ID, fmt.Sprintf("tools[%d]", i)); err != nil {
			return nil, err
		}
	}
	for i, x := range l.MCPServers {
		if err := unique(x.ID, fmt.Sprintf("mcp_servers[%d]", i)); err != nil {
			return nil, err
		}
	}
	for i, x := range l.Skills {
		if err := unique(x.ID, fmt.Sprintf("skills[%d]", i)); err != nil {
			return nil, err
		}
	}
	for i, x := range l.SecretRefs {
		if err := unique(x.ID, fmt.Sprintf("secret_refs[%d]", i)); err != nil {
			return nil, err
		}
	}
	for i, a := range l.Agents {
		v, err := agentValue(a)
		if err != nil {
			return nil, fmt.Errorf("lock: agents[%d]: %w", i, err)
		}
		agents = append(agents, v)
	}
	for i, t := range l.Tools {
		v, err := toolValue(t)
		if err != nil {
			return nil, fmt.Errorf("lock: tools[%d]: %w", i, err)
		}
		tools = append(tools, v)
	}
	for i, s := range l.MCPServers {
		v, err := serverValue(s)
		if err != nil {
			return nil, fmt.Errorf("lock: mcp_servers[%d]: %w", i, err)
		}
		servers = append(servers, v)
	}
	for i, s := range l.Skills {
		v, err := skillValue(s)
		if err != nil {
			return nil, fmt.Errorf("lock: skills[%d]: %w", i, err)
		}
		skills = append(skills, v)
	}
	for i, s := range l.SecretRefs {
		v, err := secretValue(s)
		if err != nil {
			return nil, fmt.Errorf("lock: secret_refs[%d]: %w", i, err)
		}
		secrets = append(secrets, v)
	}
	for i, e := range l.Edges {
		v, err := edgeValue(e)
		if err != nil {
			return nil, fmt.Errorf("lock: edges[%d]: %w", i, err)
		}
		edges = append(edges, v)
	}
	cov, err := coverageValue(l.Coverage)
	if err != nil {
		return nil, fmt.Errorf("lock: coverage: %w", err)
	}
	out := map[string]any{
		"schema_version": SchemaVersion,
		"agents":         sorted(agents),
		"tools":          sorted(tools),
		"mcp_servers":    sorted(servers),
		"skills":         sorted(skills),
		"secret_refs":    sorted(secrets),
		"edges":          sorted(edges),
		"coverage":       cov,
	}
	if l.Intent != nil {
		if err := l.Intent.Validate(); err != nil {
			return nil, fmt.Errorf("lock: %w", err)
		}
		agentIDs := map[string]bool{}
		for _, a := range l.Agents {
			agentIDs[string(a.ID)] = true
		}
		if err := l.Intent.Check(agentIDs); err != nil {
			return nil, fmt.Errorf("lock: %w", err)
		}
		out["intent"] = l.Intent.Value()
	}
	return out, nil
}

// sorted orders a list by the canonical bytes of its elements (docs/cobertura.md,
// total order). An element that cannot be written keeps its place: Marshal of
// the whole tree reports it with its path.
func sorted(list []any) []any {
	keys := make([][]byte, len(list))
	for i, e := range list {
		b, err := Marshal(e)
		if err != nil {
			// Sorted first; Marshal of the whole tree reports it with its path.
			b = nil
		}
		keys[i] = b
	}
	idx := make([]int, len(list))
	for i := range idx {
		idx[i] = i
	}
	sort.SliceStable(idx, func(a, b int) bool { return bytes.Compare(keys[idx[a]], keys[idx[b]]) < 0 })
	out := make([]any, len(list))
	for i, j := range idx {
		out[i] = list[j]
	}
	return out
}

func checkID(field string, id model.ID) error {
	if !idRE.MatchString(string(id)) {
		return fmt.Errorf("%s: %q is not an id (16 lowercase hex characters)", field, id)
	}
	return nil
}

func checkConfidence(c model.Confidence) error {
	if !c.Valid() {
		return fmt.Errorf("confidence: %q is not one of the closed list", c)
	}
	return nil
}

func locationValue(l model.Location) (map[string]any, error) {
	if l.File == "" {
		return nil, errors.New("location without a file")
	}
	if l.Line < 0 || l.Column < 0 || (l.Line == 0 && l.Column != 0) {
		return nil, fmt.Errorf("location %s: bad line or column", l)
	}
	v := map[string]any{"file": l.File}
	if l.Line > 0 {
		v["line"] = l.Line
	}
	if l.Column > 0 {
		v["column"] = l.Column
	}
	return v, nil
}

func locationsValue(ls []model.Location) ([]any, error) {
	out := []any{}
	for _, l := range ls {
		v, err := locationValue(l)
		if err != nil {
			return nil, err
		}
		out = append(out, v)
	}
	return sorted(out), nil
}

func agentValue(a model.Agent) (map[string]any, error) {
	if err := checkID("id", a.ID); err != nil {
		return nil, err
	}
	if err := checkConfidence(a.Confidence); err != nil {
		return nil, err
	}
	src, err := locationValue(a.Source)
	if err != nil {
		return nil, fmt.Errorf("source: %w", err)
	}
	v := map[string]any{"id": string(a.ID), "name": a.Name, "framework": a.Framework, "source": src, "confidence": string(a.Confidence)}
	if a.Model != nil {
		v["model"] = map[string]any{"name": a.Model.Name}
	}
	if a.Prompt != nil {
		if !hashRE.MatchString(a.Prompt.Hash) {
			return nil, fmt.Errorf("prompt.hash: %q is not sha256:<64 hex>", a.Prompt.Hash)
		}
		v["prompt"] = map[string]any{"hash": a.Prompt.Hash}
	}
	return v, nil
}

func toolValue(t model.Tool) (map[string]any, error) {
	if err := checkID("id", t.ID); err != nil {
		return nil, err
	}
	if err := checkConfidence(t.Confidence); err != nil {
		return nil, err
	}
	if t.Effect != model.EffectUnknown {
		return nil, fmt.Errorf("effect: %q; the lockfile only stores %q (docs/cobertura.md)", t.Effect, model.EffectUnknown)
	}
	src, err := locationValue(t.Source)
	if err != nil {
		return nil, fmt.Errorf("source: %w", err)
	}
	v := map[string]any{"id": string(t.ID), "name": t.Name, "framework": t.Framework, "source": src, "effect": t.Effect, "confidence": string(t.Confidence)}
	for field, h := range map[string]string{"schema_hash": t.SchemaHash, "description_hash": t.DescriptionHash} {
		if h == "" {
			continue
		}
		if !hashRE.MatchString(h) {
			return nil, fmt.Errorf("%s: %q is not sha256:<64 hex>", field, h)
		}
		v[field] = h
	}
	return v, nil
}

func serverValue(s model.MCPServer) (map[string]any, error) {
	if err := checkID("id", s.ID); err != nil {
		return nil, err
	}
	if err := checkConfidence(s.Confidence); err != nil {
		return nil, err
	}
	if s.Transport != model.TransportStdio && s.Transport != model.TransportHTTP {
		return nil, fmt.Errorf("transport: %q is not stdio or http", s.Transport)
	}
	if s.ToolsSource != model.ToolsSourceNone {
		return nil, fmt.Errorf("tools_source: %q; E1 only knows %q", s.ToolsSource, model.ToolsSourceNone)
	}
	src, err := locationValue(s.Source)
	if err != nil {
		return nil, fmt.Errorf("source: %w", err)
	}
	v := map[string]any{"id": string(s.ID), "name": s.Name, "transport": s.Transport, "pinned": s.Pinned, "tools_source": s.ToolsSource, "source": src, "confidence": string(s.Confidence)}
	if s.Command != "" {
		v["command"] = s.Command
	}
	if s.URL != "" {
		v["url"] = s.URL
	}
	if s.Package != nil {
		p := map[string]any{"ecosystem": s.Package.Ecosystem, "name": s.Package.Name}
		if s.Package.Version != "" {
			p["version"] = s.Package.Version
		}
		v["package"] = p
	}
	return v, nil
}

func skillValue(s model.Skill) (map[string]any, error) {
	if err := checkID("id", s.ID); err != nil {
		return nil, err
	}
	if err := checkConfidence(s.Confidence); err != nil {
		return nil, err
	}
	src, err := locationValue(s.Source)
	if err != nil {
		return nil, fmt.Errorf("source: %w", err)
	}
	allowed := []any{}
	for _, t := range s.AllowedTools {
		allowed = append(allowed, t)
	}
	return map[string]any{"id": string(s.ID), "name": s.Name, "source": src, "allowed_tools": sorted(allowed), "confidence": string(s.Confidence)}, nil
}

func secretValue(s model.SecretRef) (map[string]any, error) {
	if err := checkID("id", s.ID); err != nil {
		return nil, err
	}
	if s.Name == "" {
		return nil, errors.New("name: empty")
	}
	locs, err := locationsValue(s.Locations)
	if err != nil {
		return nil, fmt.Errorf("locations: %w", err)
	}
	return map[string]any{"id": string(s.ID), "name": s.Name, "locations": locs}, nil
}

func edgeValue(e model.Edge) (map[string]any, error) {
	if err := checkID("from", e.From); err != nil {
		return nil, err
	}
	if err := checkID("to", e.To); err != nil {
		return nil, err
	}
	if !e.Kind.Valid() {
		return nil, fmt.Errorf("kind: %q is not one of the closed list", e.Kind)
	}
	if err := checkConfidence(e.Confidence); err != nil {
		return nil, err
	}
	src, err := locationValue(e.Source)
	if err != nil {
		return nil, fmt.Errorf("source: %w", err)
	}
	return map[string]any{"from": string(e.From), "to": string(e.To), "kind": string(e.Kind), "source": src, "confidence": string(e.Confidence)}, nil
}

func coverageValue(c coverage.Coverage) (map[string]any, error) {
	if c.Version != coverage.Version {
		return nil, fmt.Errorf("version %d; this version writes %d", c.Version, coverage.Version)
	}
	agents := []any{}
	for i, a := range c.Agents {
		if err := checkID("agent", a.ID); err != nil {
			return nil, fmt.Errorf("agents[%d]: %w", i, err)
		}
		sources, err := sourcesValue(a.Sources)
		if err != nil {
			return nil, fmt.Errorf("agents[%d]: %w", i, err)
		}
		if err := checkAxes(a.Axes); err != nil {
			return nil, fmt.Errorf("agents[%d]: %w", i, err)
		}
		axes := []any{}
		for _, x := range a.Axes {
			v, err := axisValue(x)
			if err != nil {
				return nil, fmt.Errorf("agents[%d]: %w", i, err)
			}
			axes = append(axes, v)
		}
		entries, err := entriesValue(a.Unresolved)
		if err != nil {
			return nil, fmt.Errorf("agents[%d]: %w", i, err)
		}
		agents = append(agents, map[string]any{"agent": string(a.ID), "name": a.Name, "sources": sources, "axes": sorted(axes), "unresolved": entries})
	}
	sources, err := sourcesValue(c.Repo.Sources)
	if err != nil {
		return nil, fmt.Errorf("repo: %w", err)
	}
	entries, err := entriesValue(c.Repo.Unresolved)
	if err != nil {
		return nil, fmt.Errorf("repo: %w", err)
	}
	skipped := []any{}
	for _, s := range c.Repo.Skipped {
		if s.Path == "" || s.Reason == "" {
			return nil, fmt.Errorf("repo: skipped %q without a path or a reason", s.Path)
		}
		skipped = append(skipped, map[string]any{"path": s.Path, "reason": s.Reason})
	}
	return map[string]any{
		"version": coverage.Version,
		"agents":  sorted(agents),
		"repo":    map[string]any{"sources": sources, "unresolved": entries, "skipped": sorted(skipped)},
	}, nil
}

func sourcesValue(sources []coverage.Source) ([]any, error) {
	out := []any{}
	for _, s := range sources {
		switch s.Kind {
		case coverage.SourceRepo, coverage.SourceMCPServer, coverage.SourceEnvRef:
		default:
			return nil, fmt.Errorf("source kind %q is not one of the closed list", s.Kind)
		}
		switch s.State {
		case coverage.Observed:
		case coverage.NotConfigured, coverage.StateError, coverage.Stale:
			if s.Reason == "" {
				return nil, fmt.Errorf("source %s %q is %s without a reason", s.Kind, s.Name, s.State)
			}
		default:
			return nil, fmt.Errorf("source state %q is not one of the closed list", s.State)
		}
		v := map[string]any{"kind": string(s.Kind), "name": s.Name, "state": string(s.State)}
		if s.Reason != "" {
			v["reason"] = s.Reason
		}
		locs, err := locationsValue(s.Locations)
		if err != nil {
			return nil, fmt.Errorf("source %q: %w", s.Name, err)
		}
		v["locations"] = locs
		if s.Kind == coverage.SourceRepo {
			ex := []any{}
			for _, e := range s.Extractors {
				ex = append(ex, e)
			}
			v["extractors"] = sorted(ex)
		}
		out = append(out, v)
	}
	return sorted(out), nil
}

// checkAxes requires the seven axes once each: detected, resolved and
// unresolved with a value of 0 or more, and the four that are never written in
// actaira.lock with no_source (docs/cobertura.md).
func checkAxes(axes []coverage.Axis) error {
	want := map[coverage.AxisName]bool{
		coverage.Detected: true, coverage.Resolved: true, coverage.UnresolvedAxis: true,
		coverage.Effective: false, coverage.EffectiveUnused: false, coverage.Mediated: false, coverage.Governed: false,
	}
	seen := map[coverage.AxisName]bool{}
	for _, x := range axes {
		withValue, ok := want[x.Name]
		if !ok {
			return fmt.Errorf("axis %q is not one of the closed list", x.Name)
		}
		if seen[x.Name] {
			return fmt.Errorf("axis %s appears twice", x.Name)
		}
		seen[x.Name] = true
		if withValue && (x.Value == nil || *x.Value < 0) {
			return fmt.Errorf("axis %s needs a value of 0 or more", x.Name)
		}
		if !withValue && x.Value != nil {
			return fmt.Errorf("axis %s is never computed from the repository and carries no_source, not a value", x.Name)
		}
	}
	if len(seen) != len(want) {
		return fmt.Errorf("axes: %d of the 7, all are required and none is left out", len(seen))
	}
	return nil
}

func axisValue(x coverage.Axis) (map[string]any, error) {
	switch x.Name {
	case coverage.Detected, coverage.Resolved, coverage.UnresolvedAxis,
		coverage.Effective, coverage.EffectiveUnused, coverage.Mediated, coverage.Governed:
	default:
		return nil, fmt.Errorf("axis %q is not one of the closed list", x.Name)
	}
	if (x.Value == nil) == (x.NoSource == "") {
		return nil, fmt.Errorf("axis %s has to carry a value or no_source, not both nor none", x.Name)
	}
	v := map[string]any{"axis": string(x.Name)}
	if x.Value != nil {
		v["value"] = *x.Value
	} else {
		v["no_source"] = x.NoSource
	}
	return v, nil
}

func entriesValue(entries []coverage.Entry) ([]any, error) {
	out := []any{}
	for _, e := range entries {
		loc, err := locationValue(e.Location)
		if err != nil {
			return nil, fmt.Errorf("unresolved: %w", err)
		}
		if e.Kind == "" || e.Reason == "" {
			return nil, fmt.Errorf("unresolved at %s without a kind or a reason", e.Location)
		}
		out = append(out, map[string]any{"location": loc, "kind": e.Kind, "reason": e.Reason})
	}
	return sorted(out), nil
}

// Decode reads actaira.lock. The file may end with one newline, LF or CRLF
// (the one a tool adds or a CRLF checkout gives), or with none (F-0031).
// Another schema_version (said first), an unknown field, a value outside the
// model, a contract whose agent is not in the lockfile or bytes that Encode
// would not write are errors.
func Decode(data []byte) (Lockfile, error) {
	body := data
	if bytes.HasSuffix(body, []byte("\r\n")) {
		body = body[:len(body)-2]
	} else if bytes.HasSuffix(body, []byte("\n")) {
		body = body[:len(body)-1]
	}
	var version struct {
		SchemaVersion *int `json:"schema_version"`
	}
	if err := json.Unmarshal(body, &version); err != nil {
		return Lockfile{}, fmt.Errorf("lock: %w", err)
	}
	if version.SchemaVersion == nil || *version.SchemaVersion != SchemaVersion {
		got := "none"
		if version.SchemaVersion != nil {
			got = fmt.Sprint(*version.SchemaVersion)
		}
		return Lockfile{}, fmt.Errorf("lock: schema_version %s; this version reads %d", got, SchemaVersion)
	}
	dec := json.NewDecoder(bytes.NewReader(body))
	dec.DisallowUnknownFields()
	var raw rawLock
	if err := dec.Decode(&raw); err != nil {
		return Lockfile{}, fmt.Errorf("lock: %w", err)
	}
	if _, err := dec.Token(); !errors.Is(err, io.EOF) {
		return Lockfile{}, errors.New("lock: data after the lockfile")
	}
	l := Lockfile{SchemaVersion: SchemaVersion}
	for _, a := range raw.Agents {
		l.Agents = append(l.Agents, a.model())
	}
	for _, t := range raw.Tools {
		l.Tools = append(l.Tools, t.model())
	}
	for _, s := range raw.MCPServers {
		l.MCPServers = append(l.MCPServers, s.model())
	}
	for _, s := range raw.Skills {
		l.Skills = append(l.Skills, model.Skill{ID: model.ID(s.ID), Name: s.Name, Source: s.Source.model(), AllowedTools: s.AllowedTools, Confidence: model.Confidence(s.Confidence)})
	}
	for _, s := range raw.SecretRefs {
		l.SecretRefs = append(l.SecretRefs, model.SecretRef{ID: model.ID(s.ID), Name: s.Name, Locations: locations(s.Locations)})
	}
	for _, e := range raw.Edges {
		l.Edges = append(l.Edges, model.Edge{From: model.ID(e.From), To: model.ID(e.To), Kind: model.EdgeKind(e.Kind), Source: e.Source.model(), Confidence: model.Confidence(e.Confidence)})
	}
	l.Coverage = raw.Coverage.model()
	if len(raw.Intent) > 0 {
		m, err := intent.Parse(raw.Intent)
		if err != nil {
			return Lockfile{}, fmt.Errorf("lock: intent: %w", err)
		}
		l.Intent = &m
	}
	// What Decode accepts is exactly what Encode writes, newline aside.
	again, err := Encode(l)
	if err != nil {
		return Lockfile{}, err
	}
	if !bytes.Equal(bytes.TrimSuffix(again, []byte("\n")), body) {
		return Lockfile{}, errors.New("lock: not in the canonical form that actaira lock writes")
	}
	return l, nil
}

type rawLocation struct {
	File   string `json:"file"`
	Line   int    `json:"line"`
	Column int    `json:"column"`
}

func (r rawLocation) model() model.Location {
	return model.Location{File: r.File, Line: r.Line, Column: r.Column}
}

func locations(in []rawLocation) []model.Location {
	var out []model.Location
	for _, l := range in {
		out = append(out, l.model())
	}
	return out
}

type rawLock struct {
	SchemaVersion *int            `json:"schema_version"`
	Agents        []rawAgent      `json:"agents"`
	Tools         []rawTool       `json:"tools"`
	MCPServers    []rawServer     `json:"mcp_servers"`
	Skills        []rawSkill      `json:"skills"`
	SecretRefs    []rawSecret     `json:"secret_refs"`
	Edges         []rawEdge       `json:"edges"`
	Coverage      rawCoverage     `json:"coverage"`
	Intent        json.RawMessage `json:"intent"`
}

type rawAgent struct {
	ID        string      `json:"id"`
	Name      string      `json:"name"`
	Framework string      `json:"framework"`
	Source    rawLocation `json:"source"`
	Model     *struct {
		Name string `json:"name"`
	} `json:"model"`
	Prompt *struct {
		Hash string `json:"hash"`
	} `json:"prompt"`
	Confidence string `json:"confidence"`
}

func (r rawAgent) model() model.Agent {
	a := model.Agent{ID: model.ID(r.ID), Name: r.Name, Framework: r.Framework, Source: r.Source.model(), Confidence: model.Confidence(r.Confidence)}
	if r.Model != nil {
		a.Model = &model.Model{Name: r.Model.Name}
	}
	if r.Prompt != nil {
		a.Prompt = &model.PromptRef{Hash: r.Prompt.Hash}
	}
	return a
}

type rawTool struct {
	ID              string      `json:"id"`
	Name            string      `json:"name"`
	Framework       string      `json:"framework"`
	Source          rawLocation `json:"source"`
	SchemaHash      string      `json:"schema_hash"`
	DescriptionHash string      `json:"description_hash"`
	Effect          string      `json:"effect"`
	Confidence      string      `json:"confidence"`
}

func (r rawTool) model() model.Tool {
	return model.Tool{ID: model.ID(r.ID), Name: r.Name, Framework: r.Framework, Source: r.Source.model(), SchemaHash: r.SchemaHash, DescriptionHash: r.DescriptionHash, Effect: r.Effect, Confidence: model.Confidence(r.Confidence)}
}

type rawServer struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	Transport string `json:"transport"`
	Command   string `json:"command"`
	URL       string `json:"url"`
	Package   *struct {
		Ecosystem string `json:"ecosystem"`
		Name      string `json:"name"`
		Version   string `json:"version"`
	} `json:"package"`
	Pinned      bool        `json:"pinned"`
	ToolsSource string      `json:"tools_source"`
	Source      rawLocation `json:"source"`
	Confidence  string      `json:"confidence"`
}

func (r rawServer) model() model.MCPServer {
	s := model.MCPServer{ID: model.ID(r.ID), Name: r.Name, Transport: r.Transport, Command: r.Command, URL: r.URL, Pinned: r.Pinned, ToolsSource: r.ToolsSource, Source: r.Source.model(), Confidence: model.Confidence(r.Confidence)}
	if r.Package != nil {
		s.Package = &model.Package{Ecosystem: r.Package.Ecosystem, Name: r.Package.Name, Version: r.Package.Version}
	}
	return s
}

type rawSkill struct {
	ID           string      `json:"id"`
	Name         string      `json:"name"`
	Source       rawLocation `json:"source"`
	AllowedTools []string    `json:"allowed_tools"`
	Confidence   string      `json:"confidence"`
}

type rawSecret struct {
	ID        string        `json:"id"`
	Name      string        `json:"name"`
	Locations []rawLocation `json:"locations"`
}

type rawEdge struct {
	From       string      `json:"from"`
	To         string      `json:"to"`
	Kind       string      `json:"kind"`
	Source     rawLocation `json:"source"`
	Confidence string      `json:"confidence"`
}

type rawSource struct {
	Kind       string        `json:"kind"`
	Name       string        `json:"name"`
	Locations  []rawLocation `json:"locations"`
	State      string        `json:"state"`
	Reason     string        `json:"reason"`
	Extractors []string      `json:"extractors"`
}

type rawEntry struct {
	Location rawLocation `json:"location"`
	Kind     string      `json:"kind"`
	Reason   string      `json:"reason"`
}

type rawCoverage struct {
	Version int `json:"version"`
	Agents  []struct {
		Agent   string      `json:"agent"`
		Name    string      `json:"name"`
		Sources []rawSource `json:"sources"`
		Axes    []struct {
			Axis     string `json:"axis"`
			Value    *int   `json:"value"`
			NoSource string `json:"no_source"`
		} `json:"axes"`
		Unresolved []rawEntry `json:"unresolved"`
	} `json:"agents"`
	Repo struct {
		Sources    []rawSource `json:"sources"`
		Unresolved []rawEntry  `json:"unresolved"`
		Skipped    []struct {
			Path   string `json:"path"`
			Reason string `json:"reason"`
		} `json:"skipped"`
	} `json:"repo"`
}

func sourcesModel(in []rawSource) []coverage.Source {
	var out []coverage.Source
	for _, s := range in {
		out = append(out, coverage.Source{Kind: coverage.SourceKind(s.Kind), Name: s.Name, Locations: locations(s.Locations), State: coverage.State(s.State), Reason: s.Reason, Extractors: s.Extractors})
	}
	return out
}

func entriesModel(in []rawEntry) []coverage.Entry {
	var out []coverage.Entry
	for _, e := range in {
		out = append(out, coverage.Entry{Location: e.Location.model(), Kind: e.Kind, Reason: e.Reason})
	}
	return out
}

func (r rawCoverage) model() coverage.Coverage {
	c := coverage.Coverage{Version: r.Version}
	for _, a := range r.Agents {
		ac := coverage.Agent{ID: model.ID(a.Agent), Name: a.Name, Sources: sourcesModel(a.Sources), Unresolved: entriesModel(a.Unresolved)}
		for _, x := range a.Axes {
			ac.Axes = append(ac.Axes, coverage.Axis{Name: coverage.AxisName(x.Axis), Value: x.Value, NoSource: x.NoSource})
		}
		c.Agents = append(c.Agents, ac)
	}
	c.Repo.Sources = sourcesModel(r.Repo.Sources)
	c.Repo.Unresolved = entriesModel(r.Repo.Unresolved)
	for _, s := range r.Repo.Skipped {
		c.Repo.Skipped = append(c.Repo.Skipped, coverage.Skipped{Path: s.Path, Reason: s.Reason})
	}
	return c
}
