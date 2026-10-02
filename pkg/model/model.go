package model

import (
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"strconv"
)

// ID identifies an agent, tool, MCP server, skill or secret reference. It is
// stable: the first 16 hex characters (64 bits) of the SHA-256 of what names
// the thing, so the same code gives the same id on any machine and run.
type ID string

// NewID returns the id of a thing of the given kind ("agent", "tool",
// "mcp_server", "skill", "env_ref"), found by framework in the file (relative
// to the repository root, with "/") under name. Each part is length-prefixed,
// so moving characters from one part to the next changes the id.
func NewID(kind, framework, file, name string) ID {
	h := sha256.New()
	var n [8]byte
	for _, part := range []string{kind, framework, file, name} {
		binary.BigEndian.PutUint64(n[:], uint64(len(part)))
		h.Write(n[:])
		h.Write([]byte(part))
	}
	return ID(hex.EncodeToString(h.Sum(nil))[:16])
}

// Confidence says how a fact is known (docs/PLAN.md, section 4).
type Confidence string

// The closed list of confidences. unresolved is a fact the extractor read and
// did not understand (docs/cobertura.md).
const (
	Declared    Confidence = "declared"
	Inferred    Confidence = "inferred"
	Conditional Confidence = "conditional"
	Effective   Confidence = "effective"
	Observed    Confidence = "observed"
	Unresolved  Confidence = "unresolved"
)

// Valid reports whether c is one of the closed list.
func (c Confidence) Valid() bool {
	switch c {
	case Declared, Inferred, Conditional, Effective, Observed, Unresolved:
		return true
	}
	return false
}

// Location is a place in the repository. Line and Column start at 1; 0 means
// the whole file (or the whole line).
type Location struct {
	File   string
	Line   int
	Column int
}

// String returns "file", "file:line" or "file:line:column".
func (l Location) String() string {
	s := l.File
	if l.Line > 0 {
		s += ":" + strconv.Itoa(l.Line)
		if l.Column > 0 {
			s += ":" + strconv.Itoa(l.Column)
		}
	}
	return s
}

// Model is the model an agent is configured with, by name.
type Model struct {
	Name string
}

// PromptRef is the system prompt of an agent, by hash only ("sha256:<hex>").
type PromptRef struct {
	Hash string
}

// Agent is an agent found in the repository.
type Agent struct {
	ID         ID
	Name       string
	Framework  string
	Source     Location
	Model      *Model
	Prompt     *PromptRef
	Confidence Confidence
}

// EffectUnknown is the only effect a tool has in the lockfile: what a tool can
// do comes from the knowledge base and is computed when shown, never stored
// (docs/cobertura.md).
const EffectUnknown = "unknown"

// Tool is a tool found in the repository. SchemaHash and DescriptionHash are
// the SHA-256 of the canonical JSON of what the extractor normalizes, empty
// when that cannot be read without running anything.
type Tool struct {
	ID              ID
	Name            string
	Framework       string
	Source          Location
	SchemaHash      string
	DescriptionHash string
	Effect          string
	Confidence      Confidence
}

// Resolved reports whether the whole definition of the tool was read from the
// repository: both hashes are known (docs/cobertura.md).
func (t Tool) Resolved() bool {
	return t.SchemaHash != "" && t.DescriptionHash != ""
}

// Transports of an MCP server.
const (
	TransportStdio = "stdio"
	TransportHTTP  = "http"
)

// ToolsSourceNone is where the tools of an MCP server come from in E1: nowhere,
// because E1 does not list them.
const ToolsSourceNone = "none"

// Package is the package an MCP server runs from.
type Package struct {
	Ecosystem string
	Name      string
	Version   string
}

// MCPServer is an MCP server declared in the repository.
type MCPServer struct {
	ID          ID
	Name        string
	Transport   string
	Command     string
	URL         string
	Package     *Package
	Pinned      bool
	ToolsSource string
	Source      Location
	Confidence  Confidence
}

// Skill is an Agent Skill (a SKILL.md) found in the repository.
type Skill struct {
	ID           ID
	Name         string
	Source       Location
	AllowedTools []string
	Confidence   Confidence
}

// SecretRef is an environment variable referenced by name. Its value is never
// read nor stored.
type SecretRef struct {
	ID        ID
	Name      string
	Locations []Location
}

// EdgeKind is the closed list of relations the lockfile records.
type EdgeKind string

// Edge kinds of E1: an agent can call a tool or uses an MCP server, hands off
// to another agent, and an agent, tool or MCP server references a variable.
const (
	CanCall       EdgeKind = "can_call"
	DelegatesTo   EdgeKind = "delegates_to"
	UsesMCPServer EdgeKind = "uses_mcp_server"
	ReferencesEnv EdgeKind = "references_env"
)

// Valid reports whether k is one of the closed list.
func (k EdgeKind) Valid() bool {
	switch k {
	case CanCall, DelegatesTo, UsesMCPServer, ReferencesEnv:
		return true
	}
	return false
}

// Edge is a relation between two things of the model, with where it was read.
type Edge struct {
	From       ID
	To         ID
	Kind       EdgeKind
	Source     Location
	Confidence Confidence
}
