import AppKit
import SwiftUI

enum SeekSyncVersion {
    static var label: String {
        label(infoDictionary: Bundle.main.infoDictionary)
    }

    static func label(infoDictionary: [String: Any]?) -> String {
        guard let version = infoDictionary?["CFBundleShortVersionString"] as? String,
              !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "SeekSync development"
        }
        return "SeekSync \(version)"
    }

    static var shortLabel: String {
        shortLabel(infoDictionary: Bundle.main.infoDictionary)
    }

    static func shortLabel(infoDictionary: [String: Any]?) -> String {
        let fullLabel = label(infoDictionary: infoDictionary)
        guard fullLabel != "SeekSync development" else { return "dev" }
        return "v" + fullLabel.dropFirst("SeekSync ".count)
    }
}

enum SeekSyncBrandAssets {
    static let applicationIcon: NSImage = {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(named: NSImage.applicationIconName) ?? NSImage(size: NSSize(width: 128, height: 128))
    }()
}

struct SeekSyncAppIcon: View {
    var size: CGFloat
    var image: NSImage = SeekSyncBrandAssets.applicationIcon

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct SeekSyncBrandHeader: View {
    var iconSize: CGFloat = 38
    var image: NSImage = SeekSyncBrandAssets.applicationIcon
    var subtitle = "PLAYLIST SYNC"

    var body: some View {
        HStack(spacing: 10) {
            SeekSyncAppIcon(size: iconSize, image: image)
            VStack(alignment: .leading, spacing: 1) {
                Text("SeekSync")
                    .font(.headline)
                Text(subtitle)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("SeekSync, playlist sync")
    }
}

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

struct TrackFailureDetailsView: View {
    let run: SyncRun

    private var failures: [TrackSyncFailure] { run.trackFailures ?? [] }
    private var reportedIssueCount: Int { run.counts.unavailable + run.counts.needsReview }
    private var missingDetailCount: Int { max(reportedIssueCount - failures.count, 0) }

    var body: some View {
        if reportedIssueCount > 0 || !failures.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label(
                    "\(max(reportedIssueCount, failures.count)) \(max(reportedIssueCount, failures.count) == 1 ? "track needs" : "tracks need") attention",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption.bold())
                .foregroundStyle(.orange)

                if let youtubeFallbackEnabled = run.youtubeFallbackEnabled {
                    Text(
                        youtubeFallbackEnabled
                            ? "YouTube fallback through yt-dlp was enabled for this run."
                            : "YouTube fallback was disabled; this run searched Soulseek only."
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                ForEach(failures) { failure in
                    HStack(alignment: .top, spacing: 10) {
                        Text(failure.position.map(String.init) ?? "—")
                            .font(.caption.bold().monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .trailing)
                            .accessibilityLabel(failure.position.map { "Track \($0)" } ?? "Track position unavailable")

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("Song: \(failure.title)")
                                    .font(.callout.weight(.semibold))
                                Spacer(minLength: 8)
                                Label(
                                    (failure.source ?? .unknown).label,
                                    systemImage: (failure.source ?? .unknown).systemImage
                                )
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                            }
                            Text("Artist: \(failure.artist)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let album = failure.album {
                                Text("Album: \(album)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(failure.reasonDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }

                if missingDetailCount > 0 {
                    Text("Sockseek reported \(missingDetailCount) additional \(missingDetailCount == 1 ? "track issue" : "track issues") without per-track reason data.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.2)))
        }
    }
}

struct ActiveSyncProgressView: View {
    let run: SyncRun
    var compact = false

    var body: some View {
        if let details = run.progressDetails {
            VStack(alignment: .leading, spacing: compact ? 6 : 10) {
                HStack {
                    Text(trackPosition(details))
                        .font(compact ? .caption.bold() : .callout.bold())
                    Spacer()
                    if let track = details.currentTrack {
                        StatusPill(
                            text: track.activity.rawValue,
                            systemImage: track.activity == .downloading ? "arrow.down.circle.fill" : "magnifyingglass",
                            tone: .blue
                        )
                    }
                }

                if let track = details.currentTrack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(compact ? .caption.weight(.semibold) : .headline)
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if track.activity == .downloading, let fraction = track.downloadFraction {
                        ProgressView(value: fraction)
                            .tint(.blue)
                            .accessibilityLabel("Download progress for \(track.artist), \(track.title)")
                            .accessibilityValue("\(Int(fraction * 100)) percent")
                        Text(downloadLabel(track))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                ProgressView(value: details.playlistFraction)
                    .accessibilityLabel("Playlist sync progress for \(run.playlistName)")
                    .accessibilityValue("\(details.completedTracks) of \(details.totalTracks) tracks finished")

                HStack(spacing: compact ? 8 : 14) {
                    metric("\(details.completedTracks)/\(details.totalTracks)", "Finished")
                    metric("\(run.counts.added + run.counts.upgraded)", "Synced")
                    metric("\(run.counts.alreadyBest)", "Already local")
                    metric("\(run.counts.unavailable)", "Failed")
                    if !compact || run.counts.needsReview > 0 {
                        metric("\(run.counts.needsReview)", "Review")
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: run.progress)
                    .accessibilityLabel("Sync progress for \(run.playlistName)")
                    .accessibilityValue("\(Int(run.progress * 100)) percent")
                Text(run.message).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func trackPosition(_ details: SyncProgressSnapshot) -> String {
        if let position = details.currentTrack?.position {
            return "Track \(position) of \(details.totalTracks)"
        }
        return "\(details.completedTracks) of \(details.totalTracks) tracks finished"
    }

    private func downloadLabel(_ track: CurrentTrackProgress) -> String {
        if let transferred = track.bytesTransferred, let total = track.totalBytes {
            return "\(Self.byteFormatter.string(fromByteCount: transferred)) of \(Self.byteFormatter.string(fromByteCount: total))"
        }
        if let fraction = track.downloadFraction { return "\(Int(fraction * 100))% downloaded" }
        return "Download started"
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.caption.bold().monospacedDigit())
            Text(label).font(.system(size: compact ? 8 : 9)).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter
    }()
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
