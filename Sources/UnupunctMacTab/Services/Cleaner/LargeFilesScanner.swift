// SPDX-License-Identifier: GPL-3.0-or-later
// Added for the Unupunct MacTab port (a new tool, not part of upstream).

import AppKit
import Combine
import CryptoKit

/// One big file found in the user's own folders.
struct LargeFileItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let size: Int64
    let modified: Date
    var selected: Bool = false

    var name: String { url.lastPathComponent }
    var folder: String { url.deletingLastPathComponent().path }
}

/// Files with identical content.
struct DuplicateGroup: Identifiable, Equatable {
    let id = UUID()
    let size: Int64
    var files: [LargeFileItem]
}

/// The folders the large-files and duplicates tools look through. They start
/// as the usual personal folders and the person can add or remove their own.
enum LargeFilesFolders {
    static let key = "largeFilesFolders"

    static var defaults: [String] {
        let home: String = NSHomeDirectory()
        let names: [String] = ["Downloads", "Desktop", "Documents", "Movies", "Music", "Pictures"]
        return names.map { home + "/" + $0 }
    }

    static var current: [String] {
        if let saved = UserDefaults.standard.array(forKey: key) as? [String] { return saved }
        return defaults
    }

    static func save(_ paths: [String]) {
        UserDefaults.standard.set(paths, forKey: key)
    }
}

/// Finds the biggest files and the duplicate files in the folders people keep
/// things in so they can decide what to remove. It only reads. Nothing is
/// removed until a file is ticked and confirmed, and removal moves the file to
/// the Trash, which can be undone. Packages (apps, libraries) and symbolic
/// links are skipped.
final class LargeFilesScanner: ObservableObject {
    static let shared = LargeFilesScanner()

    enum Phase: Equatable { case idle, scanning, done }
    enum Mode: String, CaseIterable, Identifiable {
        case large, duplicates
        var id: String { rawValue }
    }
    enum Sort: String, CaseIterable, Identifiable {
        case size, oldest
        var id: String { rawValue }
    }

    @Published private(set) var phase: Phase = .idle
    @Published var items: [LargeFileItem] = []
    @Published var groups: [DuplicateGroup] = []
    @Published private(set) var lastFreed: Int64 = 0
    @Published private(set) var lastFailed: Int = 0
    @Published private(set) var progressNote: String = ""
    @Published var minimumMegabytes: Int = 200
    @Published var mode: Mode = .large
    @Published var sort: Sort = .size {
        didSet { applySort() }
    }
    @Published var folders: [String] = LargeFilesFolders.current

    private let lock = NSLock()
    private var currentScan = UUID()
    private static let maxResults = 300
    private static let duplicateMinimumBytes: Int64 = 5_000_000

    private init() {}

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
        groups = []
    }

    // MARK: Folders

    func addFolder(_ path: String) {
        guard !folders.contains(path) else { return }
        folders.append(path)
        LargeFilesFolders.save(folders)
    }

    func removeFolder(_ path: String) {
        folders.removeAll { $0 == path }
        LargeFilesFolders.save(folders)
    }

    func resetFolders() {
        folders = LargeFilesFolders.defaults
        LargeFilesFolders.save(folders)
    }

    // MARK: Scanning

    func scan() {
        let scanID = UUID()
        lock.lock()
        currentScan = scanID
        lock.unlock()
        phase = .scanning
        items = []
        groups = []
        lastFreed = 0
        lastFailed = 0
        progressNote = "Looking through \(folders.count) folder(s)..."
        let wanted: Mode = mode
        let minimumBytes: Int64 = wanted == .large
            ? Int64(minimumMegabytes) * 1_000_000
            : Self.duplicateMinimumBytes
        let roots: [URL] = folders.map { URL(fileURLWithPath: $0, isDirectory: true) }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let files = self.walk(roots: roots, minimumBytes: minimumBytes, scanID: scanID)
            if wanted == .large {
                let top = self.sorted(Array(files.sorted { $0.size > $1.size }.prefix(Self.maxResults)))
                DispatchQueue.main.async {
                    guard self.isCurrent(scanID) else { return }
                    self.items = top
                    self.progressNote = ""
                    self.phase = .done
                }
            } else {
                DispatchQueue.main.async {
                    guard self.isCurrent(scanID) else { return }
                    self.progressNote = "Comparing \(files.count) file(s)..."
                }
                let found = self.findDuplicates(in: files, scanID: scanID)
                DispatchQueue.main.async {
                    guard self.isCurrent(scanID) else { return }
                    self.groups = found
                    self.progressNote = ""
                    self.phase = .done
                }
            }
        }
    }

    private func walk(roots: [URL], minimumBytes: Int64, scanID: UUID) -> [LargeFileItem] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey,
                                      .contentModificationDateKey]
        let keySet: Set<URLResourceKey> = Set(keys)
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
                let size: Int64 = Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
                guard size >= minimumBytes else { continue }
                if url.lastPathComponent == ".DS_Store" { continue }
                let modified: Date = values.contentModificationDate ?? Date.distantPast
                found.append(LargeFileItem(url: url, size: size, modified: modified))
            }
        }
        return found
    }

    private func findDuplicates(in files: [LargeFileItem], scanID: UUID) -> [DuplicateGroup] {
        var bySize: [Int64: [LargeFileItem]] = [:]
        for file in files { bySize[file.size, default: []].append(file) }
        var result: [DuplicateGroup] = []
        for (size, sameSize) in bySize where sameSize.count > 1 {
            var byHash: [String: [LargeFileItem]] = [:]
            for file in sameSize {
                if !isCurrent(scanID) { return [] }
                guard let digest = Self.sha256(of: file.url, stillWanted: { self.isCurrent(scanID) }) else { continue }
                byHash[digest, default: []].append(file)
            }
            for (_, same) in byHash where same.count > 1 {
                let ordered: [LargeFileItem] = same.sorted { $0.modified < $1.modified }
                result.append(DuplicateGroup(size: size, files: ordered))
            }
        }
        result.sort { $0.size * Int64($0.files.count - 1) > $1.size * Int64($1.files.count - 1) }
        return Array(result.prefix(150))
    }

    private static func sha256(of url: URL, stillWanted: () -> Bool) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            if !stillWanted() { return nil }
            let chunk: Data? = try? handle.read(upToCount: 4 * 1024 * 1024)
            guard let data = chunk, !data.isEmpty else { break }
            hasher.update(data: data)
        }
        let digest = hasher.finalize()
        var text = ""
        for byte in digest { text += String(format: "%02x", byte) }
        return text
    }

    // MARK: Sorting

    private func sorted(_ list: [LargeFileItem]) -> [LargeFileItem] {
        switch sort {
        case .size: return list.sorted { $0.size > $1.size }
        case .oldest: return list.sorted { $0.modified < $1.modified }
        }
    }

    private func applySort() {
        items = sorted(items)
    }

    // MARK: Selection and removal

    var selectedItems: [LargeFileItem] {
        let fromLarge: [LargeFileItem] = items.filter { $0.selected }
        let fromGroups: [LargeFileItem] = groups.flatMap { $0.files }.filter { $0.selected }
        return fromLarge + fromGroups
    }

    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.size } }

    func toggle(_ item: LargeFileItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].selected.toggle()
            return
        }
        for g in groups.indices {
            if let f = groups[g].files.firstIndex(where: { $0.id == item.id }) {
                groups[g].files[f].selected.toggle()
                return
            }
        }
    }

    /// Ticks every copy except the oldest one in each group of duplicates.
    func selectExtraCopies() {
        for g in groups.indices {
            for f in groups[g].files.indices {
                groups[g].files[f].selected = f > 0
            }
        }
    }

    /// Moves the ticked files to the Trash (reversible) and drops them from the lists.
    func trashSelected() {
        let chosen: [LargeFileItem] = selectedItems
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
        for g in groups.indices {
            groups[g].files.removeAll { removed.contains($0.id) }
        }
        groups.removeAll { $0.files.count < 2 }
        lastFreed = freed
        lastFailed = failed
    }
}
