# Vorssaint Utils -> macOS 12 Monterey: compatibility report

**Status: analysis only. Nothing has been compiled or run.** Work was started on
Windows 11, which has no Swift/Xcode/macOS SDK, so no macOS build is possible here.
Nothing in this file claims Monterey compatibility.

## Environment (this machine)
Windows 11 Pro, x64, ~1 TB free. No swiftc, xcodebuild, or clang. Required: a Mac
with Xcode 15+ (Package.swift is swift-tools 5.9; Xcode 15 needs macOS 13.5+, so it
cannot run on Monterey itself). Build there with a 12.0 deployment target.

## Upstream facts
- 713 Swift files in Sources/Vorssaint, ~250 test files, GPL-3.0-or-later.
- `Package.swift`: `.macOS(.v14)`; `build.sh`: `TARGET=arm64-apple-macosx14.0`,
  `--minimum-deployment-target 14.0`, pinned to the macOS 26 SDK. Info.plist has `LSMinimumSystemVersion`.
- arm64 is hard-coded in build.sh; no universal build exists.
- TRADEMARKS.md: a fork needs a different name, icon, bundle ID (`com.vorssaint.utils`),
  signing identity and update feed. Not yet changed.

## Post-Monterey APIs found (grep counts, occurrences or files)
| API | Introduced | Where | Plan |
|---|---|---|---|
| `onChange(of:){old,new in}` two-parameter | macOS 14 | ~90 files | add a `View.onChangeCompat` shim, mechanical rewrite |
| `CATapDescription`, `AudioHardwareCreateProcessTap` | 14.2/14.4 | Audio/AppVolumeMixer, Recorder system-audio tap | per-app volume mixer and system-audio recording: disable on 12 |
| `SCScreenshotManager` | 14.0 | 6 uses, QuickTools screenshot/capture | fall back to `CGWindowListCreateImage` / SCStream (12.3) |
| `SMAppService` | 13.0 | 14 uses, LaunchAtLogin, fan helper, others | fall back to login-item helper / LaunchAgent plist |
| `.glassEffect`, `.buttonStyle(.glass)` | 26 | 7 uses | already `#available(26)`-gated; verify |
| `.symbolEffect` | 14 | 15 uses | gate or drop |
| `ContentUnavailableView`, `.onKeyPress`, `TextRenderer`, `Charts`, `ImageRenderer` | 14 / 14 / 15 / 13 / 13 | 2 files each | `Charts` and `ImageRenderer` need 13: replace or disable |
| `.scrollIndicators`, `.formStyle(.grouped)`, `Grid` | 13 | 15 / 22 / 3 | `.formStyle` and `Grid` need compat wrappers |
| `if let x {` shorthand | Swift 5.7 | very widespread | fine with Xcode 14+ toolchain |

Existing `#available` gates: macOS 26 (25), 14.4 (18), 27 (3), 15 (3). Notch UI (notch-based
features), Fan control (Apple Silicon SMC) and HID/IOKit private pieces are Apple Silicon or
newer-hardware specific and need individual review.

## Not yet done
Everything below needs a Mac: shims and rewrites, Package.swift/build.sh/Info.plist target,
rebranding, test run, bundle verification, Monterey runtime test, universal build.
`build-monterey.sh` is a preflight-plus-`swift build` stub, untested.

## Remaining issues
All of them. A blind rewrite of ~700 SwiftUI/AppKit files without a compiler was not attempted.
