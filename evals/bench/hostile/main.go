// Command hostile measures the worst cases of tree-sitter for ADR 0003: files
// of 1 MB built to make the parser work hard (unclosed generics, parentheses,
// brackets). Each case runs in its own process, so its peak memory (getrusage)
// is its own. Some cases parse without a deadline; others with a deadline per
// file, once or many times in a row, with and without MALLOC_ARENA_MAX=1 (glibc
// keeps an arena per thread, so a series of parses can reach more than one).
// Prints JSON with the date, commit, environment, command and, per case, the
// time and peak memory. Linux only: getrusage reports kilobytes there.
//
// Usage: go run ./evals/bench/hostile > evals/results/parser-hostil-<date>.json
package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"runtime"
	"strings"
	"syscall"
	"time"

	"github.com/actaira/actaira/pkg/extract/treesitter"
)

type hostileCase struct {
	Name       string `json:"name"`
	Grammar    string `json:"grammar"`
	Unit       string `json:"repeated"`
	Files      int    `json:"files_in_a_row"`
	DeadlineMS int    `json:"deadline_ms_per_file"`
	ArenaMax1  bool   `json:"malloc_arena_max_1"`
	lang       treesitter.Language
}

var cases = []hostileCase{
	{Name: "ts-unclosed-generics", Grammar: "typescript", Unit: "a<", Files: 1, lang: treesitter.TypeScript},
	{Name: "ts-open-call-args", Grammar: "typescript", Unit: "(a,", Files: 1, lang: treesitter.TypeScript},
	{Name: "ts-open-braces", Grammar: "typescript", Unit: "{", Files: 1, lang: treesitter.TypeScript},
	{Name: "tsx-open-elements", Grammar: "tsx", Unit: "<div>", Files: 1, lang: treesitter.TSX},
	{Name: "py-open-parens", Grammar: "python", Unit: "(", Files: 1, lang: treesitter.Python},
	{Name: "py-open-brackets", Grammar: "python", Unit: "[", Files: 1, lang: treesitter.Python},
	{Name: "ts-unclosed-generics-deadline", Grammar: "typescript", Unit: "a<", Files: 1, DeadlineMS: 50, lang: treesitter.TypeScript},
	{Name: "ts-unclosed-generics-deadline-x40", Grammar: "typescript", Unit: "a<", Files: 40, DeadlineMS: 50, lang: treesitter.TypeScript},
	{Name: "ts-unclosed-generics-deadline-x40-arena1", Grammar: "typescript", Unit: "a<", Files: 40, DeadlineMS: 50, ArenaMax1: true, lang: treesitter.TypeScript},
}

const size = 1 << 20

type result struct {
	Case       hostileCase `json:"case"`
	Bytes      int         `json:"bytes_per_file"`
	Seconds    float64     `json:"seconds"`
	PeakRSSKiB int64       `json:"peak_rss_kib"`
}

type report struct {
	Date    string   `json:"date"`
	Commit  string   `json:"commit"`
	Dirty   bool     `json:"uncommitted_changes"`
	Command string   `json:"command"`
	Go      string   `json:"go_version"`
	OS      string   `json:"os"`
	Arch    string   `json:"arch"`
	CPUs    int      `json:"cpus"`
	Kernel  string   `json:"kernel"`
	CC      string   `json:"cc"`
	Note    string   `json:"note"`
	Results []result `json:"results"`
}

func main() {
	one := flag.String("case", "", "run one case in this process (used by the parent)")
	flag.Parse()
	if runtime.GOOS != "linux" {
		fail(fmt.Errorf("only Linux: getrusage reports the peak memory in kilobytes there, not on %s", runtime.GOOS))
	}
	if *one != "" {
		runCase(*one)
		return
	}
	rep := report{
		Date:    time.Now().UTC().Format(time.RFC3339),
		Commit:  output("git", "rev-parse", "HEAD"),
		Dirty:   output("git", "status", "--porcelain") != "",
		Command: "go run ./evals/bench/hostile",
		Go:      runtime.Version(),
		OS:      runtime.GOOS,
		Arch:    runtime.GOARCH,
		CPUs:    runtime.NumCPU(),
		Kernel:  output("uname", "-sr"),
		CC:      firstLine(output("cc", "--version")),
		Note:    "1 MB per file, one process per case, one goroutine; peak_rss_kib is the maximum resident set size of that process (getrusage), including the Go runtime; a parse stopped at its deadline counts as done",
	}
	self, err := os.Executable()
	if err != nil {
		fail(err)
	}
	for _, c := range cases {
		start := time.Now()
		cmd := exec.Command(self, "-case", c.Name)
		cmd.Stderr = os.Stderr
		cmd.Env = os.Environ()
		if c.ArenaMax1 {
			cmd.Env = append(cmd.Env, "MALLOC_ARENA_MAX=1")
		}
		if err := cmd.Run(); err != nil {
			fail(fmt.Errorf("%s: %w", c.Name, err))
		}
		usage, ok := cmd.ProcessState.SysUsage().(*syscall.Rusage)
		if !ok {
			fail(fmt.Errorf("%s: no rusage", c.Name))
		}
		rep.Results = append(rep.Results, result{
			Case:       c,
			Bytes:      len(input(c)),
			Seconds:    time.Since(start).Seconds(),
			PeakRSSKiB: usage.Maxrss,
		})
	}
	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	if err := enc.Encode(rep); err != nil {
		fail(err)
	}
}

func input(c hostileCase) []byte {
	return []byte(strings.Repeat(c.Unit, size/len(c.Unit)))
}

func runCase(name string) {
	for _, c := range cases {
		if c.Name != name {
			continue
		}
		src := input(c)
		for i := 0; i < c.Files; i++ {
			ctx, cancel := context.Background(), context.CancelFunc(func() {})
			if c.DeadlineMS > 0 {
				ctx, cancel = context.WithTimeout(context.Background(), time.Duration(c.DeadlineMS)*time.Millisecond)
			}
			tree, err := treesitter.Parse(ctx, c.lang, src)
			cancel()
			switch {
			case err == nil:
				tree.Close()
			case errors.Is(err, context.DeadlineExceeded):
				// Stopped at its deadline, as the extractors will.
			default:
				fail(err)
			}
		}
		return
	}
	fail(fmt.Errorf("unknown case %q", name))
}

// output runs a command and returns its trimmed output, or "unknown".
func output(name string, args ...string) string {
	out, err := exec.Command(name, args...).Output()
	if err != nil {
		return "unknown"
	}
	return strings.TrimSpace(string(out))
}

func firstLine(s string) string {
	line, _, _ := strings.Cut(s, "\n")
	return line
}

func fail(err error) {
	// If stderr is gone there is no one left to tell: the exit code says it.
	_, _ = fmt.Fprintln(os.Stderr, "hostile:", err)
	os.Exit(1)
}
