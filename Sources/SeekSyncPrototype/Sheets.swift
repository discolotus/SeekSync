import AppKit
import SwiftUI

struct AddPlaylistSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var name = ""
    @State private var validationMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "music.note.list")
                    .font(.title)
                    .foregroundStyle(.green)
                VStack(alignment: .leading) {
                    Text("Add a Spotify playlist").font(.title2.bold())
                    Text("Paste a playlist URL when Spotify browsing is unavailable.")
                        .foregroundStyle(.secondary)
                }
            }

            Form {
                TextField("Spotify playlist URL", text: $url, prompt: Text("https://open.spotify.com/playlist/…"))
                TextField("Display name (optional)", text: $name)
            }
            .formStyle(.grouped)

            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            HStack {
                Text("No network request is made when adding the URL.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add Playlist") {
                    if model.addPlaylist(url: url, name: name) {
                        dismiss()
                    } else {
                        validationMessage = "Enter a valid open.spotify.com playlist URL or Spotify playlist URI."
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
    }
}

struct SyncPreviewSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var showsCommand = false
    let pending: PendingSync

    private var policyBinding: Binding<YouTubePolicy> {
        Binding(
            get: { model.pendingSync?.youtubePolicy ?? pending.youtubePolicy },
            set: { model.pendingSync?.youtubePolicy = $0 }
        )
    }

    private var effectivePending: PendingSync {
        model.pendingSync ?? pending
    }

    private var isLiveSync: Bool {
        pending.playlist.executionKind == .sockseek
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 16) {
                        PlaylistArtwork(playlist: pending.playlist, size: 68)
                        VStack(alignment: .leading, spacing: 5) {
                            Label(
                                isLiveSync ? "READY TO SYNC" : "DEMO PREVIEW",
                                systemImage: isLiveSync ? "arrow.triangle.2.circlepath" : "eye"
                            )
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(isLiveSync ? Color.orange : Color.blue)

                            Text(pending.playlist.name)
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .lineLimit(2)
                            Text(playlistSubtitle)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 0) {
                        SyncSummaryItem(
                            label: "Save to",
                            value: model.settings.outputDirectory,
                            systemImage: "folder"
                        )
                        Divider().frame(height: 44).padding(.horizontal, 16)
                        SyncSummaryItem(
                            label: "Audio target",
                            value: model.settings.preferredFormatLabel,
                            systemImage: "waveform"
                        )
                        Divider().frame(height: 44).padding(.horizontal, 16)
                        SyncSummaryItem(
                            label: "Quality check",
                            value: model.settings.lookForPreferredQuality ? "On" : "Off",
                            systemImage: "checkmark.seal"
                        )
                    }
                    .padding(16)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("YouTube fallback")
                                    .font(.headline)
                                Text("Used only when Soulseek finds no suitable match.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Picker("YouTube fallback", selection: policyBinding) {
                                ForEach(YouTubePolicy.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 240)
                        }

                        Text(fallbackExplanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    DisclosureGroup(isExpanded: $showsCommand) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(model.command(for: effectivePending).displayString)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .padding(10)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                        .padding(.top, 8)
                    } label: {
                        Text("Show sanitized command")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let startBlocker {
                        SyncNotice(
                            title: "Sync can’t start yet",
                            detail: startBlocker,
                            systemImage: "xmark.octagon.fill",
                            color: .red
                        )
                    } else if isLiveSync {
                        SyncNotice(
                            title: "This starts a real download",
                            detail: "Sockseek will search for missing or below-target tracks. Files already meeting your target are left alone.",
                            systemImage: "arrow.down.circle.fill",
                            color: .orange
                        )
                    } else {
                        SyncNotice(
                            title: "Nothing will be downloaded",
                            detail: "This sample playlist only demonstrates the sync flow and never changes your music files.",
                            systemImage: "checkmark.shield.fill",
                            color: .blue
                        )
                    }
                }
                .padding(24)
            }

            Divider()
            HStack {
                if model.activeRun != nil, startBlocker == nil {
                    Text("This playlist will start automatically when the current sync finishes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(primaryButtonTitle) {
                    model.confirmPendingSync()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(startBlocker != nil)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(.bar)
        }
        .frame(width: 660, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var playlistSubtitle: String {
        let trackDetail = pending.playlist.trackCount == 0
            ? "Track list loads when the sync starts"
            : "\(pending.playlist.trackCount) tracks"
        return "\(trackDetail) · \(pending.trigger.rawValue) run"
    }

    private var fallbackExplanation: String {
        switch effectivePending.youtubePolicy {
        case .inherit:
            return model.settings.allowYouTubeFallback
                ? "Uses your saved setting: fallback is allowed. Fallback results may not meet the preferred audio target."
                : "Uses your saved setting: fallback is disabled for this run."
        case .allow:
            return "Allowed for this run. Fallback results may improve coverage but may not meet the preferred audio target."
        case .never:
            return "Disabled for this run. SeekSync will use Soulseek results only."
        }
    }

    private var startBlocker: String? {
        if model.activeRun?.playlistID == pending.playlist.id {
            return "This playlist is already syncing."
        }
        if model.isQueued(pending.playlist.id) {
            return "This playlist is already in the sync queue."
        }
        if pending.playlist.executionKind == .sockseek, model.isConfigDirty {
            return "Save or reload the edited settings before starting a live run."
        }
        if pending.playlist.executionKind == .sockseek, !model.dependencyState.isReady {
            return "Sockseek 3 must be ready before a live run can start."
        }
        return nil
    }

    private var primaryButtonTitle: String {
        if model.activeRun != nil { return isLiveSync ? "Queue Sync" : "Queue Preview" }
        return isLiveSync ? "Start Sync" : "Run Preview"
    }
}

struct BatchSyncPreviewSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var showsCommands = false
    let pending: PendingBatchSync

    private var policyBinding: Binding<YouTubePolicy> {
        Binding(
            get: { model.pendingBatchSync?.youtubePolicy ?? pending.youtubePolicy },
            set: { model.pendingBatchSync?.youtubePolicy = $0 }
        )
    }

    private var effectivePending: PendingBatchSync {
        model.pendingBatchSync ?? pending
    }

    private var hasLiveSyncs: Bool {
        pending.playlists.contains { $0.executionKind == .sockseek }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.blue)
                            .frame(width: 54, height: 54)
                            .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 13))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(hasLiveSyncs ? "READY TO SYNC" : "DEMO PREVIEW")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(0.8)
                                .foregroundStyle(hasLiveSyncs ? Color.orange : Color.blue)
                            Text("\(pending.playlists.count) playlists")
                                .font(.system(size: 25, weight: .bold, design: .rounded))
                            Text("They’ll run sequentially to protect the Soulseek session.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    HStack(spacing: 0) {
                        SyncSummaryItem(label: "Save to", value: model.settings.outputDirectory, systemImage: "folder")
                        Divider().frame(height: 44).padding(.horizontal, 16)
                        SyncSummaryItem(label: "Audio target", value: model.settings.preferredFormatLabel, systemImage: "waveform")
                        Divider().frame(height: 44).padding(.horizontal, 16)
                        SyncSummaryItem(label: "Known tracks", value: knownTrackCountLabel, systemImage: "music.note")
                    }
                    .padding(16)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("YouTube fallback")
                                    .font(.headline)
                                Text("Apply one fallback policy to this batch.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Picker("YouTube fallback", selection: policyBinding) {
                                ForEach(YouTubePolicy.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 240)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Queue order")
                            .font(.headline)
                        ForEach(Array(pending.playlists.enumerated()), id: \.element.id) { index, playlist in
                            HStack(spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.caption.bold().monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 22)
                                PlaylistArtwork(playlist: playlist, size: 34)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(playlist.name).font(.callout.weight(.medium)).lineLimit(1)
                                    Text(playlist.trackCount == 0 ? "Track list loads at sync" : "\(playlist.trackCount) tracks")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 3)
                        }
                    }
                    .padding(12)
                    .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))

                    DisclosureGroup("Show sanitized commands", isExpanded: $showsCommands) {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(effectivePending.playlists) { playlist in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(playlist.name).font(.caption.bold())
                                    Text(model.command(for: playlist, youtubePolicy: effectivePending.youtubePolicy).displayString)
                                        .font(.system(size: 10, design: .monospaced))
                                        .textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(.top, 8)
                    }
                    .font(.caption)

                    if let startBlocker {
                        SyncNotice(title: "Batch can’t start yet", detail: startBlocker, systemImage: "xmark.octagon.fill", color: .red)
                    } else if hasLiveSyncs {
                        SyncNotice(
                            title: "This starts real downloads",
                            detail: "Each playlist will search for missing or below-target tracks after you confirm. Cancelling the current sync advances to the next queued playlist.",
                            systemImage: "arrow.down.circle.fill",
                            color: .orange
                        )
                    } else {
                        SyncNotice(
                            title: "Nothing will be downloaded",
                            detail: "These sample playlists only demonstrate the sequential batch flow.",
                            systemImage: "checkmark.shield.fill",
                            color: .blue
                        )
                    }
                }
                .padding(24)
            }

            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(batchButtonTitle) {
                    model.confirmPendingBatchSync()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(startBlocker != nil)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(.bar)
        }
        .frame(width: 680, height: 620)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var knownTrackCountLabel: String {
        let count = pending.playlists.reduce(0) { $0 + $1.trackCount }
        return count == 0 ? "Loads at sync" : "\(count)"
    }

    private var startBlocker: String? {
        if hasLiveSyncs, model.isConfigDirty {
            return "Save or reload the edited settings before starting live syncs."
        }
        if hasLiveSyncs, !model.dependencyState.isReady {
            return "Sockseek 3 must be ready before live syncs can start."
        }
        return nil
    }

    private var batchButtonTitle: String {
        if model.activeRun != nil {
            return hasLiveSyncs ? "Queue \(pending.playlists.count) Syncs" : "Queue \(pending.playlists.count) Previews"
        }
        return hasLiveSyncs ? "Start \(pending.playlists.count) Syncs" : "Run \(pending.playlists.count) Previews"
    }
}

private struct SyncSummaryItem: View {
    let label: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(value)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SyncNotice: View {
    let title: String
    let detail: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(color.opacity(0.18), lineWidth: 1)
        }
    }
}
