//go:build linux

package treesitter

import (
	"context"
	"os"
	"runtime"
	"strconv"
	"strings"
	"testing"
)

// residentBytes is the resident set size of this process (/proc/self/statm),
// which counts the C memory of tree-sitter that the Go heap does not see.
func residentBytes(t *testing.T) int64 {
	t.Helper()
	data, err := os.ReadFile("/proc/self/statm")
	if err != nil {
		t.Fatalf("reading /proc/self/statm: %v", err)
	}
	fields := strings.Fields(string(data))
	if len(fields) < 2 {
		t.Fatalf("/proc/self/statm: %q", data)
	}
	pages, err := strconv.ParseInt(fields[1], 10, 64)
	if err != nil {
		t.Fatalf("/proc/self/statm: %v", err)
	}
	return pages * int64(os.Getpagesize())
}

// Every tree is freed (docs/epicas/E1.md, step 1.2): parsing 1,000 files of
// about 60 KB and closing each tree leaves the resident memory where it was.
// Without Tree.Close, the trees alone keep about 3.5 GB.
func TestParsingAThousandFilesDoesNotLeak(t *testing.T) {
	var b strings.Builder
	for i := 0; i < 1000; i++ {
		b.WriteString("def f" + strconv.Itoa(i) + "(a, b):\n    return [a + b * " + strconv.Itoa(i) + " for _ in range(3)]\n")
	}
	src := []byte(b.String())
	parseAll := func(n int) {
		for i := 0; i < n; i++ {
			tree, err := Parse(context.Background(), Python, src)
			if err != nil {
				t.Fatalf("Parse: %v", err)
			}
			tree.Close()
		}
	}
	parseAll(50) // warm up: allocator arenas and the Go heap
	runtime.GC()
	before := residentBytes(t)
	parseAll(1000)
	runtime.GC()
	after := residentBytes(t)
	const limit = 64 << 20
	if grew := after - before; grew > limit {
		t.Fatalf("resident memory grew %d MB after 1,000 parses (limit %d MB): a tree is not closed",
			grew>>20, limit>>20)
	}
}

// Every parser is freed too: its memory is small next to a tree's, so this
// takes 100,000 parses of a tiny file. Without parser.Close, 20,000 parses
// grew 84 MB (evals/sessions/2026-09-29-e1-paso-2a-mutaciones.txt), about
// 4 KB each: 100,000 give a margin of six times the limit.
func TestParsingManyTinyFilesDoesNotLeakParsers(t *testing.T) {
	src := []byte("x = 1\n")
	parseAll := func(n int) {
		for i := 0; i < n; i++ {
			tree, err := Parse(context.Background(), Python, src)
			if err != nil {
				t.Fatalf("Parse: %v", err)
			}
			tree.Close()
		}
	}
	parseAll(500)
	runtime.GC()
	before := residentBytes(t)
	parseAll(100000)
	runtime.GC()
	after := residentBytes(t)
	const limit = 64 << 20
	if grew := after - before; grew > limit {
		t.Fatalf("resident memory grew %d MB after 100,000 parses (limit %d MB): a parser is not closed",
			grew>>20, limit>>20)
	}
}
