SHELL := /bin/bash

CASE ?= case-001

.PHONY: xcodegen launch-screen-guard test-core build-ios build-ios-dev ai-shared-test eval-build eval-run eval-case-001

xcodegen:
	xcodegen generate

launch-screen-guard:
	./scripts/assert-launch-screen-config.sh

test-core:
	xcodebuild test -project FoodBuddy.xcodeproj -scheme FoodBuddy -destination 'platform=macOS,arch=x86_64'

build-ios:
	xcodebuild build -project FoodBuddy.xcodeproj -scheme FoodBuddy -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO

build-ios-dev:
	xcodebuild build -project FoodBuddy.xcodeproj -scheme FoodBuddyDev -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO

ai-shared-test:
	cd Packages/FoodBuddyAIShared && swift test

eval-build:
	cd evals && swift build

eval-run:
	cd evals && swift run FoodBuddyAIEvals --case $(CASE)

eval-case-001:
	$(MAKE) eval-run CASE=case-001
