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

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Large files").font(.headline)
            Text("Looks through Downloads, Desktop, Documents, Movies, Music and Pictures. Nothing is removed until you tick a file and confirm, and removed files go to the Trash.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Text("Bigger than").font(.callout)
                Picker("", selection: $scanner.minimumMegabytes) {
                    ForEach(Self.thresholds, id: \.self) { megabytes in
                        Text(thresholdLabel(megabytes)).tag(megabytes)
                    }
                }
                .labelsHidden()
                .frame(width: 100)
                Button(scanner.phase == .scanning ? "Scanning…" : "Scan") { scanner.scan() }
                    .disabled(scanner.phase == .scanning)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if scanner.phase == .idle {
            note("Press Scan to look for big files.")
        } else if scanner.phase == .scanning {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Looking for big files…").font(.callout).foregroundStyle(.secondary)
            }
        } else if scanner.items.isEmpty {
            note("No files bigger than \(scanner.minimumMegabytes) MB found in these folders.")
        } else {
            list
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(scanner.items) { item in
                    row(item)
                    Divider()
                }
            }
        }
    }

    private func row(_ item: LargeFileItem) -> some View {
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
