// SPDX-License-Identifier: GPL-3.0-or-later
// Added for the Unupunct MacTab port (a new tool, not part of upstream).

import Foundation

/// Folders the person never wants the cleaner to touch. A scan leaves them
/// out, and the removal step refuses them again as a last check.
enum CleanerExclusions {
    static let key = "cleanerExcludedPaths"

    static var paths: [String] {
        (UserDefaults.standard.array(forKey: key) as? [String]) ?? []
    }

    static func add(_ path: String) {
        var list: [String] = paths
        let clean: String = URL(fileURLWithPath: path).standardizedFileURL.path
        guard !list.contains(clean) else { return }
        list.append(clean)
        UserDefaults.standard.set(list, forKey: key)
    }

    static func remove(_ path: String) {
        let list: [String] = paths.filter { $0 != path }
        UserDefaults.standard.set(list, forKey: key)
    }

    /// True when `url` is an excluded folder, lives inside one, or contains
    /// one (removing a parent would remove the excluded folder with it).
    static func isExcluded(_ url: URL, among excluded: [String]? = nil) -> Bool {
        let list: [String] = excluded ?? paths
        if list.isEmpty { return false }
        let path: String = url.standardizedFileURL.path
        for entry in list {
            if path == entry { return true }
            if path.hasPrefix(entry + "/") { return true }
            if entry.hasPrefix(path + "/") { return true }
        }
        return false
    }
}
