SHELL := /bin/bash

CASE ?= case-001
EVAL_CASES := $(shell find evals/cases -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort)
EVAL_BIN_DIR := $(shell cd evals && swift build --show-bin-path)
EVAL_BIN := $(EVAL_BIN_DIR)/FoodBuddyAIEvals
EVAL_SOURCES := $(shell find evals/Sources -type f -name '*.swift' | sort)
SHARED_AI_SOURCES := $(shell find Packages/FoodBuddyAIShared/Sources -type f -name '*.swift' | sort)

.DEFAULT_GOAL := help

.PHONY: help xcodegen launch-screen-guard test-core build-ios build-ios-dev ai-shared-test eval-build eval-run eval-run-case eval-case-001 eval-case-002

help: ## Show available targets and descriptions.
	@awk 'BEGIN {FS = ":.*##"; printf "Usage: make <target>\n\nTargets:\n"} /^[a-zA-Z0-9_.-]+:.*##/ {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

xcodegen: ## Regenerate FoodBuddy.xcodeproj from project.yml.
	xcodegen generate

launch-screen-guard: ## Validate launch screen metadata guardrail.
	./scripts/assert-launch-screen-config.sh

test-core: ## Run fast macOS unit-test verifier (FoodBuddyCoreTests).
	xcodebuild test -project FoodBuddy.xcodeproj -scheme FoodBuddy -destination 'platform=macOS,arch=x86_64'

build-ios: ## Build iOS app target without signing.
	xcodebuild build -project FoodBuddy.xcodeproj -scheme FoodBuddy -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO

build-ios-dev: ## Build local phone dev target without signing.
	xcodebuild build -project FoodBuddy.xcodeproj -scheme FoodBuddyDev -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO

ai-shared-test: ## Run shared AI package tests.
	cd Packages/FoodBuddyAIShared && swift test

$(EVAL_BIN): evals/Package.swift $(EVAL_SOURCES) Packages/FoodBuddyAIShared/Package.swift $(SHARED_AI_SOURCES)
	cd evals && swift build

eval-build: $(EVAL_BIN) ## Build the AI evals SwiftPM executable.

eval-run: $(EVAL_BIN) ## Run all eval cases under evals/cases.
	@if [ -z "$(strip $(EVAL_CASES))" ]; then \
		echo "No eval cases found under evals/cases." >&2; \
		exit 1; \
	fi
	@set -euo pipefail; \
	failures=0; \
	for case_id in $(EVAL_CASES); do \
		echo "==> Running $$case_id"; \
		if ! "$(EVAL_BIN)" --case "$$case_id"; then \
			failures=$$((failures + 1)); \
		fi; \
	done; \
	if [ $$failures -gt 0 ]; then \
		echo "eval-run: $$failures case(s) failed." >&2; \
		exit 1; \
	fi

eval-run-case: $(EVAL_BIN) ## Run one eval case (override with CASE=<case-id>).
	"$(EVAL_BIN)" --case $(CASE)

eval-case-001: ## Run the default seeded eval fixture case.
	$(MAKE) eval-run-case CASE=case-001

eval-case-002: ## Run the note-only eval fixture case.
	$(MAKE) eval-run-case CASE=case-002
