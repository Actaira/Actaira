// Command parse measures tree-sitter on real repositories for ADR 0003: it
// parses the first N files (in path order) of each repository that
// evals/bench/fetch.sh pinned, and prints JSON with the times, the sizes and
// where they come from. Files are read before timing, so only parsing counts.
//
// Usage: go run ./evals/bench/parse [-cache dir] [-n 1000] > evals/results/parser-<date>.json
package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"slices"
	"strings"
	"time"

	"github.com/actaira/actaira/pkg/extract/treesitter"
)

// repo is one of the repositories of evals/bench/fetch.sh.
type repo struct {
	Name   string `json:"name"`
	URL    string `json:"url"`
	Commit string `json:"commit"`
	exts   []string
}

var repos = []repo{
	{Name: "langchain", URL: "https://github.com/langchain-ai/langchain", Commit: "aaf25d0abd183a9b5978772c470a0ef11578ce3a", exts: []string{".py"}},
	{Name: "langchainjs", URL: "https://github.com/langchain-ai/langchainjs", Commit: "17b6bba8343bdd3f3dfc5c59578e0b72337ec740", exts: []string{".ts", ".tsx"}},
}

type result struct {
	Repo           repo    `json:"repo"`
	Files          int     `json:"files"`
	Bytes          int64   `json:"bytes"`
	TotalMS        float64 `json:"total_ms"`
	MedianMS       float64 `json:"median_ms_per_file"`
	P95MS          float64 `json:"p95_ms_per_file"`
	FilesWithError int     `json:"files_with_syntax_errors"`
}

type report struct {
	Date        string   `json:"date"`
	Commit      string   `json:"commit"`
	Command     string   `json:"command"`
	GoVersion   string   `json:"go_version"`
	OS          string   `json:"os"`
	Arch        string   `json:"arch"`
	CPUs        int      `json:"cpus"`
	BinaryBytes int64    `json:"bench_binary_bytes"`
	Note        string   `json:"note"`
	Results     []result `json:"results"`
}

func main() {
	home, err := os.UserHomeDir()
	if err != nil {
		fail(err)
	}
	cache := flag.String("cache", filepath.Join(home, ".cache", "actaira-bench"), "where evals/bench/fetch.sh put the repositories")
	n := flag.Int("n", 1000, "files per repository")
	flag.Parse()

	rep := report{
		Date:      time.Now().UTC().Format(time.RFC3339),
		Commit:    gitHead(),
		Command:   "go run ./evals/bench/parse -n " + fmt.Sprint(*n),
		GoVersion: runtime.Version(),
		OS:        runtime.GOOS,
		Arch:      runtime.GOARCH,
		CPUs:      runtime.NumCPU(),
		Note:      "one goroutine, files read before timing, every tree closed; bench_binary_bytes is this program, with tree-sitter and the Python, TypeScript and TSX grammars linked in",
	}
	if exe, err := os.Executable(); err == nil {
		if st, err := os.Stat(exe); err == nil {
			rep.BinaryBytes = st.Size()
		}
	}
	for _, r := range repos {
		res, err := measure(filepath.Join(*cache, r.Name+"-"+r.Commit), r, *n)
		if err != nil {
			fail(err)
		}
		rep.Results = append(rep.Results, res)
	}
	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	if err := enc.Encode(rep); err != nil {
		fail(err)
	}
}

func measure(dir string, r repo, n int) (result, error) {
	paths, err := firstFiles(dir, r.exts, n)
	if err != nil {
		return result{}, err
	}
	if len(paths) < n {
		return result{}, fmt.Errorf("%s: %d files with %v, want %d (run evals/bench/fetch.sh)", r.Name, len(paths), r.exts, n)
	}
	srcs := make([][]byte, len(paths))
	var total int64
	for i, p := range paths {
		if srcs[i], err = os.ReadFile(p); err != nil {
			return result{}, err
		}
		total += int64(len(srcs[i]))
	}
	times := make([]float64, len(paths))
	withError := 0
	start := time.Now()
	for i, p := range paths {
		lang := treesitter.Python
		switch filepath.Ext(p) {
		case ".ts":
			lang = treesitter.TypeScript
		case ".tsx":
			lang = treesitter.TSX
		}
		t0 := time.Now()
		tree, err := treesitter.Parse(lang, srcs[i])
		if err != nil {
			return result{}, fmt.Errorf("%s: %w", p, err)
		}
		if tree.HasError() {
			withError++
		}
		tree.Close()
		times[i] = float64(time.Since(t0).Microseconds()) / 1000
	}
	elapsed := time.Since(start)
	slices.Sort(times)
	return result{
		Repo:           r,
		Files:          len(paths),
		Bytes:          total,
		TotalMS:        float64(elapsed.Microseconds()) / 1000,
		MedianMS:       times[len(times)/2],
		P95MS:          times[(len(times)*95)/100-1],
		FilesWithError: withError,
	}, nil
}

// firstFiles returns the first n regular files under dir with one of exts, in
// path order, skipping .git and node_modules.
func firstFiles(dir string, exts []string, n int) ([]string, error) {
	var all []string
	err := filepath.WalkDir(dir, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() && (d.Name() == ".git" || d.Name() == "node_modules") {
			return filepath.SkipDir
		}
		if d.Type().IsRegular() && slices.Contains(exts, filepath.Ext(path)) && !strings.HasSuffix(path, ".d.ts") {
			all = append(all, path)
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	slices.Sort(all)
	if len(all) > n {
		all = all[:n]
	}
	return all, nil
}

func gitHead() string {
	out, err := exec.Command("git", "rev-parse", "HEAD").Output()
	if err != nil {
		return "unknown"
	}
	return strings.TrimSpace(string(out))
}

func fail(err error) {
	var exit *exec.ExitError
	if errors.As(err, &exit) {
		err = fmt.Errorf("%w: %s", err, exit.Stderr)
	}
	// If stderr is gone there is no one left to tell: the exit code says it.
	_, _ = fmt.Fprintln(os.Stderr, "parse:", err)
	os.Exit(1)
}
