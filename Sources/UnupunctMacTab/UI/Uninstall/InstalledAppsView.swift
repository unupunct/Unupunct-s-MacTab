// SPDX-License-Identifier: GPL-3.0-or-later
// Added for the Unupunct MacTab port (a new tool, not part of upstream).

import SwiftUI

/// The uninstaller tab: a list of installed apps to choose from, then the
/// uninstaller's own review screen for each chosen app.
struct UninstallTabView: View {
    @ObservedObject private var uninstaller = AppUninstaller.shared
    @ObservedObject private var batch = UninstallBatch.shared

    private var showList: Bool {
        uninstaller.phase == .empty && uninstaller.refusal == nil && !batch.isActive
    }

    var body: some View {
        if showList {
            InstalledAppsListView()
        } else {
            VStack(spacing: 0) {
                batchBar
                Divider()
                UninstallerView()
            }
        }
    }

    private var finished: Bool {
        if case .done = uninstaller.phase { return true }
        return false
    }

    private var batchBar: some View {
        HStack(spacing: 10) {
            Button("Back to the list") {
                batch.finish()
                InstalledAppsModel.shared.clearSelection()
                InstalledAppsModel.shared.load()
            }
            if batch.queue.count > 1 {
                Text("App \(batch.position + 1) of \(batch.queue.count)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if batch.hasNext {
                Button("Next app") { batch.next() }
                    .disabled(!finished && uninstaller.phase != .results)
                    .help("Skips to the next app in your selection")
            }
        }
        .padding(10)
    }
}

struct InstalledAppsListView: View {
    @ObservedObject private var model = InstalledAppsModel.shared
    @State private var confirming = false

    private func format(_ bytes: Int64?) -> String {
        guard let bytes = bytes else { return "…" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func lastUsedText(_ entry: InstalledAppEntry) -> String {
        guard let date = entry.lastUsed else { return "No record of opening" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Opened " + formatter.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            controls
            list
            footer
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { if model.apps.isEmpty { model.load() } }
        .alert("Uninstall the selected apps?", isPresented: $confirming) {
            Button("Cancel", role: .cancel) {}
            Button("Review and uninstall") {
                UninstallBatch.shared.start(model.selected.map { $0.url })
            }
        } message: {
            Text("You will review each app and its leftover files before anything is moved to the Trash.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Installed apps").font(.headline)
            Text("Pick the apps you no longer need. For each one you review the app and its leftover files first, and everything goes to the Trash. You can also drag an app onto the window that opens next.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            TextField("Search", text: $model.search)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
            Picker("", selection: $model.sort) {
                Text("Biggest first").tag(InstalledAppsModel.Sort.size)
                Text("Longest unused first").tag(InstalledAppsModel.Sort.lastUsed)
                Text("Name").tag(InstalledAppsModel.Sort.name)
            }
            .labelsHidden()
            .frame(width: 160)
            Toggle("Not opened for 90 days", isOn: $model.onlyRarelyUsed)
            Spacer()
            Button("Refresh") { model.load() }
                .disabled(model.loading)
        }
    }

    @ViewBuilder
    private var list: some View {
        if model.loading && model.apps.isEmpty {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reading your applications…").font(.callout).foregroundStyle(.secondary)
            }
        } else if model.shown.isEmpty {
            Text("No apps match.").font(.callout).foregroundStyle(.secondary)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.shown) { entry in
                        row(entry)
                        Divider()
                    }
                }
            }
        }
    }

    private func icon(_ entry: InstalledAppEntry) -> some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
            .resizable()
            .frame(width: 28, height: 28)
    }

    private func row(_ entry: InstalledAppEntry) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { entry.selected }, set: { _ in model.toggle(entry) }))
                .labelsHidden()
            icon(entry)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                Text(lastUsedText(entry))
                    .font(.caption)
                    .foregroundStyle(entry.isRarelyUsed ? Color.orange : Color.secondary)
            }
            Spacer(minLength: 8)
            if !entry.version.isEmpty {
                Text(entry.version).font(.caption).foregroundStyle(.secondary)
            }
            Text(format(entry.size)).font(.system(size: 12)).monospacedDigit().frame(width: 70, alignment: .trailing)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([entry.url])
            } label: {
                Image(systemName: "magnifyingglass.circle")
            }
            .buttonStyle(.plain)
            .help("Show in Finder")
        }
        .padding(.vertical, 5)
    }

    private var footer: some View {
        HStack {
            Text("\(model.selected.count) selected, \(format(model.selectedBytes))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Uninstall selected…") { confirming = true }
                .disabled(model.selected.isEmpty)
        }
    }
}
