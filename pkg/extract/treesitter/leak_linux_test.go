//go:build linux

package treesitter

import (
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

// Every parser and tree is freed (docs/epicas/E1.md, step 1.2): parsing 1,000
// files of about 40 KB and closing each tree leaves the resident memory where
// it was. Without Close, the C memory of the trees alone is several hundred MB.
func TestParsingAThousandFilesDoesNotLeak(t *testing.T) {
	var b strings.Builder
	for i := 0; i < 1000; i++ {
		b.WriteString("def f" + strconv.Itoa(i) + "(a, b):\n    return [a + b * " + strconv.Itoa(i) + " for _ in range(3)]\n")
	}
	src := []byte(b.String())
	parseAll := func(n int) {
		for i := 0; i < n; i++ {
			tree, err := Parse(Python, src)
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
		t.Fatalf("resident memory grew %d MB after 1,000 parses (limit %d MB): a parser or tree is not closed",
			grew>>20, limit>>20)
	}
}
