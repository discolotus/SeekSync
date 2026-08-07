import SwiftUI

struct LibraryInspectorVariant: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var showAddPlaylist: Bool
    @Binding var inspectorPresented: Bool

    var body: some View {
        GeometryReader { geometry in
            let mode = SeekSyncLayoutMode(width: geometry.size.width)
            layout(for: mode, availableWidth: geometry.size.width)
        }
    }

    @ViewBuilder
    private func layout(for mode: SeekSyncLayoutMode, availableWidth: CGFloat) -> some View {
        if mode.usesOverlayInspector {
            navigation(inlineInspectorWidth: nil)
                .overlay(alignment: .trailing) {
                    if inspectorPresented && model.selectedSection != .batchSync {
                        compactInspector(availableWidth: availableWidth)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: inspectorPresented)
        } else {
            navigation(
                inlineInspectorWidth: inspectorPresented && model.selectedSection != .batchSync
                    ? (mode == .wide ? 380 : 340)
                    : nil
            )
                .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: inspectorPresented)
        }
    }

    private func navigation(inlineInspectorWidth: CGFloat?) -> some View {
        NavigationSplitView {
            AppSidebar()
                .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 230)
        } detail: {
            HStack(spacing: 0) {
                primaryContent
                    .frame(minWidth: 440)

                if let inlineInspectorWidth {
                    Divider()
                    detailContent
                        .frame(width: inlineInspectorWidth)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private func compactInspector(availableWidth: CGFloat) -> some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.16)
                .contentShape(Rectangle())
                .onTapGesture { inspectorPresented = false }
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Playlist details")
                            .font(.headline)
                        Text("Compact view")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        inspectorPresented = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .help("Close playlist details")
                    .accessibilityLabel("Close playlist details")
                }
                .padding(.horizontal, 16)
                .frame(height: 50)
                .background(.bar)

                Divider()
                detailContent
            }
            .frame(width: min(420, max(360, availableWidth * 0.48)))
            .frame(maxHeight: .infinity)
            .background(.regularMaterial)
            .overlay(alignment: .leading) { Divider() }
            .shadow(color: .black.opacity(0.22), radius: 22, x: -8)
        }
    }

    @ViewBuilder
    private var primaryContent: some View {
        switch model.selectedSection {
        case .playlists:
            PlaylistLibraryScreen(onAdd: { showAddPlaylist = true })
        case .inventory:
            LibraryInventoryScreen()
        case .batchSync:
            BatchSyncScreen()
        case .syncPool:
            SyncPoolScreen()
        case .activity:
            ActivityScreen()
        case .attention:
            AttentionScreen()
        case .settings:
            SettingsScreen()
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch model.selectedSection {
        case .playlists:
            if let playlist = model.selectedPlaylist {
                PlaylistInspector(playlist: playlist)
            } else {
                EmptyStateView(
                    systemImage: "music.note",
                    title: "Select a playlist",
                    detail: "Its coverage, sync intent, and effective policy will appear here."
                )
            }
        case .inventory:
            LibraryInventoryExplainer()
        case .batchSync:
            PolicyExplainer()
        case .syncPool:
            if let nextPlan = model.plans.filter(\.enabled).min(by: { $0.nextRunAt < $1.nextRunAt }),
               let playlist = model.playlist(for: nextPlan) {
                VStack(alignment: .leading, spacing: 16) {
                    PlaylistArtwork(playlist: playlist, size: 110)
                    Text("Next daily check").font(.caption.bold()).foregroundStyle(.secondary)
                    Text(playlist.name).font(.title2.bold())
                    Text(nextPlan.nextRunAt.shortDateTimeLabel).foregroundStyle(.secondary)
                    Divider()
                    Text("If the Mac was asleep at the scheduled time, SeekSync checks when it next runs. Quitting SeekSync stops scheduling.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Run Now…") { model.showSyncPreview(for: playlist) }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(22)
            } else {
                PolicyExplainer()
            }
        case .activity:
            if let run = model.runs.first {
                RunDetailView(run: run)
            } else {
                EmptyStateView(systemImage: "clock", title: "No runs yet", detail: "Activity details will appear here.")
            }
        case .attention, .settings:
            PolicyExplainer()
        }
    }
}

private struct RunDetailView: View {
    let run: SyncRun

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(run.phase.rawValue.uppercased()).font(.caption.bold()).tracking(1).foregroundStyle(.secondary)
                Text(run.playlistName).font(.title2.bold())
                Text(run.message).foregroundStyle(.secondary)
                if run.phase.isActive {
                    ActiveSyncProgressView(run: run)
                } else {
                    ProgressView(value: run.progress)
                        .accessibilityLabel("Sync progress for \(run.playlistName)")
                        .accessibilityValue("\(Int(run.progress * 100)) percent")
                    RunCountsView(counts: run.counts)
                }
                TrackFailureDetailsView(run: run)
                Divider()
                Text("Sanitized command").font(.caption.bold()).foregroundStyle(.secondary)
                Text(run.commandPreview)
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
                Divider()
                Text("Result buckets stay separate: an unavailable or ambiguous track is never hidden inside a generic success state.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(22)
        }
    }
}
