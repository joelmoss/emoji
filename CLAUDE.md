# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

A macOS 14+ menu-bar emoji picker (global hotkey, search, recents, skin tones, Sparkle updates). Swift Package, no Xcode project. README.md covers the one-time release setup (Sparkle keys, notary profile, CI secrets); don't duplicate it here.

## Commands

```
make help       # list targets
make dev        # build + relaunch "Emoji Dev.app" (debug, com.joelmoss.emoji.dev)
make release    # signed Emoji.app (Developer ID), not notarized
make notarize   # notarize + staple app, then build/notarize/staple Emoji-<version>.dmg
make lint       # swiftlint lint --strict (add --no-cache inside Claude Code's sandbox)
make test       # swift test --disable-sandbox
swift test --disable-sandbox --filter VerticalTests   # one suite; a test name (e.g. skinTones) works too
```

- `scripts/bundle.sh dev|release` does the real work; `VERSION`, `BUILD` (default: commit count), `SIGN_ID` (`-` = ad-hoc), `NOTARIZE=1`, `NOTARY_ARGS` are its knobs. `make notarize` needs `xcrun notarytool store-credentials emoji ...` once.
- Regenerate data: `python3 scripts/gen_emojis.py > Sources/Emoji/emojis.json` (reads the checked-in `scripts/emoji-test.txt` and `scripts/cldr-*.json`). Regenerate the icon: `scripts/gen_icon.sh` (needs `brew install librsvg`; commit the `.icns`).
- Under Claude Code's command sandbox, `swift build/test`, `codesign`, `gh` and `git push` need `dangerouslyDisableSandbox` (SwiftPM checkouts write git hooks; SSH and the keychain are blocked).
- SwiftLint runs on `Sources` and `Tests` with default rules. Fix violations by refactoring; don't add disables.

## Architecture

An accessory app (`LSUIElement`), built as a SwiftPM executable and assembled into an `.app` by `scripts/bundle.sh`. Four source files:

- `main.swift`: entry point and `AppDelegate`. Owns the status item and one shared `NSMenu`: it is both the menu-bar menu and what the picker's gear button pops up (`picker.menu`), and `menuNeedsUpdate` hides "Show Picker" while the picker is open. Registers the global hotkey (KeyboardShortcuts package) and hosts the Sparkle updater. `Variant.isDev` (bundle id ends in `.dev`) switches the default shortcut, the icon badge and turns Sparkle off.
- `Picker.swift`: `PickerPanel` is a borderless, non-activating `NSPanel` (so the target app keeps focus) that closes on `resignKey`, except while the settings menu is open. `PickerModel` (`@Observable`) holds the sections (Recents + categories, or one flat search result section), the selection as `Pos(section, index)`, and cross-section arrow navigation. `PickerView` is SwiftUI: a `LazyVGrid` under glass search and footer bars (`safeAreaInset`, Liquid Glass on macOS 26+, material before). `PickerController` keeps a single panel alive and just shows/hides it, which is what makes it fast.
- `Paste.swift`: puts the emoji on the pasteboard, posts a synthetic ⌘V (`CGEvent`, needs Accessibility), then restores the old clipboard.
- `Emoji.swift`: `EmojiStore` loads `emojis.json`, search is a word-prefix match against a precomputed lowercase, accent-folded haystack, `Recents` and `SkinTone` are `UserDefaults`. The skin tone is one global preference, not per emoji; recents store the base character.

Data flow: `emojis.json` is generated (Unicode `emoji-test.txt` + CLDR keywords) and committed. Fully-qualified emoji only; uniform skin-tone sequences are folded into their base emoji as `t`.

Dev and release builds are isolated by bundle id: separate Accessibility grants, `UserDefaults`, and default shortcut (release ⌥⇧Space, dev ⌃⌥⇧Space).

## Gotchas that cost time before

- **Resource bundles.** Always build with `--build-system swiftbuild` (already in `bundle.sh`). Older SwiftPM backends generate a `Bundle.module` lookup that only checks the `.app` root and the build machine's `.build` path, so the shipped app aborts on launch anywhere else. `bundle.sh` fails the build if the binary contains a hardcoded `.build/*.bundle` path. Resource bundles go in `Contents/Resources`, never the `.app` root (`codesign` rejects it).
- **Launch smoke test.** `bundle.sh` runs the signed app once with `EMOJI_SMOKE_TEST=1`; `applicationDidFinishLaunching` exits 0 after building the menu. Skipped for ad-hoc builds (hardened runtime won't load an equally ad-hoc Sparkle). Any launch-time crash fails the release before it is published.
- **Window activation.** `NSApp.activate()` is cooperative on macOS 14+ and is declined while another app is frontmost; windows then never become key. Use `activate(ignoringOtherApps: true)`.
- **Signing.** Sparkle's XPC services are removed (app is unsandboxed) and its nested code is signed inside out before the app. Identities are hardcoded in `bundle.sh` (`SIGN_ID` overrides). CI's `check` job builds ad-hoc, so it skips the smoke test but still runs the resource-path guard.
- **Accessibility grant** is tied to bundle id plus the Developer ID requirement, so it survives updates. A stale entry from an old ad-hoc build makes Settings show "on" while macOS refuses: `tccutil reset Accessibility com.joelmoss.emoji`.
- **Shortcut menu presets** avoid ⌘Space, ⌃Space, ⌃⌥Space (input sources) and ⌘⌥Space, which macOS owns. The recorder window (`Custom…`) exists because a menu's tracking loop swallows recorded keystrokes.

## Releases

`vX.Y.Z` tag → `Release` workflow builds, signs, notarizes and makes a **draft** with `Emoji-X.Y.Z.dmg`. Rewrite the draft's notes into user-facing highlights (they are the Sparkle update dialog), then publish: the `Appcast` workflow builds the signed `appcast.xml` from the DMG and the release body. The app reads `releases/latest/download/appcast.xml`. The build number is the commit count (`fetch-depth: 0`), and Sparkle compares that, not the version string. `ponytail:` comments mark deliberate shortcuts and their upgrade paths.
