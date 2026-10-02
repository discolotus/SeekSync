import Foundation
import SwiftUI

/// The running commentary for a library preview: stage progress while a pass
/// is in flight, and the outcome afterwards.
///
/// A preview that fails leaves no analysis behind, so without this the detail
/// screen would answer a press of "Preview Library Reuse" with nothing at all.
struct LibraryAnalysisStatusLabel: View {
    let message: String?
    let isAnalyzing: Bool
    let hasAnalysis: Bool

    var body: some View {
        if isAnalyzing {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(message ?? "Reading playlist metadata and comparing local tag matches…")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if let message {
            Label(message, systemImage: symbolName(for: message))
                .font(.caption)
                .foregroundStyle(style(for: message))
        }
    }

    private var isFailure: Bool { !hasAnalysis }

    private func symbolName(for message: String) -> String {
        isFailure || message.localizedCaseInsensitiveContains("but")
            ? "exclamationmark.triangle.fill"
            : "info.circle"
    }

    private func style(for message: String) -> Color {
        if isFailure { return .red }
        return message.localizedCaseInsensitiveContains("but") ? .orange : .secondary
    }
}

/// A compact, reusable readout for a completed library-reuse analysis.
///
/// The card intentionally distinguishes a qualifying library reference from a
/// below-target local match: only the former can replace a new download.
struct LibraryReuseAnalysisSummaryCard: View {
    let analysis: PlaylistLibraryAnalysis
    var onShowTracks: (() -> Void)?

    private var counts: AnalysisCounts {
        analysis.tracks.reduce(into: AnalysisCounts()) { result, track in
            switch track.disposition {
            case .libraryReference:
                result.libraryReferences += 1
            case .libraryBelowThreshold:
                result.belowThreshold += 1
            case .downloadRequired:
                result.downloadRequired += 1
            case .downloaded:
                result.downloaded += 1
            case .unavailable, .unknown:
                result.unavailable += 1
            }
        }
    }

    private var referenceExplanation: String {
        let filePhrase = counts.libraryReferences == 1 ? "file stays" : "files stay"
        let possessive = counts.libraryReferences == 1 ? "its" : "their"
        let object = counts.libraryReferences == 1 ? "it" : "them"
        return "\(counts.libraryReferences) qualifying \(filePhrase) in the existing library. SeekSync records \(possessive) original path in the playlist instead of copying or downloading \(object)."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label("Existing-library analysis", systemImage: "externaldrive.fill.badge.checkmark")
                    .font(.headline)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(analysis.basisLabel)
                    Text(analysis.analyzedAt.relativeLabel)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 92), spacing: 8, alignment: .leading)],
                alignment: .leading,
                spacing: 8
            ) {
                AnalysisMetric(
                    value: counts.libraryReferences,
                    label: "References",
                    systemImage: "link",
                    color: .green
                )
                AnalysisMetric(
                    value: counts.belowThreshold,
                    label: "Below target",
                    systemImage: "arrow.down.right",
                    color: .orange
                )
                AnalysisMetric(
                    value: counts.downloadRequired,
                    label: "Need download",
                    systemImage: "arrow.down.circle",
                    color: .blue
                )
                AnalysisMetric(
                    value: counts.downloaded,
                    label: "Downloaded",
                    systemImage: "checkmark.circle",
                    color: .green
                )
                AnalysisMetric(
                    value: counts.unavailable,
                    label: "Unavailable",
                    systemImage: "questionmark.circle",
                    color: counts.unavailable > 0 ? .red : .secondary
                )
            }

            if counts.libraryReferences > 0 {
                Text(referenceExplanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No qualifying library references were found. Existing files that miss the reuse target remain in place and are not selected for reuse.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let onShowTracks {
                Button(action: onShowTracks) {
                    Label("View all \(analysis.tracks.count) tracks", systemImage: "list.bullet.rectangle")
                }
                .controlSize(.small)
            }
        }
        .padding(14)
        .background(Color.accentColor.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.accentColor.opacity(0.16))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Existing-library analysis for \(analysis.playlistName)")
    }
}

/// A complete, inspectable inventory of a playlist analysis.
///
/// Below-threshold local matches deliberately appear first, ahead of files that
/// qualify as references, so the user sees every proposed replacement before
/// confirming a sync.
struct PlaylistTrackListSheet: View {
    @State private var query = ""
    @State private var selectedDisposition: PlaylistTrackDisposition?
    @Environment(\.dismiss) private var dismiss

    let analysis: PlaylistLibraryAnalysis

    private var counts: AnalysisCounts {
        analysis.tracks.reduce(into: AnalysisCounts()) { result, track in
            switch track.disposition {
            case .libraryReference:
                result.libraryReferences += 1
            case .libraryBelowThreshold:
                result.belowThreshold += 1
            case .downloadRequired:
                result.downloadRequired += 1
            case .downloaded:
                result.downloaded += 1
            case .unavailable, .unknown:
                result.unavailable += 1
            }
        }
    }

    private var belowThresholdTracks: [PlaylistTrackRecord] {
        sortedTracks { track in
            if case .libraryBelowThreshold = track.disposition { return true }
            return false
        }
    }

    private var libraryReferenceTracks: [PlaylistTrackRecord] {
        sortedTracks { track in
            if case .libraryReference = track.disposition { return true }
            return false
        }
    }

    private var downloadedTracks: [PlaylistTrackRecord] {
        sortedTracks { track in
            if case .downloaded = track.disposition { return true }
            return false
        }
    }

    private var downloadRequiredTracks: [PlaylistTrackRecord] {
        sortedTracks { track in
            if case .downloadRequired = track.disposition { return true }
            return false
        }
    }

    private var unavailableTracks: [PlaylistTrackRecord] {
        sortedTracks { track in
            switch track.disposition {
            case .unavailable, .unknown: return true
            default: return false
            }
        }
    }

    private var targetLabel: String {
        analysis.targetLabel
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack {
                TextField("Search title, artist, album, or path", text: $query)
                    .textFieldStyle(.roundedBorder)
                Picker("Show", selection: $selectedDisposition) {
                    Text("All tracks").tag(Optional<PlaylistTrackDisposition>.none)
                    Text("Below target / upgrade pending").tag(Optional(PlaylistTrackDisposition.libraryBelowThreshold))
                    Text("In library").tag(Optional(PlaylistTrackDisposition.libraryReference))
                    Text("Downloaded").tag(Optional(PlaylistTrackDisposition.downloaded))
                    Text("Download required").tag(Optional(PlaylistTrackDisposition.downloadRequired))
                    Text("Unavailable").tag(Optional(PlaylistTrackDisposition.unavailable))
                }
                .frame(width: 280)
            }
            .padding(.horizontal, 22).padding(.bottom, 14)
            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    analysisOverview

                    if counts.belowThreshold > 0 {
                        belowThresholdNotice
                    }

                    TrackAnalysisSection(
                        title: "Below reuse target",
                        detail: "These tracks already exist locally—in the selected library or downloads—but do not satisfy all current reuse conditions. Those include the audio target and Sockseek's metadata matching. Playable copies stay in exports while future syncs look for replacements.",
                        systemImage: "arrow.down.right.circle.fill",
                        color: .orange,
                        tracks: belowThresholdTracks,
                        targetLabel: targetLabel
                    )

                    TrackAnalysisSection(
                        title: "Existing-library references",
                        detail: "These files meet the target and stay at their original paths. The generated playlist points to them there.",
                        systemImage: "link.circle.fill",
                        color: .green,
                        tracks: libraryReferenceTracks,
                        targetLabel: targetLabel
                    )

                    TrackAnalysisSection(
                        title: "Downloaded",
                        detail: "These tracks are in SeekSync's destination. Downloaded does not guarantee they meet every reuse condition; refresh analysis to check the current target.",
                        systemImage: "checkmark.circle.fill",
                        color: .green,
                        tracks: downloadedTracks,
                        targetLabel: targetLabel
                    )

                    TrackAnalysisSection(
                        title: "Download required",
                        detail: "No qualifying existing-library file was selected. A confirmed sync will search for these tracks.",
                        systemImage: "arrow.down.circle.fill",
                        color: .blue,
                        tracks: downloadRequiredTracks,
                        targetLabel: targetLabel
                    )

                    TrackAnalysisSection(
                        title: "Unavailable or unknown",
                        detail: "SeekSync could not establish a usable local or downloaded file for these tracks.",
                        systemImage: "questionmark.circle.fill",
                        color: .red,
                        tracks: unavailableTracks,
                        targetLabel: targetLabel
                    )
                }
                .padding(22)
            }
        }
        .frame(minWidth: 760, idealWidth: 860, minHeight: 620, idealHeight: 720)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "list.bullet.rectangle.portrait.fill")
                .font(.system(size: 28))
                .foregroundStyle(.blue)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("PLAYLIST TRACKS")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                Text(analysis.playlistName)
                    .font(.title2.bold())
                    .lineLimit(2)
                Text("\(analysis.tracks.count) tracks · \(analysis.basisLabel.lowercased()) · \(analysis.analyzedAt.shortDateTimeLabel)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(22)
    }

    private var analysisOverview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label("Quality target", systemImage: "waveform.badge.magnifyingglass")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(targetLabel)
                    .font(.callout.weight(.semibold))
                    .textSelection(.enabled)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label("Existing library", systemImage: "externaldrive")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(analysis.sourceLibraryPath)
                    .font(.callout.monospaced())
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(analysis.sourceLibraryPath)
            }

            Text("Referenced files are not copied into the downloads folder. They stay in this library, and their original paths are written into the generated playlist file.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(.quaternary.opacity(0.32), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var belowThresholdNotice: some View {
        let subject = counts.belowThreshold == 1 ? "local track is" : "local tracks are"
        return VStack(alignment: .leading, spacing: 5) {
            Label(
                "\(counts.belowThreshold) \(subject) below your reuse target",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.headline)
            .foregroundStyle(.orange)

            Text("These files are shown first below. A sync will leave the existing copies alone and look for replacements that satisfy the reuse conditions. The audio target is \(targetLabel).")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.orange.opacity(0.2))
        }
        .accessibilityElement(children: .combine)
    }

    private func sortedTracks(
        matching predicate: (PlaylistTrackRecord) -> Bool
    ) -> [PlaylistTrackRecord] {
        analysis.filteredTracks(query: query, disposition: selectedDisposition)
            .filter(predicate)
            .sorted { $0.seed.position < $1.seed.position }
    }
}

private struct TrackAnalysisSection: View {
    let title: String
    let detail: String
    let systemImage: String
    let color: Color
    let tracks: [PlaylistTrackRecord]
    let targetLabel: String

    var body: some View {
        if !tracks.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label(title, systemImage: systemImage)
                        .font(.headline)
                        .foregroundStyle(color)
                    Text("\(tracks.count)")
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 0) {
                    ForEach(Array(tracks.enumerated()), id: \.offset) { offset, track in
                        PlaylistAnalysisTrackRow(track: track, targetLabel: targetLabel)
                        if offset < tracks.count - 1 { Divider() }
                    }
                }
                .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.secondary.opacity(0.14))
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(title), \(tracks.count) tracks")
        }
    }
}

private struct PlaylistAnalysisTrackRow: View {
    let track: PlaylistTrackRecord
    let targetLabel: String

    private var status: (label: String, systemImage: String, color: Color) {
        switch track.disposition {
        case .libraryReference:
            return ("Library reference", "link", .green)
        case .libraryBelowThreshold:
            return ("Below target", "arrow.down.right", .orange)
        case .downloadRequired:
            return ("Will download", "arrow.down", .blue)
        case .downloaded:
            return ("Downloaded", "checkmark", .green)
        case .unavailable:
            return ("Unavailable", "xmark", .red)
        case .unknown:
            return ("Unknown", "questionmark", .secondary)
        }
    }

    private var lengthLabel: String? {
        guard let lengthSeconds = track.seed.lengthSeconds, lengthSeconds > 0 else { return nil }
        return String(format: "%d:%02d", lengthSeconds / 60, lengthSeconds % 60)
    }

    private var qualityLabel: String {
        if let quality = track.quality { return quality.displayLabel }
        switch track.disposition {
        case .downloadRequired:
            return "Requested: \(targetLabel)"
        case .unavailable, .unknown:
            return "Quality unavailable"
        case .libraryBelowThreshold:
            return "Below \(targetLabel)"
        case .libraryReference, .downloaded:
            return "Quality not reported"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(track.seed.position)")
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
                .accessibilityLabel("Track \(track.seed.position)")

            VStack(alignment: .leading, spacing: 4) {
                Text(track.seed.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)
                Text(track.seed.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let album = track.seed.album, !album.isEmpty {
                    Text("Album: \(album)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let path = track.localPath, !path.isEmpty {
                    Label(path, systemImage: "folder")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(path)
                        .accessibilityLabel("File path: \(path)")
                } else {
                    Text("No local file path")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 6) {
                Label(status.label, systemImage: status.systemImage)
                    .font(.caption2.bold())
                    .foregroundStyle(status.color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(status.color.opacity(0.11), in: Capsule())

                Text(qualityLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)

                if let lengthLabel {
                    Text(lengthLabel)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel("Duration \(lengthLabel)")
                }
            }
            .frame(minWidth: 138, maxWidth: 210, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        var parts = [
            "Track \(track.seed.position)",
            track.seed.title,
            "by \(track.seed.artist)",
            status.label,
            qualityLabel
        ]
        if let album = track.seed.album, !album.isEmpty { parts.append("album \(album)") }
        if let path = track.localPath, !path.isEmpty { parts.append("path \(path)") }
        return parts.joined(separator: ", ")
    }
}

private struct AnalysisMetric: View {
    let value: Int
    let label: String
    let systemImage: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label("\(value)", systemImage: systemImage)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}

private struct AnalysisCounts {
    var libraryReferences = 0
    var belowThreshold = 0
    var downloadRequired = 0
    var downloaded = 0
    var unavailable = 0
}
