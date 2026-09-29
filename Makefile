.DEFAULT_GOAL := help
.PHONY: help dev release notarize lint test

help: ## Show this help
	@awk -F':.*## ' '/^[a-z-]+:.*## / {printf "  make %-8s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# Quit any running copy first so the fresh build is the one that launches.
dev: ## Build and relaunch "Emoji Dev.app" (debug, own bundle id and settings)
	scripts/bundle.sh dev
	-pkill -x "Emoji Dev"
	open "Emoji Dev.app"

release: ## Build the signed release "Emoji.app"
	scripts/bundle.sh release

notarize: ## Build, notarize and staple Emoji.app (needs the "emoji" notarytool profile)
	NOTARIZE=1 scripts/bundle.sh release

lint: ## Run SwiftLint (strict)
	swiftlint lint --strict

test: ## Run the test suite
	swift test --disable-sandbox
