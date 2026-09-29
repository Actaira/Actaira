// Command hostile measures the worst cases of tree-sitter for ADR 0003: files
// of 1 MB built to make the parser work hard (unclosed generics, parentheses,
// brackets), with no deadline. Each case runs in its own process, so its peak
// memory (getrusage, Linux) is its own. Prints JSON with the date, commit,
// environment, command, time and peak memory of each case.
//
// Usage: go run ./evals/bench/hostile > evals/results/parser-hostil-<date>.json
package main

import (
	"context"
	"encoding/json"
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
	Name    string `json:"name"`
	Grammar string `json:"grammar"`
	Unit    string `json:"repeated"`
	lang    treesitter.Language
}

var cases = []hostileCase{
	{Name: "ts-unclosed-generics", Grammar: "typescript", Unit: "a<", lang: treesitter.TypeScript},
	{Name: "ts-open-call-args", Grammar: "typescript", Unit: "(a,", lang: treesitter.TypeScript},
	{Name: "ts-open-braces", Grammar: "typescript", Unit: "{", lang: treesitter.TypeScript},
	{Name: "tsx-open-elements", Grammar: "tsx", Unit: "<div>", lang: treesitter.TSX},
	{Name: "py-open-parens", Grammar: "python", Unit: "(", lang: treesitter.Python},
	{Name: "py-open-brackets", Grammar: "python", Unit: "[", lang: treesitter.Python},
}

const size = 1 << 20

type result struct {
	Case       hostileCase `json:"case"`
	Bytes      int         `json:"bytes"`
	Seconds    float64     `json:"seconds"`
	PeakRSSKiB int64       `json:"peak_rss_kib"`
}

type report struct {
	Date    string   `json:"date"`
	Commit  string   `json:"commit"`
	Command string   `json:"command"`
	Go      string   `json:"go_version"`
	OS      string   `json:"os"`
	Arch    string   `json:"arch"`
	Note    string   `json:"note"`
	Results []result `json:"results"`
}

func main() {
	one := flag.String("case", "", "run one case in this process (used by the parent)")
	flag.Parse()
	if *one != "" {
		runCase(*one)
		return
	}
	rep := report{
		Date:    time.Now().UTC().Format(time.RFC3339),
		Commit:  commit(),
		Command: "go run ./evals/bench/hostile",
		Go:      runtime.Version(),
		OS:      runtime.GOOS,
		Arch:    runtime.GOARCH,
		Note:    "1 MB per case, no deadline, one process per case; peak_rss_kib is the maximum resident set size of that process (getrusage), including the Go runtime",
	}
	self, err := os.Executable()
	if err != nil {
		fail(err)
	}
	for _, c := range cases {
		start := time.Now()
		cmd := exec.Command(self, "-case", c.Name)
		cmd.Stderr = os.Stderr
		if err := cmd.Run(); err != nil {
			fail(fmt.Errorf("%s: %w", c.Name, err))
		}
		usage, ok := cmd.ProcessState.SysUsage().(*syscall.Rusage)
		if !ok {
			fail(fmt.Errorf("%s: no rusage on %s", c.Name, runtime.GOOS))
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
		if c.Name == name {
			tree, err := treesitter.Parse(context.Background(), c.lang, input(c))
			if err != nil {
				fail(err)
			}
			tree.Close()
			return
		}
	}
	fail(fmt.Errorf("unknown case %q", name))
}

func commit() string {
	out, err := exec.Command("git", "rev-parse", "HEAD").Output()
	if err != nil {
		return "unknown"
	}
	return strings.TrimSpace(string(out))
}

func fail(err error) {
	// If stderr is gone there is no one left to tell: the exit code says it.
	_, _ = fmt.Fprintln(os.Stderr, "hostile:", err)
	os.Exit(1)
}
