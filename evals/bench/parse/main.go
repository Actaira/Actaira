// Command parse measures tree-sitter on real repositories for ADR 0003: it
// parses the first N files (in path order) of each repository that
// evals/bench/fetch.sh pinned, one grammar per repository, and prints JSON with
// the times, the sizes and where they come from. Files are read before timing,
// so only parsing counts. It refuses a repository whose tree is not exactly the
// pinned commit, and records whether this repository had uncommitted changes.
//
// Usage: go run ./evals/bench/parse [-cache dir] [-n 1000] > evals/results/parser-<date>.json
package main

import (
	"context"
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

// repo is one of the repositories of evals/bench/fetch.sh, measured with one
// grammar: the files with ext, at most n of them (all of them if it has fewer).
type repo struct {
	Name    string `json:"name"`
	URL     string `json:"url"`
	Commit  string `json:"commit"`
	Grammar string `json:"grammar"`
	ext     string
	lang    treesitter.Language
}

var repos = []repo{
	{Name: "langchain", URL: "https://github.com/langchain-ai/langchain", Commit: "aaf25d0abd183a9b5978772c470a0ef11578ce3a",
		Grammar: "python", ext: ".py", lang: treesitter.Python},
	{Name: "langchainjs", URL: "https://github.com/langchain-ai/langchainjs", Commit: "17b6bba8343bdd3f3dfc5c59578e0b72337ec740",
		Grammar: "typescript", ext: ".ts", lang: treesitter.TypeScript},
	{Name: "vercel-ai", URL: "https://github.com/vercel/ai", Commit: "4556206a2d4385eb1be698e365fa1660d6ca98b8",
		Grammar: "tsx", ext: ".tsx", lang: treesitter.TSX},
}

type result struct {
	Repo           repo     `json:"repo"`
	Files          int      `json:"files"`
	EmptyFiles     int      `json:"empty_files"`
	Bytes          int64    `json:"bytes"`
	TotalMS        float64  `json:"total_ms"`
	MedianMS       float64  `json:"median_ms_per_file"`
	P95MS          float64  `json:"p95_ms_per_file"`
	FilesWithError int      `json:"files_with_syntax_errors"`
	ErrorFiles     []string `json:"error_files"`
}

type report struct {
	Date        string   `json:"date"`
	Commit      string   `json:"commit"`
	Dirty       bool     `json:"uncommitted_changes"`
	Command     string   `json:"command"`
	GoVersion   string   `json:"go_version"`
	OS          string   `json:"os"`
	Arch        string   `json:"arch"`
	CPUs        int      `json:"cpus"`
	Kernel      string   `json:"kernel"`
	CC          string   `json:"cc"`
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
	if *n < 1 {
		fail(fmt.Errorf("-n %d: at least one file per repository", *n))
	}

	rep := report{
		Date:      time.Now().UTC().Format(time.RFC3339),
		Commit:    output(".", "git", "rev-parse", "HEAD"),
		Dirty:     output(".", "git", "status", "--porcelain") != "",
		Kernel:    output(".", "uname", "-sr"),
		CC:        firstLine(output(".", "cc", "--version")),
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
	if head := output(dir, "git", "rev-parse", "HEAD"); head != r.Commit {
		return result{}, fmt.Errorf("%s is at %q, not at %s (run evals/bench/fetch.sh)", dir, head, r.Commit)
	}
	if st := output(dir, "git", "status", "--porcelain"); st != "" {
		return result{}, fmt.Errorf("%s has changes on top of %s (run evals/bench/fetch.sh)", dir, r.Commit)
	}
	paths, err := firstFiles(dir, r.ext, n)
	if err != nil {
		return result{}, err
	}
	if len(paths) == 0 {
		return result{}, fmt.Errorf("%s: no %s files (run evals/bench/fetch.sh)", r.Name, r.ext)
	}
	srcs := make([][]byte, len(paths))
	var total int64
	empty := 0
	for i, p := range paths {
		if srcs[i], err = os.ReadFile(p); err != nil {
			return result{}, err
		}
		total += int64(len(srcs[i]))
		if len(srcs[i]) == 0 {
			empty++
		}
	}
	times := make([]float64, len(paths))
	withError := 0
	var errorFiles []string
	start := time.Now()
	for i, p := range paths {
		t0 := time.Now()
		tree, err := treesitter.Parse(context.Background(), r.lang, srcs[i])
		if err != nil {
			return result{}, fmt.Errorf("%s: %w", p, err)
		}
		if tree.HasError() {
			withError++
			if rel, err := filepath.Rel(dir, p); err == nil {
				errorFiles = append(errorFiles, filepath.ToSlash(rel))
			}
		}
		tree.Close()
		times[i] = float64(time.Since(t0).Microseconds()) / 1000
	}
	elapsed := time.Since(start)
	slices.Sort(times)
	return result{
		Repo:           r,
		Files:          len(paths),
		EmptyFiles:     empty,
		Bytes:          total,
		TotalMS:        float64(elapsed.Microseconds()) / 1000,
		MedianMS:       times[(len(times)-1)/2],
		P95MS:          times[nearestRank(len(times), 95)],
		FilesWithError: withError,
		ErrorFiles:     errorFiles,
	}, nil
}

// nearestRank is the index, in a sorted slice of n values, of the p-th
// percentile by the nearest-rank method: ceil(p/100 * n) - 1.
func nearestRank(n, p int) int {
	return (p*n+99)/100 - 1
}

// firstFiles returns the first n regular files under dir with ext, in path
// order, skipping .git, node_modules and TypeScript declarations (.d.ts).
func firstFiles(dir, ext string, n int) ([]string, error) {
	var all []string
	err := filepath.WalkDir(dir, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() && (d.Name() == ".git" || d.Name() == "node_modules") {
			return filepath.SkipDir
		}
		if d.Type().IsRegular() && filepath.Ext(path) == ext && !strings.HasSuffix(path, ".d.ts") {
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

// output runs a command in dir and returns its trimmed output, or "unknown".
func output(dir, name string, args ...string) string {
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	out, err := cmd.Output()
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
	var exit *exec.ExitError
	if errors.As(err, &exit) {
		err = fmt.Errorf("%w: %s", err, exit.Stderr)
	}
	// If stderr is gone there is no one left to tell: the exit code says it.
	_, _ = fmt.Fprintln(os.Stderr, "parse:", err)
	os.Exit(1)
}
