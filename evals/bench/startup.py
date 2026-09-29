#!/usr/bin/env python3
"""Measures the start-up time of `actaira version` and the size of the binary.

Builds ./cmd/actaira from the committed tree into a temporary directory, runs
it 20 times to warm up and then N times (200 by default), and prints JSON with
the date, commit, environment, command and figures (ADR 0001, "Latencia").
Refuses to measure a dirty tree, so the commit in the output is what was built.
Usage: python3 evals/bench/startup.py [N] > evals/results/<date>-arranque-cli.json
"""
import datetime
import json
import os
import platform
import statistics
import subprocess
import sys
import tempfile
import time

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def git(*args):
    return subprocess.run(["git", "-C", REPO, *args], stdout=subprocess.PIPE, text=True, check=True).stdout.strip()


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 200
    if git("status", "--porcelain", "--", "cmd", "internal", "pkg", "go.mod"):
        sys.exit("startup.py: hay cambios sin commitear en el código; commitea antes de medir")
    with tempfile.TemporaryDirectory() as tmp:
        binary = os.path.join(tmp, "actaira")
        build = ["go", "build", "-trimpath", "-o", binary, "./cmd/actaira"]
        subprocess.run(build, cwd=REPO, check=True)
        for _ in range(20):
            subprocess.run([binary, "version"], stdout=subprocess.DEVNULL, check=True)
        times = []
        for _ in range(n):
            start = time.perf_counter_ns()
            subprocess.run([binary, "version"], stdout=subprocess.DEVNULL, check=True)
            times.append((time.perf_counter_ns() - start) / 1e6)
        size = os.path.getsize(binary)
    times.sort()
    print(json.dumps({
        "date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "commit": git("rev-parse", "HEAD"),
        "environment": {
            "os": platform.platform(),
            "go": subprocess.run(["go", "version"], stdout=subprocess.PIPE, text=True, check=True).stdout.strip(),
            "python": platform.python_version(),
        },
        "command": " ".join(build) + f" && {n} x actaira version (after 20 warm-up runs), timed from Python",
        "runs": n,
        "median_ms": round(statistics.median(times), 3),
        "p95_ms": round(times[max(0, int(0.95 * n) - 1)], 3),
        "min_ms": round(times[0], 3),
        "max_ms": round(times[-1], 3),
        "binary_bytes": size,
        "note": "the time includes starting the process from Python",
    }, indent=2))


if __name__ == "__main__":
    main()
