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

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 16) {
                        PlaylistArtwork(playlist: pending.playlist, size: 72)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sync preview").font(.caption.bold()).foregroundStyle(.secondary)
                            Text(pending.playlist.name)
                                .font(.title2.bold())
                                .lineLimit(2)
                            Text("\(pending.playlist.trackCount) tracks · \(pending.trigger.rawValue.lowercased()) run")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusPill(
                            text: model.settings.executionMode.rawValue,
                            systemImage: model.settings.executionMode == .simulate ? "sparkles" : "arrow.down.circle.fill",
                            tone: model.settings.executionMode == .simulate ? .blue : .orange
                        )
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            LabeledContent("Destination", value: model.settings.outputDirectory)
                            LabeledContent("Preferred target", value: model.settings.preferredFormatLabel)
                            LabeledContent(
                                "Preferred-target recheck",
                                value: model.settings.lookForPreferredQuality ? "Enabled" : "Disabled"
                            )
                            Picker("YouTube fallback", selection: policyBinding) {
                                ForEach(YouTubePolicy.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            Text("Fallback is tried only when Soulseek returns no suitable candidate. It can improve coverage, but its output does not automatically satisfy the preferred target.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(4)
                    } label: {
                        Label("Effective policy", systemImage: "slider.horizontal.3")
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sanitized command").font(.caption.bold()).foregroundStyle(.secondary)
                        ScrollView(.horizontal) {
                            Text(model.command(for: effectivePending).displayString)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .padding(10)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                    }

                    if model.settings.executionMode == .live {
                        Label("This will start a real Sockseek download process. Existing indexed files are skipped unless they miss the preferred conditions.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.callout)
                    } else {
                        Label("Simulation exercises the app flow and changes no music files.", systemImage: "checkmark.shield.fill")
                            .foregroundStyle(.blue)
                            .font(.callout)
                    }

                    if let startBlocker {
                        Label(startBlocker, systemImage: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }
                .padding(24)
            }

            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(model.settings.executionMode == .live ? "Start Sockseek" : "Run Simulation") {
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
        .frame(width: 680, height: 500)
    }

    private var startBlocker: String? {
        if model.activeRun != nil { return "Another sync is already running." }
        if model.settings.executionMode == .live, model.isConfigDirty {
            return "Save or reload the edited settings before starting a live run."
        }
        if model.settings.executionMode == .live, !model.dependencyState.isReady {
            return "Sockseek 3 must be ready before a live run can start."
        }
        return nil
    }
}
