// SPDX-License-Identifier: GPL-3.0-or-later
// Added for the Unupunct MacTab port (a new tool, not part of upstream).

import SwiftUI

struct LargeFilesView: View {
    @ObservedObject private var scanner = LargeFilesScanner.shared
    @State private var confirming = false

    private static let thresholds: [Int] = [100, 200, 500, 1000, 2000]

    private func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func thresholdLabel(_ megabytes: Int) -> String {
        megabytes >= 1000 ? "\(megabytes / 1000) GB" : "\(megabytes) MB"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            foldersBox
            options
            content
            footer
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .alert("Move to the Trash?", isPresented: $confirming) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) { scanner.trashSelected() }
        } message: {
            Text("\(scanner.selectedItems.count) file(s), \(format(scanner.selectedBytes)). You can still put them back from the Trash.")
        }
    }

    // MARK: Header, folders, options

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Large files and duplicates").font(.headline)
            Text("Nothing is removed until you tick a file and confirm, and removed files go to the Trash.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var foldersBox: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Folders to look through").font(.callout.weight(.semibold))
                Spacer()
                Button("Add folder…") { chooseFolder() }
                Button("Reset") { scanner.resetFolders() }
            }
            ForEach(scanner.folders, id: \.self) { path in
                folderRow(path)
            }
        }
    }

    private func folderRow(_ path: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "folder").foregroundStyle(.secondary)
            Text(prettyPath(path)).font(.caption).lineLimit(1).truncationMode(.middle)
            Spacer()
            Button {
                scanner.removeFolder(path)
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Stop looking in this folder")
        }
    }

    private func prettyPath(_ path: String) -> String {
        let home: String = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose folders or drives to look through."
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { scanner.addFolder(url.path) }
    }

    private var options: some View {
        HStack(spacing: 10) {
            Picker("", selection: $scanner.mode) {
                Text("Big files").tag(LargeFilesScanner.Mode.large)
                Text("Duplicates").tag(LargeFilesScanner.Mode.duplicates)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 190)
            if scanner.mode == .large {
                sizeAndSort
            }
            Spacer()
            Button(scanner.phase == .scanning ? "Scanning…" : "Scan") { scanner.scan() }
                .disabled(scanner.phase == .scanning || scanner.folders.isEmpty)
        }
    }

    private var sizeAndSort: some View {
        HStack(spacing: 8) {
            Text("Bigger than").font(.callout)
            Picker("", selection: $scanner.minimumMegabytes) {
                ForEach(Self.thresholds, id: \.self) { megabytes in
                    Text(thresholdLabel(megabytes)).tag(megabytes)
                }
            }
            .labelsHidden()
            .frame(width: 90)
            Picker("", selection: $scanner.sort) {
                Text("Biggest first").tag(LargeFilesScanner.Sort.size)
                Text("Oldest first").tag(LargeFilesScanner.Sort.oldest)
            }
            .labelsHidden()
            .frame(width: 120)
        }
    }

    // MARK: Results

    @ViewBuilder
    private var content: some View {
        if scanner.phase == .idle {
            note(scanner.mode == .large
                 ? "Press Scan to look for big files."
                 : "Press Scan to look for files that exist more than once (5 MB and up).")
        } else if scanner.phase == .scanning {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(scanner.progressNote).font(.callout).foregroundStyle(.secondary)
            }
        } else if scanner.mode == .large {
            largeList
        } else {
            duplicateList
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var largeList: some View {
        if scanner.items.isEmpty {
            note("No files bigger than \(scanner.minimumMegabytes) MB found in these folders.")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(scanner.items) { item in
                        row(item, showDate: scanner.sort == .oldest)
                        Divider()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var duplicateList: some View {
        if scanner.groups.isEmpty {
            note("No duplicate files found in these folders.")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(scanner.groups.count) set(s) of identical files.").font(.callout)
                    Spacer()
                    Button("Tick extra copies (keep the oldest)") { scanner.selectExtraCopies() }
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(scanner.groups) { group in
                            groupBox(group)
                        }
                    }
                }
            }
        }
    }

    private func groupBox(_ group: DuplicateGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(group.files.count) copies, \(format(group.size)) each")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)
            ForEach(group.files) { file in
                row(file, showDate: true)
                Divider()
            }
        }
    }

    private func dateText(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    private func row(_ item: LargeFileItem, showDate: Bool) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { item.selected }, set: { _ in scanner.toggle(item) }))
                .labelsHidden()
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                Text(item.folder)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 8)
            if showDate {
                Text(dateText(item.modified)).font(.caption).foregroundStyle(.secondary)
            }
            Text(format(item.size)).font(.system(size: 12)).monospacedDigit()
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Image(systemName: "magnifyingglass.circle")
            }
            .buttonStyle(.plain)
            .help("Show in Finder")
        }
        .padding(.vertical, 6)
    }

    // MARK: Footer

    private var resultText: String {
        var text = "Moved \(format(scanner.lastFreed)) to the Trash."
        if scanner.lastFailed > 0 { text += " \(scanner.lastFailed) could not be moved." }
        return text
    }

    private var footer: some View {
        HStack {
            if scanner.lastFreed > 0 || scanner.lastFailed > 0 {
                Text(resultText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(scanner.selectedItems.count) selected, \(format(scanner.selectedBytes))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Move to Trash") { confirming = true }
                .disabled(scanner.selectedItems.isEmpty)
        }
    }
}
