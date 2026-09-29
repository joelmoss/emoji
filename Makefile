.PHONY: build run lint

build:
	scripts/bundle.sh

# Quit any running copy first so the fresh build is the one that launches.
run: build
	-pkill -x Emoji
	open Emoji.app

lint:
	swiftlint lint --strict
