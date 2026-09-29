.DEFAULT_GOAL := help
.PHONY: help build run lint test

help: ## Show this help
	@awk -F':.*## ' '/^[a-z-]+:.*## / {printf "  make %-6s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

build: ## Build and sign Emoji.app
	scripts/bundle.sh

# Quit any running copy first so the fresh build is the one that launches.
run: build ## Build, then relaunch Emoji.app
	-pkill -x Emoji
	open Emoji.app

lint: ## Run SwiftLint (strict)
	swiftlint lint --strict

test: ## Run the test suite
	swift test --disable-sandbox
