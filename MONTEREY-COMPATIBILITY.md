# Unupunct MacTab: macOS 12 (Monterey) compatibility report

Unupunct MacTab is an **unofficial** port of [Vorssaint Utils](https://github.com/vorssaint/vorssaint-utils)
(upstream release 3.4.3, GPL-3.0-or-later) to macOS 12 Monterey on Intel Macs. It is not made, endorsed
or supported by the upstream project. See [TRADEMARKS.md](TRADEMARKS.md) for why the name, icon, bundle
identifier and update behaviour differ.

## What was actually done, and on what

| | |
|---|---|
| Built on | MacBook Air, **macOS 12.7.6 (21H1320), x86_64** (the same Mac the app was run on) |
| Compiler / SDK | Apple Swift 5.7.2 (Command Line Tools only, **no Xcode**), macOS SDK 13.1 |
| Deployment target | **macOS 12.3** (`x86_64-apple-macosx12.3`); the executable's `minos` is 12.3 |
| Architecture | The main download is **x86_64**. A second, **universal** download adds an arm64 slice that was cross-compiled on this Intel Mac and **never run**. |
| Signing | ad-hoc (`codesign --sign -`). Not Developer ID signed, **not notarized**. |
| Build command | `./build-monterey.sh` (run on the Mac; log in `build/build-monterey.log`) |

Xcode 14.2 is the newest Xcode that runs on Monterey and Xcode 15+ needs macOS 13.5, so a Monterey Mac
builds with the Command Line Tools' Swift 5.7. Upstream targets Swift 5.9+; most of the source changes
below exist because of that older compiler as well as the older OS.

## Test results (honest summary)

| Check | Result |
|---|---|
| App compiles and links for macOS 12.3 | yes (714 Swift files, 0 errors) |
| Fan-control helper compiles; its own `--selftest` | yes / `fan-control-helper: ok` (it is **not** bundled, see below) |
| Now Playing adapter (`libUnupunctMacTabNowPlaying.dylib`) compiles | yes |
| App launches on macOS 12.7.6 and keeps running | yes (observed running for the duration of the checks, no crash report) |
| App's built-in `--selftest` on macOS 12.7.6 | **`SELFTEST OK`**, with 5 warnings (below) |
| Settings window renders on macOS 12.7.6 | see the screenshots in the README (captured from the running app) |
| Individual features exercised by hand | **no**. Only startup, the self-test and the Settings pages in the screenshots were looked at. |
| Upstream unit tests (`Tests/`, about 250 files) | **not run.** The upstream harness (`build.sh --test`) was not ported. |
| Apple Silicon | not built, not run |
| Any macOS other than 12.7.6 | not run |

The 5 self-test warnings, all on this Mac: no SMC temperature keys (hardware); four menu-bar icon choices
from newer SF Symbols (`mountain.2.fill`, `gauge.with.dots.needle.67percent`, `cat.fill` do not exist on
macOS 12, `cloud.fill` touches its canvas edge). Choosing one of the missing symbols falls back to the
app's own icon, which is the behaviour upstream's self-test describes.

## Added by this port (releases monterey.2 and monterey.3)

New code, not in upstream, and **tested only by looking at it on the one Mac**: the panel's Screenshot, Send to and Clean
buttons; the Clean window with the app uninstaller and the Large files finder; Send to; app volume for Music, Spotify and
VLC through AppleScript; Intel SMC temperature keys (`TC…`, `TG…`); a LAN tile that replaces the GPU temperature where a
Mac has none; a keep-the-panel-below-the-menu-bar guard (macOS 12 grew the panel upward and cut off its top); the first-run
"Everything" choice. Added in monterey.3: the installed-apps list in the uninstaller (sizes, last opened from Spotlight, batch review), large files with your own folders / oldest-first sort / duplicate finder, an Exclusions tab, a monthly clean schedule, optional unticked caches for Slack, Discord, Teams, Spotify and Steam, and a "left in place" list after cleaning. All four Clean-window tabs were opened and used by hand on the one Mac and worked; not every path was exercised (uninstalling several apps in a row, the monthly schedule firing, trashing duplicates, the app-cache paths on a Mac that has those apps).
Seen working in screenshots: the panel layout, the volume sliders, the CPU temperature and the Send to
button. Not exercised: sending files, removing files from the Large files list, running the cleaner, the per-app sliders
(none of those apps was open), and the first-run flow end to end (one run ended with only 7 tools installed and the cause is
unknown; if it happens, use Settings > Features > Install all).

## Features disabled or reduced on Monterey (and why)

These are switched off in code, not left looking functional:

| Feature | On macOS 12 | Why |
|---|---|---|
| Fan control | unavailable; the helper is neither bundled nor installed | needs a privileged helper registered with `SMAppService` daemons (macOS 13). The helper also refuses to run before macOS 13, because it cannot enforce the caller's code-signing requirement there. |
| Per-app volume mixer | hidden (`isAvailable` is false) | Core Audio process taps, macOS 14.2 |
| Notch live-equalizer / audio level bars | hidden | process taps, macOS 14.2 |
| Recording the Mac's sound (screen recorder) | toggle replaced by a note; microphone recording still offered | ScreenCaptureKit audio (macOS 13) / process taps (14.2) |
| Launch at login | works through a per-user LaunchAgent plist instead of `SMAppService` | `SMAppService.mainApp` needs macOS 13 |
| Self-update | **no update feed**: it never checks for, downloads or installs updates | the port has no release feed of its own; the state stays idle and does not claim "up to date" |

Degraded but still present (visual or minor behaviour):
- `ViewThatFits` shows the most compact option; `Grid`/`GridRow` become stacked rows without column
  alignment; the Settings split view is a plain sidebar plus detail; the wrapping "flow" layout is an adaptive
  grid. Layouts can look different from upstream.
- No scroll-indicator hiding, no `scrollDisabled`, no hidden scroll background, no `blurReplace`/numeric/symbol
  content transitions, no SF Symbol effects (bounce, variable colour) on macOS 12.
- Markdown task-list checkboxes in the scratchpad preview are not clickable.
- `userPreferredCamera` / Continuity Camera are not persisted or discovered.
- Language and region only for the clock/week-start locale (no `Locale.Components`).
- Display-link animations use a timer at the screen's refresh rate (not vsync-locked).
- Keyboard focus effects (macOS 14) are not removed; two controls that used key-press handlers are mouse-only.
- Some SwiftUI animations (`.smooth`, `.snappy`, `.bounce`, `.spring(duration:bounce:)`) are approximated with springs.

## Post-Monterey APIs replaced (selection)

The full set is in `Sources/UnupunctMacTab/Support/` (`MontereyCompat.swift`, `AppServiceCompat.swift`,
`DisplayLinkCompat.swift`, `ScreenshotCompat.swift`, `SwiftUICompat.swift`) plus
`Sources/MontereyCompat/Bridging.h`.

| API (introduced) | Replacement |
|---|---|
| `SMAppService` (13) | `AppServiceCompat`: LaunchAgent for the login item; daemons report not found |
| `NSXPCConnection.setCodeSigningRequirement` (13) | guarded; helper refuses to run |
| `SCScreenshotManager` (14) | `SCScreenshotCompat`: one-frame `SCStream` grab (12.3+) |
| `SCStream` audio, mic, presenter overlay config (13/14) | gated with `#available` |
| `CADisplayLink` on `NSView`/`NSScreen` (14) | `DisplayLinkCompat` timer |
| `onChange(of:initial:_:)` and two-argument `onChange` (14) | overloads in `MontereyCompat.swift` (about 360 call sites unchanged) |
| `NSHostingController.sizingOptions` (13) | `setPreferredContentSizing` |
| `NSRunningApplication.activate(from:)`, cooperative activation (14) | `activateCompat` |
| Core Audio process taps (14.2) | gated behind `#if compiler(>=5.9)` and `#available`; stub tap that reports none |
| `Duration`, `ContinuousClock`, `Task.sleep(for:)` (13) | `TimeInterval` and `Task.sleepCompat` |
| `MainActor.assumeIsolated` (14) | `MainActorCompat.assumeIsolated` |
| `ViewThatFits`, `Grid`, `LabeledContent`, `NavigationSplitView`, `AnyLayout`, `Layout` (13) | same-named shadow types or helpers in `SwiftUICompat.swift` |
| `UnevenRoundedRectangle`, `ContentUnavailableView` (13/17) | small shape/view replacements |
| `.formStyle(.grouped)`, `.scrollIndicators`, `.contentTransition`, `.tracking`, `.fontWeight`, ... (13) | `…Compat` modifiers: real call on 13+, no-op on 12 |
| `onContinuousHover`, `onTapGesture { location }`, `dropDestination(for:)` (13) | tracking-area / drag-gesture / `onDrop` equivalents |
| `NSSharingServicePicker.standardShareMenuItem` (13) | sharing-service submenu |
| Calendar `requestFullAccessToEvents`, `NSCalendarsFullAccessUsageDescription` (14) | `requestAccess(to: .event)` and `NSCalendarsUsageDescription` added to Info.plist |
| Swift 5.9 `if`/`switch` expressions, `nonisolated(unsafe)`, `any Sendable` dictionary | rewritten with explicit `return`s / `#if compiler` |
| Large result-builder bodies (10+ children) and long `String + String` chains | wrapped in `Group`s, split into functions, rewritten as interpolation (Swift 5.7 cannot type-check them) |

## Fork identity (TRADEMARKS.md)

- Name **Unupunct MacTab**, bundle id `local.unupunct.mactab`, executable `UnupunctMacTab`.
- Own app and menu-bar icon (generated by `Tools/MakeMontereyIcon.swift`), sharing nothing with the upstream artwork.
- Signing: ad-hoc only. No upstream signing identity is used.
- Update feed: none (see above). Feedback and the temporary screenshot/recording share links are pointed at a reserved,
  never-resolving address instead of upstream's servers, and the Feedback card and donation buttons are hidden, so
  nothing is sent to the upstream maintainer's infrastructure. One read-only exception remains: the optional AI-agent
  usage feature fetches a public price list (`agent-prices.json`) from upstream's GitHub repository.
  Data lives in its own preference domain and Application Support folder.
- The user-visible name "Vorssaint" was replaced in string literals. Copyright and licence headers, `LICENSE`,
  `TRADEMARKS.md`, code comments, internal module/type names and the upstream links were **kept** on purpose:
  the GPL requires the notices to stay, and the links credit the original project.
- Not touched: upstream's `build.sh` and `Package.swift`. They still build the upstream macOS 14+ app and do
  not work for this port; use `build-monterey.sh`.

## Build and install

On a Monterey (or newer) Mac with the Command Line Tools:

```sh
git clone https://github.com/unupunct/Unupunct-s-MacTab.git
cd Unupunct-s-MacTab
./build-monterey.sh          # about 15 minutes with -Onone; output in build/
```

It checks the OS, compiler, SDK and architecture, compiles the app and the Now Playing adapter, compiles and
self-tests the fan helper (not bundled), builds the bundle, ad-hoc signs it, verifies it, and writes
`build/Unupunct MacTab.app`, a `.zip` and a `.dmg`. Options: `--reuse` (skip the compile), `--opt -O`
(optimised build), `--test` (reserved: the unit-test script is not written yet, so it fails honestly).

To install from the DMG: open it, drag **Unupunct MacTab** onto Applications. The app is not notarized, so
macOS will block the first launch: right-click the app, choose **Open**, confirm. Then grant the permissions it
asks for (Accessibility, and others per feature).

## Known issues and what is left

- Untested by hand: nearly every feature. Treat anything not named in the test table as unverified.
- Unit tests not ported or run; no CI.
- Apple Silicon and other macOS versions untested; not universal.
- Layout differences listed above; no visual comparison against upstream was made.
- Optimised (`-O`) builds were not made or timed; the published binary is a `-Onone` debug-style build (large, slower).
- Without Xcode there is no asset catalog (`actool`): the app uses a plain `.icns`.
- `README-UPSTREAM.md` is upstream's README, kept unchanged; its feature list describes the macOS 14+ app, not this port.
