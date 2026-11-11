// SPDX-License-Identifier: GPL-3.0-or-later
// Added for the Unupunct MacTab port (a new tool, not part of upstream).

import AppKit
import Combine

/// One big file found in the user's own folders.
struct LargeFileItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let size: Int64
    var selected: Bool = false

    var name: String { url.lastPathComponent }
    var folder: String { url.deletingLastPathComponent().path }
}

/// Finds the biggest files in the folders people keep things in (Downloads,
/// Desktop, Documents, Movies, Music, Pictures) so they can decide what to
/// remove. It only reads sizes. Nothing is removed until the person ticks a
/// file and confirms, and removal moves the file to the Trash, which can be
/// undone. Packages (apps, libraries) and symbolic links are skipped.
final class LargeFilesScanner: ObservableObject {
    static let shared = LargeFilesScanner()

    enum Phase: Equatable { case idle, scanning, done }

    @Published private(set) var phase: Phase = .idle
    @Published var items: [LargeFileItem] = []
    @Published private(set) var lastFreed: Int64 = 0
    @Published private(set) var lastFailed: Int = 0
    @Published var minimumMegabytes: Int = 200

    private let lock = NSLock()
    private var currentScan = UUID()
    private static let maxResults = 300

    private init() {}

    static var roots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let names: [String] = ["Downloads", "Desktop", "Documents", "Movies", "Music", "Pictures"]
        return names.map { home.appendingPathComponent($0, isDirectory: true) }
    }

    private func isCurrent(_ scan: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return currentScan == scan
    }

    func reset() {
        lock.lock()
        currentScan = UUID()
        lock.unlock()
        phase = .idle
        items = []
    }

    func scan() {
        let scanID = UUID()
        lock.lock()
        currentScan = scanID
        lock.unlock()
        phase = .scanning
        items = []
        lastFreed = 0
        lastFailed = 0
        let minimumBytes = Int64(minimumMegabytes) * 1_000_000
        let roots = Self.roots
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let found = self.walk(roots: roots, minimumBytes: minimumBytes, scanID: scanID)
            DispatchQueue.main.async {
                guard self.isCurrent(scanID) else { return }
                self.items = found
                self.phase = .done
            }
        }
    }

    private func walk(roots: [URL], minimumBytes: Int64, scanID: UUID) -> [LargeFileItem] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        let keySet = Set(keys)
        var found: [LargeFileItem] = []
        for root in roots {
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsPackageDescendants],
                errorHandler: { _, _ in true })
            guard let walker = enumerator else { continue }
            for case let url as URL in walker {
                if !isCurrent(scanID) { return [] }
                guard let values = try? url.resourceValues(forKeys: keySet),
                      values.isRegularFile == true else { continue }
                let size = Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
                if size >= minimumBytes {
                    found.append(LargeFileItem(url: url, size: size))
                }
            }
        }
        found.sort { $0.size > $1.size }
        if found.count > Self.maxResults { found = Array(found.prefix(Self.maxResults)) }
        return found
    }

    var selectedItems: [LargeFileItem] { items.filter { $0.selected } }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.size } }

    func toggle(_ item: LargeFileItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].selected.toggle()
    }

    /// Moves the ticked files to the Trash (reversible) and drops them from the list.
    func trashSelected() {
        let chosen = selectedItems
        var freed: Int64 = 0
        var failed = 0
        var removed = Set<UUID>()
        for item in chosen {
            do {
                try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                freed += item.size
                removed.insert(item.id)
            } catch {
                failed += 1
            }
        }
        items.removeAll { removed.contains($0.id) }
        lastFreed = freed
        lastFailed = failed
    }
}
