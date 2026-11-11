// SPDX-License-Identifier: GPL-3.0-or-later
// Added for the Unupunct MacTab port (a new tool, not part of upstream).

import SwiftUI
import AppKit

enum ToolboxTab: String, CaseIterable, Identifiable {
    case clean, uninstall, large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clean: return "Clean"
        case .uninstall: return "Uninstall apps"
        case .large: return "Large files"
        }
    }
}

final class ToolboxState: ObservableObject {
    static let shared = ToolboxState()
    @Published var tab: ToolboxTab = .clean
}

struct ToolboxView: View {
    @ObservedObject private var state = ToolboxState.shared

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $state.tab) {
                ForEach(ToolboxTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)
            Divider()
            tabContent
        }
        .frame(minWidth: 640, minHeight: 520)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch state.tab {
        case .clean:
            CleanerView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .uninstall:
            UninstallerView()
        case .large:
            LargeFilesView()
        }
    }
}

/// The window behind the panel's Clean button: cleaner, app uninstaller and
/// large-file finder in one place.
final class ToolboxWindowController {
    static let shared = ToolboxWindowController()
    private var window: NSWindow?

    func show(tab: ToolboxTab) {
        // These tools are what the Clean button is for, so make sure they are
        // installed instead of opening a page that does nothing.
        FeatureRuntime.shared.setAvailable([.cleaner, .uninstaller], true)
        ToolboxState.shared.tab = tab
        if window == nil {
            let host = NSHostingController(rootView: ToolboxView())
            host.setPreferredContentSizing(false)
            let created = NSWindow(contentViewController: host)
            created.title = "Clean and free space"
            created.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            created.setContentSize(NSSize(width: 760, height: 640))
            created.isReleasedWhenClosed = false
            created.center()
            window = created
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
