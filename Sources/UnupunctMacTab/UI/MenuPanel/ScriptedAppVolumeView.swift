// SPDX-License-Identifier: GPL-3.0-or-later
// Added for the Unupunct MacTab port (a new tool, not part of upstream).

import SwiftUI

/// Sliders for the apps that offer their own volume, shown on macOS 12 where
/// the per-app mixer cannot run.
struct ScriptedAppVolumeView: View {
    @ObservedObject private var service = ScriptedAppVolume.shared
    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("App volume")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)
            if service.players.isEmpty {
                Text("Music, Spotify and VLC get their own slider here while they are open. macOS 12 cannot turn down other apps one by one; they follow the general volume above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(service.players) { player in
                    row(player)
                }
            }
        }
        .onAppear { service.refresh() }
        .onReceive(timer) { _ in service.refresh() }
    }

    private func icon(_ player: Player) -> some View {
        Group {
            if let image = player.icon {
                Image(nsImage: image).resizable().frame(width: 16, height: 16)
            } else {
                Image(systemName: "app").frame(width: 16, height: 16)
            }
        }
    }

    private func row(_ player: Player) -> some View {
        HStack(spacing: 8) {
            icon(player)
            Text(player.name)
                .font(.system(size: 11.5))
                .frame(width: 58, alignment: .leading)
                .lineLimit(1)
            Slider(value: Binding(get: { player.volume },
                                  set: { service.setVolume($0, for: player) }),
                   in: 0...1)
                .controlSize(.small)
            Text("\(Int((player.volume * 100).rounded()))%")
                .font(.system(size: 10.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
    }
}

private typealias Player = ScriptedAppVolume.Player
