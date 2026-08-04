import SwiftUI

struct LibraryInspectorVariant: View {
    @EnvironmentObject private var model: AppModel
    @Binding var showAddPlaylist: Bool
    @Binding var inspectorPresented: Bool

    var body: some View {
        NavigationSplitView {
            AppSidebar()
                .padding(.top, 48)
                .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 220)
        } detail: {
            primaryContent
                .padding(.top, 48)
                .frame(minWidth: 380)
        }
        .navigationSplitViewStyle(.balanced)
        .inspector(isPresented: $inspectorPresented) {
            detailContent
                .padding(.top, 48)
                .inspectorColumnWidth(min: 300, ideal: 340, max: 400)
        }
    }

    @ViewBuilder
    private var primaryContent: some View {
        switch model.selectedSection {
        case .playlists:
            PlaylistLibraryScreen(onAdd: { showAddPlaylist = true })
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
                ProgressView(value: run.progress)
                    .accessibilityLabel("Sync progress for \(run.playlistName)")
                    .accessibilityValue("\(Int(run.progress * 100)) percent")
                RunCountsView(counts: run.counts)
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
