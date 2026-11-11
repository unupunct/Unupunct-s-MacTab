// SPDX-License-Identifier: GPL-3.0-or-later
// Added for the Unupunct MacTab port (a new tool, not part of upstream).

import AppKit
import Combine

/// Per-app volume for the apps that expose their own volume to AppleScript
/// (Music, Spotify, VLC). macOS 12 gives no way to turn down an arbitrary
/// app's sound, so those are the only apps with their own slider; every other
/// app follows the general volume. The first use of each app makes macOS ask
/// for Automation permission, which the person can grant or refuse.
final class ScriptedAppVolume: ObservableObject {
    static let shared = ScriptedAppVolume()

    struct Player: Identifiable, Equatable {
        let id: String
        let name: String
        let icon: NSImage?
        var volume: Double

        static func == (lhs: Player, rhs: Player) -> Bool {
            lhs.id == rhs.id && abs(lhs.volume - rhs.volume) < 0.001
        }
    }

    private struct Spec {
        let bundleID: String
        let name: String
        let property: String
        let maximum: Double
    }

    private static let specs: [Spec] = [
        Spec(bundleID: "com.apple.Music", name: "Music", property: "sound volume", maximum: 100),
        Spec(bundleID: "com.spotify.client", name: "Spotify", property: "sound volume", maximum: 100),
        Spec(bundleID: "org.videolan.vlc", name: "VLC", property: "audio volume", maximum: 512),
    ]

    @Published private(set) var players: [Player] = []
    private let queue = DispatchQueue(label: "local.unupunct.scripted-volume", qos: .userInitiated)
    private var lastWrite: [String: Date] = [:]

    private init() {}

    /// Reads the volume of every supported app that is open right now. An
    /// app that is not running is never touched, so nothing gets launched.
    func refresh() {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        let open = Self.specs.filter { running.contains($0.bundleID) }
        if open.isEmpty {
            if !players.isEmpty { players = [] }
            return
        }
        queue.async { [weak self] in
            var found: [Player] = []
            for spec in open {
                guard let raw = Self.run("tell application id \"\(spec.bundleID)\" to get \(spec.property)"),
                      let value = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else { continue }
                let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: spec.bundleID)
                let icon = app.map { NSWorkspace.shared.icon(forFile: $0.path) }
                let fraction = min(max(value / spec.maximum, 0), 1)
                found.append(Player(id: spec.bundleID, name: spec.name, icon: icon, volume: fraction))
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                // Do not fight a slider that is being dragged right now.
                let merged = found.map { player -> Player in
                    var copy = player
                    if let written = self.lastWrite[player.id], Date().timeIntervalSince(written) < 1.5,
                       let current = self.players.first(where: { $0.id == player.id }) {
                        copy.volume = current.volume
                    }
                    return copy
                }
                if merged != self.players { self.players = merged }
            }
        }
    }

    func setVolume(_ fraction: Double, for player: Player) {
        guard let spec = Self.specs.first(where: { $0.bundleID == player.id }) else { return }
        let clamped = min(max(fraction, 0), 1)
        if let index = players.firstIndex(where: { $0.id == player.id }) {
            players[index].volume = clamped
        }
        lastWrite[player.id] = Date()
        let target = Int((clamped * spec.maximum).rounded())
        queue.async {
            _ = Self.run("tell application id \"\(spec.bundleID)\" to set \(spec.property) to \(target)")
        }
    }

    /// Runs one AppleScript line through osascript, off the main thread, so a
    /// slow or blocked app can never freeze the panel.
    private static func run(_ source: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let deadline = Date().addingTimeInterval(4)
        while process.isRunning && Date() < deadline { usleep(20_000) }
        if process.isRunning {
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
