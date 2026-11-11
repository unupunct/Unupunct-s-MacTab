// SPDX-License-Identifier: GPL-3.0-or-later
// Monterey (macOS 12) port: stand-in for ServiceManagement's SMAppService (macOS 13+).

import AppKit
import ServiceManagement

/// Same surface the app uses from `SMAppService`. On macOS 13+ it forwards to the
/// real service. On macOS 12:
/// - the main app registers as a login item through a per-user LaunchAgent plist;
/// - privileged daemons (the fan helper) cannot be registered, so they report
///   `.notFound` and registration throws. Fan control stays unavailable there.
struct AppServiceCompat {
    enum Status { case notRegistered, enabled, requiresApproval, notFound }

    struct UnsupportedError: LocalizedError {
        var errorDescription: String? { "This feature needs macOS 13 or later." }
    }

    private enum Kind { case mainApp, daemon(String) }
    private let kind: Kind

    static var mainApp: AppServiceCompat { AppServiceCompat(kind: .mainApp) }
    static func daemon(plistName: String) -> AppServiceCompat { AppServiceCompat(kind: .daemon(plistName)) }

    @available(macOS 13.0, *)
    private var real: SMAppService {
        switch kind {
        case .mainApp: return SMAppService.mainApp
        case .daemon(let name): return SMAppService.daemon(plistName: name)
        }
    }

    var status: Status {
        if #available(macOS 13.0, *) {
            switch real.status {
            case .enabled: return .enabled
            case .requiresApproval: return .requiresApproval
            case .notRegistered: return .notRegistered
            default: return .notFound
            }
        }
        guard case .mainApp = kind else { return .notFound }
        return FileManager.default.fileExists(atPath: Self.agentURL.path) ? .enabled : .notRegistered
    }

    func register() throws {
        if #available(macOS 13.0, *) { try real.register(); return }
        guard case .mainApp = kind else { throw UnsupportedError() }
        let plist: [String: Any] = [
            "Label": Self.agentLabel,
            "ProgramArguments": [Bundle.main.executablePath ?? ""],
            "RunAtLoad": true,
            "ProcessType": "Interactive",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try FileManager.default.createDirectory(at: Self.agentURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: Self.agentURL, options: .atomic)
    }

    func unregister() throws {
        if #available(macOS 13.0, *) { try real.unregister(); return }
        guard case .mainApp = kind else { throw UnsupportedError() }
        if FileManager.default.fileExists(atPath: Self.agentURL.path) {
            try FileManager.default.removeItem(at: Self.agentURL)
        }
    }

    func unregister(completionHandler: @escaping (Error?) -> Void) {
        if #available(macOS 13.0, *) { real.unregister(completionHandler: completionHandler); return }
        do { try unregister(); completionHandler(nil) } catch { completionHandler(error) }
    }

    static func openSystemSettingsLoginItems() {
        if #available(macOS 13.0, *) { SMAppService.openSystemSettingsLoginItems(); return }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.users?startupItemsPref") {
            NSWorkspace.shared.open(url)
        }
    }

    private static var agentLabel: String { (Bundle.main.bundleIdentifier ?? "app") + ".login" }
    private static var agentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")
    }
}

extension NSXPCConnection {
    /// `setCodeSigningRequirement` needs macOS 13; on macOS 12 the fan helper cannot
    /// run at all (see `AppServiceCompat`), so there is nothing to protect.
    func setCodeSigningRequirementCompat(_ requirement: String) {
        if #available(macOS 13.0, *) { setCodeSigningRequirement(requirement) }
    }
}
