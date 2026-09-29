# Sourced by the harness scripts (not executed): which failures are recorded
# in docs/harness/FALLOS.md, and whether a piece of text cites one of them.
# Used wherever an exception that switches a check off must be justified (L-003).

# fallos_ids [file]: ids recorded in FALLOS.md (entries after "## Entradas",
# outside fenced code blocks), one per line. Nothing if the file is missing.
fallos_ids() {
  local f="${1:-docs/harness/FALLOS.md}"
  if [ -f "$f" ]; then
    awk '/^## Entradas/ {p = 1; next}
         p && /^```/ {c = !c; next}
         p && !c && /^## F-[0-9][0-9][0-9][0-9]/ {print $2}' "$f"
  fi
}

# cites_known_fallo <text> <known ids>: true if <text> cites at least one of
# the recorded ids (as printed by fallos_ids).
cites_known_fallo() {
  local id
  for id in $(awk '{ while (match($0, /F-[0-9][0-9][0-9][0-9]/)) { print substr($0, RSTART, RLENGTH); $0 = substr($0, RSTART + RLENGTH) } }' <<< "$1"); do
    if grep -qxF -- "$id" <<< "$2"; then return 0; fi
  done
  return 1
}
