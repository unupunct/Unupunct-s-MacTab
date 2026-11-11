// SPDX-License-Identifier: GPL-3.0-or-later
// Added for the Unupunct MacTab port (a new tool, not part of upstream).

import SwiftUI
import AppKit

/// Builds and shows the "Send to" menu. A plain AppKit menu keeps the button
/// looking exactly like its neighbours (SwiftUI's Menu drops the border on
/// macOS 12).
final class SendToMenuPresenter: NSObject {
    static let shared = SendToMenuPresenter()

    private let service = SendToService.shared

    private func item(_ title: String, symbol: String, action: Selector,
                      object: Any? = nil) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        entry.representedObject = object
        entry.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return entry
    }

    func present() {
        let menu = NSMenu()
        for destination in service.destinations {
            let symbol = destination.isApp ? "app" : "folder"
            menu.addItem(item(destination.name, symbol: symbol,
                              action: #selector(sendTo(_:)), object: destination))
        }
        if !service.destinations.isEmpty { menu.addItem(.separator()) }
        menu.addItem(item("Add folder, drive or network location…", symbol: "plus",
                          action: #selector(addFolder)))
        menu.addItem(item("Add app…", symbol: "plus.app", action: #selector(addApp)))
        if !service.destinations.isEmpty {
            let removeItem = NSMenuItem(title: "Remove", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for destination in service.destinations {
                submenu.addItem(item(destination.name, symbol: "minus.circle",
                                     action: #selector(remove(_:)), object: destination))
            }
            removeItem.submenu = submenu
            menu.addItem(removeItem)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    /// Runs after the panel has closed, so the file picker is not fighting it.
    private func afterPanelCloses(_ work: @escaping () -> Void) {
        appDelegate()?.closePopover()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    @objc private func sendTo(_ sender: NSMenuItem) {
        guard let destination = sender.representedObject as? SendToDestination else { return }
        afterPanelCloses { SendToService.shared.chooseFilesAndSend(to: destination) }
    }

    @objc private func addFolder() {
        afterPanelCloses { SendToService.shared.addFolder() }
    }

    @objc private func addApp() {
        afterPanelCloses { SendToService.shared.addApp() }
    }

    @objc private func remove(_ sender: NSMenuItem) {
        guard let destination = sender.representedObject as? SendToDestination else { return }
        SendToService.shared.remove(destination)
    }
}

/// The panel's "Send to" button: opens a menu of the person's destinations.
struct SendToMenuButton: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            SendToMenuPresenter.shared.present()
        } label: {
            Label("Send to", systemImage: "paperplane")
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 7)
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(PanelSurface.cardFill(for: colorScheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 0.8)
                )
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }
}
