// SPDX-License-Identifier: GPL-3.0-or-later
// Added for the Unupunct MacTab port (a new tool, not part of upstream).

import AppKit
import Combine
import UniformTypeIdentifiers

/// A place files can be sent: a folder (including a drive or a network share
/// that is mounted under /Volumes) or an app that opens them.
struct SendToDestination: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var path: String
    var isApp: Bool
}

/// "Send to" for the menu bar panel. The person chooses files, then a
/// destination: a folder gets a copy, an app opens the files. The list of
/// destinations is theirs to edit.
final class SendToService: ObservableObject {
    static let shared = SendToService()

    @Published private(set) var destinations: [SendToDestination] = []
    private let key = "sendToDestinations"

    private init() {
        load()
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([SendToDestination].self, from: data) {
            destinations = saved
            return
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let desktop = SendToDestination(name: "Desktop",
                                        path: home.appendingPathComponent("Desktop").path,
                                        isApp: false)
        let downloads = SendToDestination(name: "Downloads",
                                          path: home.appendingPathComponent("Downloads").path,
                                          isApp: false)
        destinations = [desktop, downloads]
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(destinations) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    // MARK: Editing the list

    func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder, drive or network location. A network share must be connected first so it shows under Locations."
        panel.prompt = "Add"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        add(SendToDestination(name: url.lastPathComponent, path: url.path, isApp: false))
    }

    func addApp() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let name = url.deletingPathExtension().lastPathComponent
        add(SendToDestination(name: name, path: url.path, isApp: true))
    }

    private func add(_ destination: SendToDestination) {
        guard !destinations.contains(where: { $0.path == destination.path }) else { return }
        destinations.append(destination)
        save()
    }

    func remove(_ destination: SendToDestination) {
        destinations.removeAll { $0.id == destination.id }
        save()
    }

    // MARK: Sending

    func chooseFilesAndSend(to destination: SendToDestination) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Send"
        panel.message = "Choose what to send to \(destination.name)."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        send(panel.urls, to: destination)
    }

    func send(_ urls: [URL], to destination: SendToDestination) {
        let target = URL(fileURLWithPath: destination.path)
        guard FileManager.default.fileExists(atPath: destination.path) else {
            notify("\(destination.name) is not available. If it is a network location, connect it first.")
            return
        }
        if destination.isApp {
            NSWorkspace.shared.open(urls, withApplicationAt: target,
                                    configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if let error = error {
                    DispatchQueue.main.async {
                        self.notify("Could not open the files with \(destination.name): \(error.localizedDescription)")
                    }
                }
            }
            return
        }
        copy(urls, into: target, name: destination.name)
    }

    private func copy(_ urls: [URL], into folder: URL, name: String) {
        var failures: [String] = []
        for source in urls {
            let destination = uniqueURL(for: source.lastPathComponent, in: folder)
            do {
                try FileManager.default.copyItem(at: source, to: destination)
            } catch {
                failures.append("\(source.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if failures.isEmpty {
            NSSound(named: NSSound.Name("Glass"))?.play()
        } else {
            notify("Some items were not copied to \(name):\n" + failures.joined(separator: "\n"))
        }
    }

    private func uniqueURL(for fileName: String, in folder: URL) -> URL {
        var candidate = folder.appendingPathComponent(fileName)
        let base = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let numbered = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            candidate = folder.appendingPathComponent(numbered)
            counter += 1
        }
        return candidate
    }

    private func notify(_ text: String) {
        let alert = NSAlert()
        alert.messageText = "Send to"
        alert.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
