# Actaira build gates.
#   make check  fast gate: every step, the Stop hook and the CI `check` job.
#   make gate   check + step evals + quick e2e, before every PR.
# Never weaken a recipe: scripts/harness/check-weakeners.sh (part of check)
# rejects `|| true`, `-` prefixes, -i/-k, .IGNORE and friends.

SHELL := bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := check
.DELETE_ON_ERROR:

TOOLS_DIR := .tools

# gitleaks, pinned by version and sha256 (from gitleaks_<version>_checksums.txt
# of the official release: https://github.com/gitleaks/gitleaks/releases).
GITLEAKS_VERSION := 8.30.1
GITLEAKS_SHA256_linux_x64    := 551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb
GITLEAKS_SHA256_linux_arm64  := e4a487ee7ccd7d3a7f7ec08657610aa3606637dab924210b3aee62570fb4b080
GITLEAKS_SHA256_darwin_x64   := dfe101a4db2255fc85120ac7f3d25e4342c3c20cf749f2c20a18081af1952709
GITLEAKS_SHA256_darwin_arm64 := b40ab0ae55c505963e365f271a8d3846efbc170aa17f2607f13df610a9aeb6a5

HOST_OS   := $(shell uname -s | tr '[:upper:]' '[:lower:]')
HOST_ARCH := $(patsubst x86_64,x64,$(patsubst amd64,x64,$(patsubst aarch64,arm64,$(shell uname -m))))
GITLEAKS_PLATFORM := $(HOST_OS)_$(HOST_ARCH)
GITLEAKS := $(TOOLS_DIR)/gitleaks-$(GITLEAKS_VERSION)
# golangci-lint, pinned by version and sha256 (from golangci-lint-<version>-checksums.txt
# of the official release: https://github.com/golangci/golangci-lint/releases),
# with the config in .golangci.yml. Built with go1.27.0, so it reads this module.
# --config: only the pinned .golangci.yml counts (a .golangci.yaml, .toml or
# .json next to it would take precedence). --allow-serial-runners: runs that
# overlap (the Stop hook and a reviewer's clone) wait for the lock instead of
# failing.
GOLANGCI_LINT_VERSION := 2.14.0
GOLANGCI_LINT_SHA256_linux_amd64  := ab90aeb7b066f92a33415b638a50fe5344bbb75a0d32ad30cc248d88f81032ab
GOLANGCI_LINT_SHA256_linux_arm64  := ee7ec5f3453d15ddf106fae5a4d6c71737712348a979d1fe9cd52ec7ea299bae
GOLANGCI_LINT_SHA256_darwin_amd64 := a5667c1c3536be1740133213e1e822bfb8f0d98ea12903174d6d5f635e4ed68d
GOLANGCI_LINT_SHA256_darwin_arm64 := 5ef5f36a7147e91dc58ef9ef4d11bb7bad5ead0c76eb6c01327a73c641d1dcc3
GOLANGCI_LINT_OS_ARCH := $(HOST_OS)_$(patsubst x64,amd64,$(HOST_ARCH))
GOLANGCI_LINT_PLATFORM := $(subst _,-,$(GOLANGCI_LINT_OS_ARCH))
GOLANGCI_LINT := $(TOOLS_DIR)/golangci-lint-$(GOLANGCI_LINT_VERSION)

# Exported so every recipe runs the harness tests with the same environment:
# test-harness and check-fallos execute the same guards (F-0003).
export GITLEAKS

# GOFLAGS can filter or skip tests (-run, -short) without touching a recipe.
unexport GOFLAGS

# Go sources to format-check: skips hidden dirs (.git, .tools, .claude worktrees)
# and testdata, which may hold deliberately malformed fixtures.
GO_SOURCES := find . -path './.*' -prune -o -path '*/testdata' -prune -o -type f -name '*.go' -print

HARNESS_SCRIPTS := scripts/harness/*.sh scripts/harness/tests/*.sh scripts/harness/pre-push scripts/harness/commit-msg

.PHONY: check gate fmt-check lint test test-harness determinism secrets weakeners pipes fallos skips attribution personal \
	evals-paso e2e-rapido e2e-completo install-hooks tools

check: weakeners pipes fallos skips attribution personal fmt-check lint test determinism test-harness secrets
	@echo "check: OK"

gate: check evals-paso e2e-rapido
	@echo "gate: OK"

fmt-check:
	@files="$$($(GO_SOURCES))"; \
	if [ -n "$$files" ]; then \
	  bad="$$(gofmt -l $$files)"; \
	  if [ -n "$$bad" ]; then echo "gofmt: ficheros sin formatear:"; echo "$$bad"; exit 1; fi; \
	fi

lint: $(GOLANGCI_LINT)
	go vet ./...
	$(GOLANGCI_LINT) run --config .golangci.yml --allow-serial-runners ./...
	@for f in $(HARNESS_SCRIPTS); do bash -n "$$f"; done

test:
	@if [ -n "$$(go env GOFLAGS)" ]; then echo "GOFLAGS no vacío ($$(go env GOFLAGS)): puede filtrar o saltar tests. Quítalo con go env -u GOFLAGS"; exit 1; fi
	go test -count=1 -shuffle=on ./...

determinism:
	@echo "determinism: sin prueba de determinismo todavía (llega en E1 con actaira.lock)"

test-harness: $(GITLEAKS) $(GOLANGCI_LINT)
	bash scripts/harness/tests/run.sh

secrets: $(GITLEAKS)
	scripts/harness/secrets-scan.sh "$(GITLEAKS)"

weakeners:
	scripts/harness/check-weakeners.sh

pipes:
	scripts/harness/check-pipes.sh

fallos: $(GITLEAKS)
	scripts/harness/check-fallos.sh

skips:
	scripts/harness/check-skips.sh

attribution:
	scripts/harness/check-attribution.sh

# Nothing personal in the repo (CLAUDE.md, rule 4; F-0015).
personal:
	scripts/harness/check-personal.sh

evals-paso:
	@echo "evals-paso: sin evals todavía"

e2e-rapido:
	@echo "e2e-rapido: sin e2e todavía"

e2e-completo:
	@echo "e2e-completo: sin e2e todavía"

install-hooks:
	for name in pre-push commit-msg; do \
	  hook="$$(git rev-parse --path-format=absolute --git-path "hooks/$$name")"; \
	  mkdir -p "$$(dirname "$$hook")"; \
	  cp "scripts/harness/$$name" "$$hook"; \
	  chmod +x "$$hook"; \
	  echo "$$name instalado en $$hook"; \
	done

tools: $(GITLEAKS) $(GOLANGCI_LINT)

$(GITLEAKS):
	scripts/harness/fetch-tool.sh \
	  "https://github.com/gitleaks/gitleaks/releases/download/v$(GITLEAKS_VERSION)/gitleaks_$(GITLEAKS_VERSION)_$(GITLEAKS_PLATFORM).tar.gz" \
	  "$(GITLEAKS_SHA256_$(GITLEAKS_PLATFORM))" gitleaks "$@"

$(GOLANGCI_LINT):
	scripts/harness/fetch-tool.sh \
	  "https://github.com/golangci/golangci-lint/releases/download/v$(GOLANGCI_LINT_VERSION)/golangci-lint-$(GOLANGCI_LINT_VERSION)-$(GOLANGCI_LINT_PLATFORM).tar.gz" \
	  "$(GOLANGCI_LINT_SHA256_$(GOLANGCI_LINT_OS_ARCH))" \
	  "golangci-lint-$(GOLANGCI_LINT_VERSION)-$(GOLANGCI_LINT_PLATFORM)/golangci-lint" "$@"

# print-<VAR>: the value of a variable, for the harness tests (make 3.81, the
# one of macOS, has no --eval).
print-%:
	@echo '$($*)'
