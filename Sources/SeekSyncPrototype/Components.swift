import AppKit
import SwiftUI

struct PlaylistArtwork: View {
    let playlist: Playlist
    var size: CGFloat = 54

    var body: some View {
        Group {
            if let url = playlist.artworkURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: generatedArtwork
                    }
                }
            } else {
                generatedArtwork
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(size * 0.12, 6), style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: max(size * 0.12, 6), style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: size * 0.09, y: size * 0.05)
        .accessibilityHidden(true)
    }

    private var generatedArtwork: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hue: playlist.artworkHue, saturation: 0.76, brightness: 0.72),
                    Color(hue: (playlist.artworkHue + 0.13).truncatingRemainder(dividingBy: 1), saturation: 0.88, brightness: 0.38)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(.white.opacity(0.12))
                .frame(width: size * 0.7)
                .offset(x: size * 0.22, y: -size * 0.2)
            Image(systemName: "waveform")
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}

struct StatusPill: View {
    enum Tone { case neutral, green, orange, red, blue }
    let text: String
    let systemImage: String?
    var tone: Tone = .neutral

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(foreground)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(background, in: Capsule())
    }

    private var foreground: Color {
        switch tone {
        case .neutral: return .secondary
        case .green: return .green
        case .orange: return .orange
        case .red: return .red
        case .blue: return .blue
        }
    }

    private var background: Color { foreground.opacity(0.12) }
}

struct DependencyPill: View {
    let state: DependencyState

    var body: some View {
        switch state {
        case .ready:
            StatusPill(text: state.label, systemImage: "checkmark.circle.fill", tone: .green)
        case .checking, .installing:
            StatusPill(text: state.label, systemImage: "hourglass", tone: .neutral)
        case .missing, .failed:
            StatusPill(text: state.label, systemImage: "exclamationmark.triangle.fill", tone: .red)
        }
    }
}

struct PlaylistHealthPill: View {
    let playlist: Playlist

    var body: some View {
        switch playlist.health {
        case .ready:
            StatusPill(text: playlist.health.label, systemImage: "checkmark", tone: .green)
        case .partial:
            StatusPill(text: "\(playlist.missingCount) missing", systemImage: "arrow.down.circle", tone: .orange)
        case .attention:
            StatusPill(text: attentionReason, systemImage: "exclamationmark", tone: .red)
        case .neverSynced:
            StatusPill(text: playlist.health.label, systemImage: nil, tone: .neutral)
        }
    }

    private var attentionReason: String {
        if playlist.needsReview > 0 {
            return "\(playlist.needsReview) to review"
        }
        if playlist.missingCount > 0 {
            return "\(playlist.missingCount) missing"
        }
        return playlist.health.label
    }
}

struct PlaylistRow: View {
    @EnvironmentObject private var model: AppModel
    let playlist: Playlist
    var compact = false

    var body: some View {
        Button {
            model.select(playlist)
        } label: {
            HStack(spacing: 12) {
                PlaylistArtwork(playlist: playlist, size: compact ? 42 : 52)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(playlist.name)
                            .font(.system(size: compact ? 13 : 14, weight: .semibold))
                            .lineLimit(1)
                            .help(playlist.name)
                        if model.isInPool(playlist.id) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundStyle(.blue)
                                .font(.caption)
                                .help("Keep synced")
                        }
                    }
                    Text("\(playlist.owner) · \(playlist.trackCount == 0 ? "Tracks load when synced" : "\(playlist.trackCount) tracks")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if !compact {
                        ProgressView(value: playlist.coverage)
                            .tint(.blue)
                            .accessibilityLabel("Local coverage for \(playlist.name)")
                            .accessibilityValue("\(playlist.localCount) of \(playlist.trackCount) tracks available locally")
                    }
                }
                Spacer(minLength: 8)
                if !compact { PlaylistHealthPill(playlist: playlist) }
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                model.selectedPlaylistID == playlist.id
                    ? Color.accentColor.opacity(0.07)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(alignment: .leading) {
                if model.selectedPlaylistID == playlist.id {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: 3)
                        .padding(.vertical, 8)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(playlist.name), \(playlist.trackCount == 0 ? "track count loads when synced" : "\(playlist.trackCount) tracks"), \(playlist.health.label)")
        .contextMenu {
            Button("Sync Now…") { model.showSyncPreview(for: playlist) }
            Button(model.isInPool(playlist.id) ? "Disable Daily Sync" : "Enable Daily Sync") {
                model.togglePlan(for: playlist)
            }
        }
    }
}

struct RunCountsView: View {
    let counts: RunCounts

    var body: some View {
        HStack(spacing: 7) {
            count("+\(counts.added)", "Added", .green)
            count("↑\(counts.upgraded)", "Upgraded", .blue)
            count("\(counts.alreadyBest)", "Already best", .secondary)
            if counts.unavailable > 0 { count("\(counts.unavailable)", "Unavailable", .orange) }
            if counts.needsReview > 0 { count("\(counts.needsReview)", "Needs review", .red) }
        }
    }

    private func count(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(color)
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct ToastView: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "info.circle.fill")
            .font(.callout.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThickMaterial, in: Capsule())
            .overlay(Capsule().stroke(.quaternary))
            .shadow(radius: 12, y: 5)
    }
}

struct SectionHeader: View {
    let eyebrow: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(eyebrow.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
            Text(title).font(.system(size: 26, weight: .bold, design: .rounded))
            Text(detail).font(.callout).foregroundStyle(.secondary)
        }
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(detail))
    }
}
