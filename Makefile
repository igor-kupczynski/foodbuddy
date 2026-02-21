SHELL := /bin/bash

CASE ?= case-001
EVAL_CASES := $(shell find evals/cases -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort)

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

eval-build: ## Build the AI evals SwiftPM executable.
	cd evals && swift build

eval-run: ## Run all eval cases under evals/cases.
	@if [ -z "$(strip $(EVAL_CASES))" ]; then \
		echo "No eval cases found under evals/cases." >&2; \
		exit 1; \
	fi
	@set -euo pipefail; \
	failures=0; \
	for case_id in $(EVAL_CASES); do \
		echo "==> Running $$case_id"; \
		if ! (cd evals && swift run FoodBuddyAIEvals --case "$$case_id"); then \
			failures=$$((failures + 1)); \
		fi; \
	done; \
	if [ $$failures -gt 0 ]; then \
		echo "eval-run: $$failures case(s) failed." >&2; \
		exit 1; \
	fi

eval-run-case: ## Run one eval case (override with CASE=<case-id>).
	cd evals && swift run FoodBuddyAIEvals --case $(CASE)

eval-case-001: ## Run the default seeded eval fixture case.
	$(MAKE) eval-run-case CASE=case-001

eval-case-002: ## Run the note-only eval fixture case.
	$(MAKE) eval-run-case CASE=case-002
