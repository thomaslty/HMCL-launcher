# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
swift test                                  # 42 tests, no network
swift test --filter LauncherInstallerTests  # one suite
swift build                                 # library + executable only
./scripts/build-app.sh                      # build/HMCL Launcher.app, ad-hoc signed
./scripts/make-dmg.sh                       # dist/HMCL-Launcher-<version>.dmg
swift scripts/make-icon.swift               # regenerate Resources/AppIcon.icns
```

The live check downloads ~136 MB and starts a real HMCL process, so it is gated:

```bash
HMCL_INTEGRATION=1 swift test --filter EndToEnd
```

There is no Xcode project. `scripts/build-app.sh` assembles the `.app` by hand from the SwiftPM product plus `Resources/Info.plist`.

## Layout

- `Sources/LauncherKit/` — every decision, no UI, fully tested
- `Sources/HMCLLauncher/` — SwiftUI app, thin orchestration over LauncherKit
- `Tests/LauncherKitTests/` — swift-testing (`import Testing`, `@Test`, `#expect`), not XCTest

## Architecture

Cold start is one chain: `GitHubReleaseClient` → `LauncherInstaller` → `LibericaClient` → `RuntimeInstaller` → `HMCLLaunchService`. `LauncherViewModel` drives that chain and owns all UI state; the views hold none.

Two protocols are the only seams to the outside world, and everything is tested through them:

- `HTTPFetching` — JSON API calls, stubbed by `StubFetcher` in tests
- `FileDownloading` — large file downloads, stubbed by copying a fixture

`Workspace` resolves every path under `~/Library/Application Support/net.tlau.HMCLLauncher/`. Nothing in this codebase may write outside it, and `WorkspaceTests.everyPathLivesUnderTheRoot` enforces that.

## Constraints that are load-bearing

These were established by pulling `HMCL-3.16.3.jar` apart and testing against it. Changing them silently breaks the product.

- The runtime must be a Liberica **`jre-full`** build. HMCL's UI is JavaFX; a stock JRE has none, and HMCL's fallback is to download OpenJFX and module-patch it at startup, which is the most reported macOS failure. `EndToEndTests` asserts on HMCL's `JavaFX Version` log line for exactly this reason.
- Java home is **resolved by looking for `bin/java`**, never assumed. Liberica's macOS tarball unpacks flat (`jre-25.0.4-full.jre/bin/java`), other vendors ship `Contents/Home`.
- BellSoft publishes **SHA-1** only, so that is what `Checksum` verifies. GitHub publishes no checksum for HMCL jars at all.
- The launch attaches **no pipes**. stdout and stderr go to a file so the child outlives this app. Adding a pipe to feed the log pane would kill HMCL when the window closes.
- The working directory is the **user's home**. HMCL resolves its game directory as `.minecraft` relative to it, so this is what keeps saves in `~/.minecraft` instead of inside the workspace.
- App Sandbox must stay **off**. A sandbox is inherited by child processes and would follow HMCL into the game.

## Screenshots

`screencapture` needs Screen Recording permission that a build machine will not have, so the app renders its own views into an offscreen `NSWindow`:

```bash
"build/HMCL Launcher.app/Contents/MacOS/HMCLLauncher" --render-screenshots /tmp/shots [--live]
```

`ImageRenderer` cannot rasterize AppKit-backed controls (pickers, borderless buttons come out blank) — do not switch back to it. For the same reason the log pane uses `VStack`, not `LazyVStack`: lazy containers draw nothing offscreen.

Do not use AppKit's `.switch` toggle style. NSSwitch positions its knob where neither `cacheDisplay` nor `layer.render(in:)` can photograph it, so an enabled switch renders as disabled and the screenshot lies. Use `MossSwitchStyle` in `DesignTokens.swift`, which is drawn from SwiftUI shapes.

## Releasing

Bump all three in the same commit, then tag:

- `Resources/Info.plist` → `CFBundleShortVersionString`
- `Resources/Info.plist` → `CFBundleVersion`
- `Sources/LauncherKit/LauncherKit.swift` → `AppIdentity.version`

The README carries no version — Quick start links to Releases and `make-dmg.sh` reads the plist — so there is nothing to change there.

The two plist keys must hold the **same** value. macOS shows `Version 1.0.1 (1)` in the About window whenever they differ, and that trailing build number is not wanted.

```bash
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 1.0.2" \
                        -c "Set :CFBundleVersion 1.0.2" Resources/Info.plist
```

Pushing a `v*` tag is what publishes the release; `.github/workflows/release.yml` builds the DMG and attaches it. Wait for the master run to go green before tagging, so a broken build never produces a release.

## Workflow

`openspec/` is gitignored; the change lives in `openspec/changes/add-hmcl-launcher/`. Run `openspec validate <change>` after editing its artifacts.
