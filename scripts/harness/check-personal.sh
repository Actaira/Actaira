#!/usr/bin/env bash
# Fails if what this branch publishes holds personal data of Marcos (CLAUDE.md,
# rule 4: the repos are public; F-0015). It scans:
#   - the tracked files and the untracked files that are not ignored, contents
#     and paths;
#   - the staged changes (lines added to the index);
#   - the commits of the branch (origin/main..HEAD, or all of HEAD when there
#     is no origin/main): the lines they add, their messages and their author
#     and committer names. main is not scanned again: a finding there could
#     never be removed without rewriting main (F-0009).
# It looks for:
#   - the terms of Marcos's private list, which lives outside git on purpose
#     (~/actaira-ws/privado/datos-personales.txt, "category | term" per line;
#     publishing even their hashes would let anyone test guesses). A term
#     matches whole words, ignoring case and accents, across punctuation and
#     line breaks. The CI has no private list: there the terms are skipped,
#     and the output says so; everywhere else a missing list fails.
#   - e-mail addresses at personal providers, outside testdata/ (fixtures of
#     analysed repos) and outside commit identities (contributors sign with
#     their own address).
# A finding names the category and the place, never the text: the CI logs of
# a public repo are public too.
# With --files, only the given files are scanned (merge-pr.sh: the squash
# message and the PR text, which enter main or GitHub without CI).
# Usage: scripts/harness/check-personal.sh [--terms <file>] [--files <file>...]
set -euo pipefail
terms="${HOME:-}/actaira-ws/privado/datos-personales.txt"
if [ "${1:-}" = "--terms" ]; then
  terms="${2:?falta el fichero tras --terms}"
  shift 2
fi
files=()
if [ "${1:-}" = "--files" ]; then
  shift
  files=("$@")
  [ "${#files[@]}" -gt 0 ] || { echo "check-personal: --files sin ficheros" >&2; exit 2; }
else
  cd "$(git rev-parse --show-toplevel)"
fi
if [ ! -f "$terms" ]; then
  if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    echo "check-personal: la CI no tiene la lista privada de términos; solo busca correos (los términos se comprueban en local)"
    terms=""
  else
    echo "check-personal: falta la lista privada de términos ($terms)" >&2
    exit 1
  fi
fi

python3 - "$terms" "${files[@]}" <<'PYEOF'
import bisect
import codecs
import os
import re
import subprocess
import sys
import unicodedata

EMAIL = re.compile(
    r"[A-Za-z0-9._%+-]+@(?:gmail|googlemail|hotmail|outlook|live|msn|yahoo|ymail|icloud|me|proton|protonmail|pm|gmx)\.[A-Za-z]{2,}",
    re.IGNORECASE,
)


def normalize(text):
    """Lowercase, no accents, no invisible format characters (zero-width space...)."""
    text = unicodedata.normalize("NFKD", text.lower())
    return "".join(c for c in text if not unicodedata.combining(c) and unicodedata.category(c) != "Cf")


def words(text):
    return [(m.group(), m.start()) for m in re.finditer(r"[a-z0-9]+", text)]


terms = {}
for line in (open(sys.argv[1], encoding="utf-8") if sys.argv[1] else []):
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    category, _, term = line.partition("|")
    key = tuple(w for w, _ in words(normalize(term)))
    if key:
        terms[key] = category.strip()
max_words = max((len(k) for k in terms), default=0)


def findings_in(text, emails=True):
    """(category, line) for each term and personal address in text."""
    found = []
    if emails:
        for m in EMAIL.finditer(text):
            found.append(("correo de un proveedor personal", text.count("\n", 0, m.start()) + 1))
    if terms:
        norm = normalize(text)
        newlines = [i for i, c in enumerate(norm) if c == "\n"]
        toks = words(norm)
        for i in range(len(toks)):
            for k in range(1, min(max_words, len(toks) - i) + 1):
                category = terms.get(tuple(w for w, _ in toks[i:i + k]))
                if category:
                    found.append((f"dato personal ({category})", bisect.bisect_left(newlines, toks[i][1]) + 1))
    return found


def decode(data):
    """Text of a file: UTF-16 with a BOM, UTF-8, or cp1252 as a last resort."""
    for bom, enc in ((codecs.BOM_UTF16_LE, "utf-16"), (codecs.BOM_UTF16_BE, "utf-16")):
        if data.startswith(bom):
            return data.decode(enc, "replace")
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return data.decode("cp1252", "replace")


def git(*args):
    return subprocess.run(["git", *args], stdout=subprocess.PIPE, check=True).stdout


bad = []
if len(sys.argv) > 2:
    for path in sys.argv[2:]:
        for what, line in findings_in(decode(open(path, "rb").read())):
            bad.append(f"{what} en {os.path.basename(path)}:{line}")
    for b in bad:
        print(f"check-personal: {b}", file=sys.stderr)
    raise SystemExit(1 if bad else 0)

for raw in git("ls-files", "-z", "--cached", "--others", "--exclude-standard").split(b"\0"):
    if not raw:
        continue
    path = raw.decode("utf-8", "surrogateescape")
    for what, _ in findings_in(path.replace("/", " / ")):
        bad.append(f"{what} en el nombre de {path}")
    if not os.path.isfile(path) or os.path.islink(path):
        continue
    data = open(path, "rb").read()
    text = decode(data)
    if "\0" in text:
        continue
    fixture = path.startswith("testdata/") or "/testdata/" in path
    for what, line in findings_in(text, emails=not fixture):
        bad.append(f"{what} en {path}:{line}")


def added_lines(patch):
    return "\n".join(l[1:] for l in patch.splitlines() if l.startswith("+") and not l.startswith("+++"))


for what, _ in findings_in(added_lines(git("diff", "--cached", "--no-color").decode("utf-8", "replace"))):
    bad.append(f"{what} en el índice")

if subprocess.run(["git", "rev-parse", "-q", "--verify", "HEAD"], stdout=subprocess.PIPE).returncode == 0:
    has_main = subprocess.run(["git", "rev-parse", "-q", "--verify", "refs/remotes/origin/main"],
                              stdout=subprocess.PIPE).returncode == 0
    rng = "refs/remotes/origin/main..HEAD" if has_main else "HEAD"
    for sha in git("rev-list", rng).decode().split():
        short = sha[:7]
        who = git("log", "-1", "--format=%an%n%ae%n%cn%n%ce", sha).decode("utf-8", "replace")
        msg = git("log", "-1", "--format=%B", sha).decode("utf-8", "replace")
        patch = git("show", "--format=", "--no-color", sha).decode("utf-8", "replace")
        found = {w for w, _ in findings_in(who, emails=False)}
        found |= {w for w, _ in findings_in(msg)}
        found |= {w for w, _ in findings_in(added_lines(patch))}
        for what in sorted(found):
            bad.append(f"{what} en el commit {short} (mensaje, autor o líneas que añade)")

for b in bad:
    print(f"check-personal: {b}", file=sys.stderr)
raise SystemExit(1 if bad else 0)
PYEOF
