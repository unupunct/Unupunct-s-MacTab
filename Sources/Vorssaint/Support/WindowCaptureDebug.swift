// SPDX-License-Identifier: GPL-3.0-or-later
// Monterey port: a developer aid that saves PNGs of this app's OWN Settings
// window, used to make the screenshots in the README. It runs only when the
// environment variable UNUPUNCT_CAPTURE_DIR names a folder, draws nothing but
// the app's own window (nothing else on the screen), and quits when done.

import AppKit
import CoreGraphics

enum WindowCaptureDebug {
    /// The Settings pages captured, in order.
    private static let pages: [(name: String, page: SettingsPage)] = [
        ("general", .general), ("features", .features), ("mouse", .mouse),
        ("windows", .windowLayout), ("notch", .notch), ("shortcuts", .shortcuts), ("about", .about),
    ]

    static func startIfRequested(_ delegate: AppDelegate) {
        guard let folder = ProcessInfo.processInfo.environment["UNUPUNCT_CAPTURE_DIR"], !folder.isEmpty else { return }
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            delegate.openSettingsWindow()
            step(0, folder: folder)
        }
    }

    private static func step(_ index: Int, folder: String) {
        guard index < pages.count else { NSApp.terminate(nil); return }
        SettingsRouter.shared.page = pages[index].page
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            capture(named: pages[index].name, folder: folder)
            step(index + 1, folder: folder)
        }
    }

    private static func capture(named name: String, folder: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.level == .normal && $0.styleMask.contains(.titled) })
        else { return }
        let id = CGWindowID(window.windowNumber)
        guard let image = CGWindowListCreateImage(.null, .optionIncludingWindow, id, [.boundsIgnoreFraming]) else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: "\(folder)/settings-\(name).png"))
        }
    }
}
