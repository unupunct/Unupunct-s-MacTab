// SPDX-License-Identifier: GPL-3.0-or-later
// Added for the Unupunct MacTab port (a new tool, not part of upstream).

import AppKit
import Combine
import CoreServices

/// One app found in the Applications folders.
struct InstalledAppEntry: Identifiable, Equatable {
    var id: String { url.path }
    let url: URL
    let name: String
    let bundleID: String
    let version: String
    var size: Int64?
    let lastUsed: Date?
    let added: Date?
    var selected: Bool = false

    static let rarelyUsedDays = 90

    /// True when the app was not opened for a long time (or Spotlight has no record of it opening).
    var isRarelyUsed: Bool {
        guard let lastUsed = lastUsed else { return true }
        let cutoff: Date = Date().addingTimeInterval(-Double(Self.rarelyUsedDays) * 86_400)
        return lastUsed < cutoff
    }
}

/// The list behind the uninstaller's first screen: every app in /Applications
/// and ~/Applications with its size and when it was last opened (from
/// Spotlight's own record). Apple's own apps are left out. Reading only: it
/// removes nothing; removal goes through the uninstaller's review screen.
final class InstalledAppsModel: ObservableObject {
    static let shared = InstalledAppsModel()

    enum Sort: String, CaseIterable, Identifiable {
        case size, lastUsed, name
        var id: String { rawValue }
    }

    @Published private(set) var apps: [InstalledAppEntry] = []
    @Published private(set) var loading = false
    @Published var sort: Sort = .size
    @Published var onlyRarelyUsed = false
    @Published var search = ""

    private var loadToken = UUID()
    private let sizeQueue = DispatchQueue(label: "local.unupunct.app-sizes", qos: .utility)

    private init() {}

    var shown: [InstalledAppEntry] {
        var list: [InstalledAppEntry] = apps
        if onlyRarelyUsed { list = list.filter { $0.isRarelyUsed } }
        let query: String = search.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }
        switch sort {
        case .size:
            return list.sorted { ($0.size ?? 0) > ($1.size ?? 0) }
        case .lastUsed:
            return list.sorted { ($0.lastUsed ?? Date.distantPast) < ($1.lastUsed ?? Date.distantPast) }
        case .name:
            return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    var selected: [InstalledAppEntry] { apps.filter { $0.selected } }
    var selectedBytes: Int64 { selected.reduce(0) { $0 + ($1.size ?? 0) } }

    func toggle(_ entry: InstalledAppEntry) {
        guard let index = apps.firstIndex(where: { $0.id == entry.id }) else { return }
        apps[index].selected.toggle()
    }

    func clearSelection() {
        for index in apps.indices { apps[index].selected = false }
    }

    func load() {
        let token = UUID()
        loadToken = token
        loading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let found: [InstalledAppEntry] = Self.discover()
            DispatchQueue.main.async {
                guard let self = self, self.loadToken == token else { return }
                self.apps = found
                self.loading = false
                self.computeSizes(for: found, token: token)
            }
        }
    }

    private func computeSizes(for entries: [InstalledAppEntry], token: UUID) {
        for entry in entries {
            sizeQueue.async { [weak self] in
                let size: Int64 = Self.directorySize(entry.url)
                DispatchQueue.main.async {
                    guard let self = self, self.loadToken == token,
                          let index = self.apps.firstIndex(where: { $0.id == entry.id }) else { return }
                    self.apps[index].size = size
                }
            }
        }
    }

    // MARK: Discovery

    private static func discover() -> [InstalledAppEntry] {
        let roots: [String] = ["/Applications", NSHomeDirectory() + "/Applications"]
        var urls: [URL] = []
        for root in roots { urls.append(contentsOf: appBundles(in: URL(fileURLWithPath: root), depth: 2)) }
        var entries: [InstalledAppEntry] = []
        for url in urls {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { continue }
            if id.hasPrefix("com.apple.") { continue }
            if id == AppInfo.portBundleID { continue }
            let name: String = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
            let version: String = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
            entries.append(InstalledAppEntry(url: url, name: name, bundleID: id, version: version, size: nil,
                                             lastUsed: lastUsedDate(url), added: addedDate(url)))
        }
        return entries
    }

    private static func appBundles(in folder: URL, depth: Int) -> [URL] {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        var found: [URL] = []
        for child in children {
            if child.pathExtension == "app" {
                found.append(child)
            } else if depth > 1,
                      (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                found.append(contentsOf: appBundles(in: child, depth: depth - 1))
            }
        }
        return found
    }

    private static func lastUsedDate(_ url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(nil, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    private static func addedDate(_ url: URL) -> Date? {
        if let item = MDItemCreateWithURL(nil, url as CFURL),
           let date = MDItemCopyAttribute(item, kMDItemDateAdded) as? Date { return date }
        return (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
    }

    private static func directorySize(_ url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}

/// Runs the uninstaller's own review flow for one chosen app after another.
final class UninstallBatch: ObservableObject {
    static let shared = UninstallBatch()

    @Published private(set) var queue: [URL] = []
    @Published private(set) var position = 0

    private init() {}

    var isActive: Bool { !queue.isEmpty }
    var hasNext: Bool { position + 1 < queue.count }

    func start(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        queue = urls
        position = 0
        _ = AppUninstaller.shared.select(appURL: urls[0])
    }

    func next() {
        guard hasNext else { return }
        AppUninstaller.shared.reset()
        position += 1
        _ = AppUninstaller.shared.select(appURL: queue[position])
    }

    func finish() {
        AppUninstaller.shared.reset()
        queue = []
        position = 0
    }
}
