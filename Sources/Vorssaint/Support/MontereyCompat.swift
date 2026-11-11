// SPDX-License-Identifier: GPL-3.0-or-later
// Monterey (macOS 12) port: wrappers for APIs newer than macOS 12.

import AppKit
import SwiftUI

extension NSHostingController {
    /// `sizingOptions` exists from macOS 13. On macOS 12 the controller keeps
    /// its older default sizing behaviour and this call does nothing.
    func setPreferredContentSizing(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            sizingOptions = enabled ? .preferredContentSize : []
        }
    }
}

extension NSPopover {
    /// `hasFullSizeContent` only exists on macOS 26 and later (read through KVC
    /// so the code also compiles against older SDKs). Never set before macOS 26.
    func setFullSizeContentIfSupported(_ enabled: Bool) {
        guard #available(macOS 26.0, *) else { return }
        setValue(enabled, forKey: "hasFullSizeContent")
    }
}

extension NSRunningApplication {
    /// Cooperative activation (`activate(from:options:)`) exists from macOS 14;
    /// earlier systems, and builds against an older SDK, use the classic call.
    @discardableResult
    func activateCompat(from other: NSRunningApplication, options: NSApplication.ActivationOptions = []) -> Bool {
        #if compiler(>=5.9)
        if #available(macOS 14.0, *) {
            return activate(from: other, options: options)
        }
        #endif
        return activate(options: options)
    }
}

/// Mirrors `URL.DirectoryHint` (macOS 13+) for Monterey.
enum DirectoryHintCompat {
    case isDirectory, notDirectory, inferFromPath
}

extension URL {
    /// `appending(path:directoryHint:)` needs macOS 13; this works on macOS 12.
    func appendingCompat(path: String, directoryHint: DirectoryHintCompat = .inferFromPath) -> URL {
        switch directoryHint {
        case .isDirectory: return appendingPathComponent(path, isDirectory: true)
        case .notDirectory: return appendingPathComponent(path, isDirectory: false)
        case .inferFromPath: return appendingPathComponent(path)
        }
    }
}

extension TimeZone {
    /// `TimeZone.gmt` needs macOS 13.
    static var gmtCompat: TimeZone { TimeZone(secondsFromGMT: 0) ?? .current }
}

#if !compiler(>=5.9)
import CoreAudio
// Audio process-object selectors are declared by the macOS 14.2+ SDK only. The
// four-character codes are copied from AudioHardware.h so the process-listing code
// compiles with the Monterey toolchain; on macOS 12 the HAL answers "unknown
// property", which the callers already treat as "no processes".
let kAudioHardwarePropertyProcessObjectList: AudioObjectPropertySelector = 0x7072_7323 // 'prs#'
let kAudioProcessPropertyPID: AudioObjectPropertySelector = 0x7070_6964 // 'ppid'
let kAudioProcessPropertyBundleID: AudioObjectPropertySelector = 0x7062_6964 // 'pbid'
let kAudioProcessPropertyDevices: AudioObjectPropertySelector = 0x7064_7623 // 'pdv#'
let kAudioProcessPropertyIsRunning: AudioObjectPropertySelector = 0x7069_723F // 'pir?'
let kAudioProcessPropertyIsRunningOutput: AudioObjectPropertySelector = 0x7069_726F // 'piro'
#endif

extension NSWindow.CollectionBehavior {
    /// `.canJoinAllApplications` needs macOS 13; macOS 12 has no equivalent.
    static var canJoinAllApplicationsCompat: NSWindow.CollectionBehavior {
        if #available(macOS 13.0, *) { return .canJoinAllApplications }
        return []
    }
}

#if !compiler(>=5.9)
let kAudioHardwarePropertyTranslatePIDToProcessObject: AudioObjectPropertySelector = 0x6964_3270 // 'id2p'
#endif

#if !compiler(>=5.9)
import EventKit
extension EKAuthorizationStatus {
    /// macOS 14 split `.authorized` into `.fullAccess` and `.writeOnly`; macOS 12/13 have one grant.
    static var fullAccess: EKAuthorizationStatus { .authorized }
    static var writeOnly: EKAuthorizationStatus { EKAuthorizationStatus(rawValue: 4) ?? .denied }
}
#endif

enum MainActorCompat {
    /// `MainActor.assumeIsolated` needs the macOS 14 runtime. Same contract: the caller
    /// must already be on the main thread.
    static func assumeIsolated<T>(_ body: @MainActor () -> T) -> T {
        #if compiler(>=5.9)
        if #available(macOS 14.0, *) { return MainActor.assumeIsolated(body) }
        #endif
        dispatchPrecondition(condition: .onQueue(.main))
        return withoutActuallyEscaping(body) { escapable in
            unsafeBitCast(escapable, to: (() -> T).self)()
        }
    }
}

extension NSHostingView {
    /// `NSHostingView.sizingOptions` needs macOS 13; no-op on macOS 12.
    func setPreferredContentSizing(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            sizingOptions = enabled ? .preferredContentSize : []
        }
    }
}

#if !compiler(>=5.9)
import SwiftUI
// SwiftUI's preset springs arrived in macOS 14. These approximate them with the
// older spring initialiser (same feel, not bit-identical curves).
extension Animation {
    static var smooth: Animation { smooth() }
    static func smooth(duration: TimeInterval = 0.5, extraBounce: Double = 0) -> Animation {
        .spring(response: duration, dampingFraction: min(1, 1 - extraBounce))
    }
    static var snappy: Animation { snappy() }
    static func snappy(duration: TimeInterval = 0.5, extraBounce: Double = 0) -> Animation {
        .spring(response: duration * 0.7, dampingFraction: min(1, 0.85 - extraBounce))
    }
    static var bouncy: Animation { bouncy() }
    static func bouncy(duration: TimeInterval = 0.5, extraBounce: Double = 0.25) -> Animation {
        .spring(response: duration, dampingFraction: max(0.1, 0.75 - extraBounce))
    }
}
#endif

extension Task where Success == Never, Failure == Never {
    /// `Task.sleep(for: Duration)` needs macOS 13; the nanosecond form works on macOS 12.
    static func sleepCompat(seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }
}

#if !compiler(>=5.9)
// macOS 14 added `onChange(of:initial:_:)` with old/new (or no) arguments. These
// overloads provide the same call shapes on older SDKs by tracking the previous value.
private struct OnChangeCompat<V: Equatable>: ViewModifier {
    let value: V
    let initial: Bool
    let action: (V, V) -> Void
    @State private var previous: V

    init(value: V, initial: Bool, action: @escaping (V, V) -> Void) {
        self.value = value
        self.initial = initial
        self.action = action
        _previous = State(initialValue: value)
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: value) { new in
                let old = previous
                previous = new
                action(old, new)
            }
            .onAppear { if initial { action(value, value) } }
    }
}

extension View {
    func onChange<V: Equatable>(of value: V, initial: Bool = false,
                                _ action: @escaping (_ oldValue: V, _ newValue: V) -> Void) -> some View {
        modifier(OnChangeCompat(value: value, initial: initial, action: action))
    }

    func onChange<V: Equatable>(of value: V, initial: Bool = false,
                                _ action: @escaping () -> Void) -> some View {
        modifier(OnChangeCompat(value: value, initial: initial, action: { _, _ in action() }))
    }
}
#endif

import AVFoundation

extension AVAssetImageGenerator {
    /// `image(at:)` (async) needs macOS 13; macOS 12 uses the synchronous copy call.
    func imageCompat(at time: CMTime) async throws -> CGImage {
        #if compiler(>=5.8)
        if #available(macOS 13.0, *) { return try await image(at: time).image }
        #endif
        return try copyCGImage(at: time, actualTime: nil)
    }
}

extension View {
    /// `.menuStyle(.button)` needs macOS 13; macOS 12 uses the borderless menu style.
    @ViewBuilder func menuStyleButtonCompat() -> some View {
        if #available(macOS 13.0, *) { menuStyle(.button) } else { menuStyle(.borderlessButton) }
    }
}
