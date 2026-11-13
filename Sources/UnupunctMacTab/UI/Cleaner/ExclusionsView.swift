// SPDX-License-Identifier: GPL-3.0-or-later
// Added for the Unupunct MacTab port (a new tool, not part of upstream).

import SwiftUI

/// The list of folders the cleaner must leave alone.
struct ExclusionsView: View {
    @State private var paths: [String] = CleanerExclusions.paths

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Folders the cleaner leaves alone").font(.headline)
                Text("Anything inside these folders is skipped by every scan and every clean, including the scheduled one. If a folder you add is inside something the cleaner would otherwise remove, the whole item is skipped.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Add folder…") { choose() }
                Spacer()
            }
            if paths.isEmpty {
                Text("No exclusions yet.").font(.callout).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(paths, id: \.self) { path in
                            row(path)
                            Divider()
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ path: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield").foregroundStyle(.secondary)
            Text(path).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
            Spacer()
            Button("Remove") {
                CleanerExclusions.remove(path)
                paths = CleanerExclusions.paths
            }
        }
        .padding(.vertical, 6)
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Exclude"
        panel.message = "Choose folders the cleaner must never touch."
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { CleanerExclusions.add(url.path) }
        paths = CleanerExclusions.paths
    }
}
