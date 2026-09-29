#!/usr/bin/env bash
# Tests for scripts/harness/fetch-tool.sh (pinned downloads with checksum).
source "$(dirname "$0")/lib.sh"

# make_archive: a local release archive served through file://, so the test needs no network.
make_archive() {
  mkdir -p "$T/src"
  printf '#!/bin/sh\necho fake-tool\n' > "$T/src/tool"
  chmod +x "$T/src/tool"
  tar -czf "$T/tool.tar.gz" -C "$T/src" tool
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

test_installs_when_checksum_matches() {
  make_archive
  "$HARNESS_DIR/fetch-tool.sh" "file://$T/tool.tar.gz" "$(sha256_of "$T/tool.tar.gz")" tool "$T/bin/tool"
  assert_eq "$("$T/bin/tool")" "fake-tool" "herramienta instalada"
}

test_refuses_when_checksum_differs() {
  make_archive
  local out rc=0
  out="$("$HARNESS_DIR/fetch-tool.sh" "file://$T/tool.tar.gz" \
    0000000000000000000000000000000000000000000000000000000000000000 tool "$T/bin/tool" 2>&1)" || rc=$?
  assert_eq "$rc" "1" "exit con checksum distinto"
  assert_contains "$out" "checksum distinto"
  [ ! -e "$T/bin/tool" ] || fail "no debe instalar nada con checksum distinto"
}

test_refuses_without_pinned_checksum() {
  make_archive
  local rc=0
  "$HARNESS_DIR/fetch-tool.sh" "file://$T/tool.tar.gz" "" tool "$T/bin/tool" 2>/dev/null || rc=$?
  assert_eq "$rc" "1" "exit sin checksum fijado"
  [ ! -e "$T/bin/tool" ] || fail "no debe instalar nada sin checksum"
}

# A stuck download must not hang `make check` until the Stop hook's 540 s
# timeout or the CI job limit: the download has retries and time limits.
test_download_has_retries_and_time_limits() {
  local line
  line="$(grep -E '^[[:space:]]*curl ' "$HARNESS_DIR/fetch-tool.sh")"
  [ -n "$line" ] || fail "fetch-tool.sh no tiene una línea curl"
  assert_contains "$line" "--retry " "curl con --retry"
  assert_contains "$line" "--connect-timeout " "curl con --connect-timeout"
  assert_contains "$line" "--max-time " "curl con --max-time"
}

run_tests "$@"
