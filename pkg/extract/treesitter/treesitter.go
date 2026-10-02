// Package treesitter parses source files with tree-sitter, through the
// official Go binding (github.com/tree-sitter/go-tree-sitter, cgo) and the
// official grammars of Python, TypeScript and TSX (ADR 0003). It only builds
// syntax trees: nothing from the parsed file is ever run. Every tree holds C
// memory that the Go collector does not see, so Close must be called.
package treesitter

import (
	"context"
	"errors"
	"fmt"
	"time"

	sitter "github.com/tree-sitter/go-tree-sitter"
	python "github.com/tree-sitter/tree-sitter-python/bindings/go"
	typescript "github.com/tree-sitter/tree-sitter-typescript/bindings/go"
)

// Language is a grammar that Parse knows.
type Language int

// The grammars. TSX has its own: the TypeScript grammar reads JSX as errors,
// so the extractors pick the grammar by extension.
const (
	Python Language = iota
	TypeScript
	TSX
)

func (l Language) String() string {
	switch l {
	case Python:
		return "python"
	case TypeScript:
		return "typescript"
	case TSX:
		return "tsx"
	}
	return fmt.Sprintf("Language(%d)", int(l))
}

func (l Language) grammar() (*sitter.Language, error) {
	switch l {
	case Python:
		return sitter.NewLanguage(python.Language()), nil
	case TypeScript:
		return sitter.NewLanguage(typescript.LanguageTypescript()), nil
	case TSX:
		return sitter.NewLanguage(typescript.LanguageTSX()), nil
	}
	return nil, fmt.Errorf("treesitter: unknown language %v", l)
}

// Tree is the syntax tree of one file. After Close it must not be used.
type Tree struct {
	t *sitter.Tree
}

// Parse parses src with the grammar of lang. Broken code is not an error: the
// tree comes back with its ERROR and MISSING nodes (HasError). The deadline of
// ctx is passed to tree-sitter, and a parse it stops returns an error that
// wraps context.DeadlineExceeded. It bounds neither time nor memory: a hostile
// file can take seconds and a GB (ADR 0003), and the final error recovery does
// not check the deadline (F-0026), so callers bound the file size first. A
// context canceled without a deadline is only checked before parsing starts:
// go-tree-sitter v0.25.0 cannot stop a parse any other way without leaking
// (F-0024).
func Parse(ctx context.Context, lang Language, src []byte) (*Tree, error) {
	if err := ctx.Err(); err != nil {
		return nil, fmt.Errorf("treesitter: parse not started: %w", err)
	}
	grammar, err := lang.grammar()
	if err != nil {
		return nil, err
	}
	parser := sitter.NewParser()
	defer parser.Close()
	if err := parser.SetLanguage(grammar); err != nil {
		return nil, fmt.Errorf("treesitter: %v grammar: %w", lang, err)
	}
	deadline, hasDeadline := ctx.Deadline()
	if hasDeadline {
		left := time.Until(deadline).Microseconds()
		if left <= 0 {
			return nil, fmt.Errorf("treesitter: parse not started: %w", context.DeadlineExceeded)
		}
		// ParseOptions and its progress callback would stop the parse too, but
		// go-tree-sitter v0.25.0 never frees the options it is given, and with
		// them the caller's context (F-0024).
		parser.SetTimeoutMicros(uint64(left)) //nolint:staticcheck // F-0024: the one way to stop a parse without leaking
	}
	read := func(i int, _ sitter.Point) []byte {
		if i < len(src) {
			return src[i:]
		}
		return []byte{}
	}
	t := parser.ParseWithOptions(read, nil, nil)
	if t == nil {
		if hasDeadline {
			return nil, fmt.Errorf("treesitter: parse stopped at the deadline: %w", context.DeadlineExceeded)
		}
		return nil, errors.New("treesitter: the parser returned no tree")
	}
	return &Tree{t: t}, nil
}

// RootKind is the node kind of the root ("module" for Python, "program" for
// TypeScript and TSX).
func (t *Tree) RootKind() string {
	return t.t.RootNode().Kind()
}

// HasError reports whether the tree has ERROR or MISSING nodes.
func (t *Tree) HasError() bool {
	return t.t.RootNode().HasError()
}

// Close frees the C memory of the tree. A second call does nothing:
// go-tree-sitter itself would free the same memory twice.
func (t *Tree) Close() {
	if t.t != nil {
		t.t.Close()
		t.t = nil
	}
}
