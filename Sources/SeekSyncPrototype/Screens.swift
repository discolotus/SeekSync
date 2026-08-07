import AppKit
import SwiftUI

struct AppSidebar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            SeekSyncBrandHeader()
            .padding(14)

            List(selection: $model.selectedSection) {
                Section("Library") {
                    sidebarRow(.playlists, badge: nil)
                    sidebarRow(.batchSync, badge: model.queuedSyncCount)
                    sidebarRow(.syncPool, badge: model.plans.count)
                }
                Section("Runs") {
                    sidebarRow(.activity, badge: model.activeRun == nil ? nil : 1)
                    sidebarRow(.attention, badge: model.attentionCount)
                }
                Section {
                    sidebarRow(.settings, badge: nil)
                }
            }
            .listStyle(.sidebar)

            VStack(alignment: .leading, spacing: 8) {
                DependencyPill(state: model.dependencyState)
                StatusPill(
                    text: model.spotifyState.label,
                    systemImage: "music.note",
                    tone: spotifyTone
                )
                if case .failed(let detail) = model.spotifyState {
                    Text(detail)
                        .font(.system(size: 9))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(model.spotifyCatalogLoaded ? "Real playlists · syncs require confirmation" : "Demo catalog · preview only")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
        }
    }

    private func sidebarRow(_ section: AppSection, badge: Int?) -> some View {
        Label {
            HStack {
                Text(section.rawValue)
                Spacer()
                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }
        } icon: {
            Image(systemName: section.systemImage)
        }
        .tag(section)
    }

    private var spotifyTone: StatusPill.Tone {
        switch model.spotifyState {
        case .connected, .cached: return .green
        case .failed: return .red
        default: return .neutral
        }
    }
}

struct BatchSyncScreen: View {
    @EnvironmentObject private var model: AppModel
    @State private var searchText = ""
    @State private var selectedPlaylistIDs: Set<String> = []

    private let columns = [
        GridItem(.adaptive(minimum: 156, maximum: 210), spacing: 14, alignment: .top)
    ]

    private var playlists: [Playlist] {
        PlaylistLibrary.filtered(model.allPlaylists, searchText: searchText)
    }

    private var selectedPlaylists: [Playlist] {
        model.allPlaylists.filter { selectedPlaylistIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .bottom) {
                        heading
                        Spacer()
                        selectionButtons
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        heading
                        selectionButtons
                    }
                }

                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search playlists", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))

                    StatusPill(
                        text: "\(playlists.count) shown",
                        systemImage: nil
                    )
                }

                if let activeRun = model.activeRun {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Syncing \(activeRun.playlistName)")
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        if model.queuedSyncCount > 0 {
                            Text("· \(model.queuedSyncCount) queued")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(model.queuedSyncCount > 0 ? "Cancel batch" : "Cancel sync") {
                            model.cancelActiveRun()
                        }
                        .controlSize(.small)
                    }
                    .padding(10)
                    .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                }
            }
            .padding(20)

            Divider()

            if playlists.isEmpty {
                EmptyStateView(
                    systemImage: "magnifyingglass",
                    title: "No playlists match",
                    detail: "Try a different name, owner, or description."
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                        ForEach(playlists) { playlist in
                            BatchPlaylistCard(
                                playlist: playlist,
                                isSelected: selectedPlaylistIDs.contains(playlist.id),
                                action: { toggleSelection(for: playlist) }
                            )
                        }
                    }
                    .padding(16)
                }
            }

            Divider()
            HStack(spacing: 12) {
                if selectedPlaylists.isEmpty {
                    Text("Select playlists to create a one-time sync queue.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(selectedPlaylists.count) selected")
                        .font(.headline)
                    Text(trackSummary)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.showBatchSyncPreview(for: selectedPlaylists)
                } label: {
                    Label("Review & Sync", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedPlaylists.isEmpty || model.activeRun != nil)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.bar)
        }
    }

    private var heading: some View {
        SectionHeader(
            eyebrow: "One-time queue",
            title: "Batch sync",
            detail: "Choose several playlists, then review and run them one at a time."
        )
        .fixedSize(horizontal: false, vertical: true)
    }

    private var selectionButtons: some View {
        HStack {
            Button("Select shown") {
                selectedPlaylistIDs.formUnion(playlists.map(\.id))
            }
            .disabled(playlists.isEmpty || playlists.allSatisfy { selectedPlaylistIDs.contains($0.id) })
            Button("Clear") { selectedPlaylistIDs.removeAll() }
                .disabled(selectedPlaylistIDs.isEmpty)
        }
    }

    private var trackSummary: String {
        let total = selectedPlaylists.reduce(0) { $0 + $1.trackCount }
        return total > 0 ? "· \(total) known tracks" : ""
    }

    private func toggleSelection(for playlist: Playlist) {
        if selectedPlaylistIDs.contains(playlist.id) {
            selectedPlaylistIDs.remove(playlist.id)
        } else {
            selectedPlaylistIDs.insert(playlist.id)
        }
    }
}

private struct BatchPlaylistCard: View {
    let playlist: Playlist
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    PlaylistArtwork(playlist: playlist, size: 116)
                        .frame(maxWidth: .infinity)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.9), isSelected ? Color.accentColor : Color.black.opacity(0.35))
                        .padding(7)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(playlist.name)
                        .font(.headline)
                        .lineLimit(2)
                    Text(playlist.owner)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(playlist.trackCount == 0 ? "Tracks load at sync" : "\(playlist.trackCount) tracks")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                isSelected ? Color.accentColor.opacity(0.11) : Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.18), lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(playlist.name), \(playlist.owner), \(playlist.trackCount == 0 ? "track count loads at sync" : "\(playlist.trackCount) tracks")")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct PlaylistLibraryScreen: View {
    @EnvironmentObject private var model: AppModel
    let onAdd: () -> Void
    var compact = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .bottom) {
                        libraryHeading
                        Spacer()
                        HStack {
                            refreshButton(labelStyle: true)
                            addButton(labelStyle: true)
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        libraryHeading
                        HStack {
                            Spacer()
                            refreshButton(labelStyle: true)
                            addButton(labelStyle: true)
                        }
                    }
                }
                if !model.spotifyCatalogLoaded {
                    Label("Demo data · preview only — connect or refresh Spotify to replace these sample playlists.", systemImage: "testtube.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Demo data. Preview only. Sample playlists are currently visible.")
                }
                if let activeRun = model.activeRun {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("Syncing \(activeRun.playlistName)", systemImage: "arrow.down.circle.fill")
                                .font(.headline)
                                .foregroundStyle(.blue)
                            Spacer()
                            Button("Cancel") { model.cancelActiveRun() }
                                .controlSize(.small)
                        }
                        ActiveSyncProgressView(run: activeRun)
                    }
                    .padding(12)
                    .background(Color.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.blue.opacity(0.2))
                    }
                    .accessibilityElement(children: .contain)
                }
                HStack {
                    TextField("Search playlists", text: $model.searchText)
                        .textFieldStyle(.roundedBorder)
                    StatusPill(
                        text: "\(model.allPlaylists.count) \(model.allPlaylists.count == 1 ? "playlist" : "playlists")",
                        systemImage: nil
                    )
                }
            }
            .padding(20)

            Divider()

            if model.filteredPlaylists.isEmpty {
                EmptyStateView(
                    systemImage: "music.note.list",
                    title: model.spotifyCatalogLoaded && model.allPlaylists.isEmpty ? "No Spotify playlists found" : "No playlists match",
                    detail: model.spotifyCatalogLoaded && model.allPlaylists.isEmpty
                        ? "Add a playlist URL or refresh after creating one in Spotify."
                        : "Try a different search or add a Spotify playlist URL."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.filteredPlaylists) { playlist in
                            PlaylistRow(playlist: playlist, compact: compact)
                            Divider().padding(.leading, compact ? 64 : 76)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private var libraryHeading: some View {
        SectionHeader(
            eyebrow: "Spotify",
            title: "Your playlists",
            detail: "Pick a playlist, run it once, or keep it synced daily."
        )
        .fixedSize(horizontal: false, vertical: true)
    }

    private func refreshButton(labelStyle: Bool) -> some View {
        Button { model.refreshSpotify() } label: {
            if labelStyle {
                Label("Refresh", systemImage: "arrow.clockwise")
            } else {
                Image(systemName: "arrow.clockwise")
            }
        }
        .disabled(model.spotifyState == .loading)
        .help("Refresh Spotify playlists")
        .accessibilityLabel("Refresh Spotify playlists")
    }

    private func addButton(labelStyle: Bool) -> some View {
        Button(action: onAdd) {
            if labelStyle {
                Label("Add URL", systemImage: "plus")
            } else {
                Image(systemName: "plus")
            }
        }
        .buttonStyle(.borderedProminent)
        .help("Add Spotify playlist URL")
        .accessibilityLabel("Add Spotify playlist URL")
    }
}

struct PlaylistInspector: View {
    @EnvironmentObject private var model: AppModel
    let playlist: Playlist
    @State private var showCommand = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 14) {
                    PlaylistArtwork(playlist: playlist, size: 172)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("PLAYLIST").font(.caption2.bold()).tracking(1.2).foregroundStyle(.secondary)
                        Text(playlist.name).font(.system(size: 27, weight: .bold, design: .rounded))
                        Text("By \(playlist.owner) · \(playlist.trackCount == 0 ? "track count loads at sync" : "\(playlist.trackCount) tracks")")
                            .foregroundStyle(.secondary)
                        Text(playlist.detail).font(.callout).foregroundStyle(.secondary).padding(.top, 2)
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        syncButton
                        dailySyncButton
                    }
                    VStack(spacing: 10) {
                        syncButton
                        dailySyncButton
                    }
                }
                .controlSize(.large)

                if playlist.trackCount > 0 {
                    GroupBox("Local coverage") {
                        VStack(alignment: .leading, spacing: 10) {
                            ViewThatFits(in: .horizontal) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text("\(playlist.localCount)").font(.title.bold())
                                    Text("of \(playlist.trackCount) indexed locally")
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: true, vertical: false)
                                    Spacer()
                                    coveragePercent
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text("\(playlist.localCount) of \(playlist.trackCount)")
                                            .font(.title.bold())
                                        Spacer()
                                        coveragePercent
                                    }
                                    Text("indexed locally")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            ProgressView(value: playlist.coverage)
                                .accessibilityLabel("Local coverage for \(playlist.name)")
                                .accessibilityValue("\(playlist.localCount) of \(playlist.trackCount) tracks available locally")
                            ViewThatFits(in: .horizontal) {
                                HStack { coveragePills }
                                VStack(alignment: .leading, spacing: 6) { coveragePills }
                            }
                        }
                        .padding(4)
                    }
                }

                GroupBox("Effective download policy") {
                    VStack(alignment: .leading, spacing: 10) {
                        AdaptiveValueRow("Destination", value: model.settings.outputDirectory)
                        AdaptiveValueRow("Target", value: model.settings.preferredFormatLabel)
                        AdaptiveValueRow("YouTube fallback", value: effectiveYouTubeLabel)
                        AdaptiveValueRow("Recheck", value: model.settings.lookForPreferredQuality ? "Files below preferred conditions" : "Missing files only")
                        Divider()
                        Text("“Preferred quality” is a technical target. Sockseek will revisit an indexed lossy file when FLAC is preferred, but it cannot judge mastering quality.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(4)
                }

                DisclosureGroup("Command preview", isExpanded: $showCommand) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.command(for: playlist).displayString)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Copy command", systemImage: "doc.on.doc") {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(model.command(for: playlist).displayString, forType: .string)
                        }
                        .controlSize(.small)
                    }
                    .padding(.top, 6)
                }
                .font(.caption)
            }
            .padding(22)
        }
        .background(.background.opacity(0.6))
    }

    private var syncButton: some View {
        Button {
            model.showSyncPreview(for: playlist)
        } label: {
            Label("Sync Now…", systemImage: "arrow.down.circle.fill")
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
    }

    private var dailySyncButton: some View {
        Button {
            model.togglePlan(for: playlist)
        } label: {
            Label(
                model.isInPool(playlist.id) ? "Daily sync on" : "Enable daily sync",
                systemImage: model.isInPool(playlist.id) ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath"
            )
            .lineLimit(1)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private var coveragePercent: some View {
        Text("\(Int(playlist.coverage * 100))%")
            .font(.headline.monospacedDigit())
    }

    @ViewBuilder
    private var coveragePills: some View {
        if playlist.missingCount > 0 {
            StatusPill(text: "\(playlist.missingCount) missing", systemImage: "plus", tone: .orange)
        }
        if playlist.upgradeCandidates > 0 {
            StatusPill(text: "\(playlist.upgradeCandidates) below target", systemImage: "arrow.up", tone: .blue)
        }
        if playlist.needsReview > 0 {
            StatusPill(text: "\(playlist.needsReview) review", systemImage: "questionmark", tone: .red)
        }
    }

    private var effectiveYouTubeLabel: String {
        switch model.plan(for: playlist.id)?.youtubePolicy ?? .inherit {
        case .allow: return "Allowed for this playlist"
        case .never: return "Disabled for this playlist"
        case .inherit: return model.settings.allowYouTubeFallback ? "Allowed by default" : "Disabled by default"
        }
    }
}

private struct AdaptiveValueRow: View {
    let label: String
    let value: String

    init(_ label: String, value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(label)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                Text(value)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct SyncPoolScreen: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom) {
                SectionHeader(
                    eyebrow: "Daily automation",
                    title: "Sync pool",
                    detail: "Checks missing tracks and preferred-format targets while SeekSync is open."
                )
                Spacer()
                StatusPill(text: scheduleLabel, systemImage: "clock", tone: .blue)
            }
            .padding(20)
            Divider()

            if model.plans.isEmpty {
                EmptyStateView(systemImage: "arrow.triangle.2.circlepath", title: "No daily syncs", detail: "Choose Keep Synced on a playlist to add it here.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.plans) { plan in
                            if let playlist = model.playlist(for: plan) {
                                SyncPlanRow(plan: plan, playlist: playlist)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private var scheduleLabel: String {
        String(format: "Daily · %d:%02d", model.settings.dailyHour, model.settings.dailyMinute)
    }
}

struct SyncPlanRow: View {
    @EnvironmentObject private var model: AppModel
    let plan: SyncPlan
    let playlist: Playlist

    private var enabledBinding: Binding<Bool> {
        Binding(get: { plan.enabled }, set: { model.setPlanEnabled(plan.id, enabled: $0) })
    }

    private var policyBinding: Binding<YouTubePolicy> {
        Binding(get: { plan.youtubePolicy }, set: { model.setYouTubePolicy(plan.id, policy: $0) })
    }

    var body: some View {
        HStack(spacing: 14) {
            Toggle("", isOn: enabledBinding)
                .labelsHidden()
                .accessibilityLabel("Daily sync for \(playlist.name)")
            PlaylistArtwork(playlist: playlist, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name).font(.headline)
                Text(plan.enabled ? "Next check \(plan.nextRunAt.relativeLabel)" : "Paused")
                    .font(.caption)
                    .foregroundColor(plan.enabled ? .secondary : .orange)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Picker("YouTube", selection: policyBinding) {
                    ForEach(YouTubePolicy.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .frame(width: 112)
                Text("YouTube fallback").font(.caption2).foregroundStyle(.secondary)
            }
            Button("Run Now…") { model.showSyncPreview(for: playlist) }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }
}

struct ActivityScreen: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                SectionHeader(eyebrow: "Ledger", title: "Activity", detail: "Every run keeps a visible trigger, policy, and outcome.")
                Spacer()
                if let active = model.activeRun {
                    StatusPill(text: active.phase.rawValue, systemImage: "bolt.fill", tone: .blue)
                    Button("Cancel") { model.cancelActiveRun() }
                }
            }
            .padding(20)
            Divider()
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(model.runs) { run in RunRow(run: run) }
                }
                .padding(16)
            }
        }
    }
}

struct RunRow: View {
    let run: SyncRun
    @State private var showCommand = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: phaseIcon)
                    .font(.title2)
                    .foregroundStyle(phaseColor)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(run.playlistName).font(.headline)
                    Text("\(run.trigger.rawValue) · \(run.startedAt.relativeLabel) · \(run.phase.rawValue)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if run.phase.isActive {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("\(run.phase.rawValue) for \(run.playlistName)")
                }
            }
            if run.phase.isActive {
                ActiveSyncProgressView(run: run)
            } else {
                RunCountsView(counts: run.counts)
                Text(run.message).font(.caption).foregroundStyle(.secondary)
            }
            TrackFailureDetailsView(run: run)
            DisclosureGroup("Sanitized command", isExpanded: $showCommand) {
                Text(run.commandPreview)
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 5)
            }
            .font(.caption)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }

    private var phaseIcon: String {
        switch run.phase {
        case .completed: return "checkmark.circle.fill"
        case .partial: return "exclamationmark.circle.fill"
        case .failed, .cancelled: return "xmark.circle.fill"
        default: return "arrow.down.circle.fill"
        }
    }
    private var phaseColor: Color {
        switch run.phase {
        case .completed: return .green
        case .partial: return .orange
        case .failed, .cancelled: return .red
        default: return .blue
        }
    }
}

struct AttentionScreen: View {
    @EnvironmentObject private var model: AppModel
    var opensInspector = true

    private var playlists: [Playlist] { model.allPlaylists.filter(model.needsAttention) }

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(eyebrow: "Review queue", title: "Needs attention", detail: "Failures and ambiguous matches stay visible instead of being counted as success.")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            Divider()
            if playlists.isEmpty {
                EmptyStateView(systemImage: "checkmark.circle", title: "Nothing needs attention", detail: "Failed and ambiguous items will appear here.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(playlists) { playlist in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 12) {
                                    PlaylistArtwork(playlist: playlist, size: 48)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(playlist.name).font(.headline)
                                        Text(attentionDetail(for: playlist))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button(opensInspector ? "Inspect" : "Review…") {
                                        if opensInspector {
                                            model.select(playlist)
                                            model.selectedSection = .playlists
                                        } else {
                                            model.showSyncPreview(for: playlist)
                                        }
                                    }
                                }

                                if let run = model.latestRun(for: playlist.id) {
                                    TrackFailureDetailsView(run: run)
                                }
                            }
                            .padding(14)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private func attentionDetail(for playlist: Playlist) -> String {
        if playlist.needsReview > 0 {
            return "\(playlist.needsReview) metadata matches need review"
        }
        return "The latest sync did not complete cleanly"
    }
}

struct SettingsScreen: View {
    @EnvironmentObject private var model: AppModel
    @State private var showArmConfirmation = false
    @State private var showResetConfirmation = false
    @State private var showReloadConfirmation = false
    @State private var showOutputDirectoryDecision = false
    @State private var outputDirectoryCandidate: String?
    @State private var credentialsEditing = false
    @State private var revealSoulseekPassword = false
    @State private var revealSpotifySecret = false
    @State private var credentialDraft = CredentialDraft()
    @State private var advancedExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeader(
                    eyebrow: "Preferences",
                    title: "Settings",
                    detail: "Choose where music goes, the quality SeekSync prefers, and the accounts it uses. Config changes save to Sockseek; automation and app data stay local."
                )

                GroupBox("Downloads") {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("Downloads folder") {
                            HStack(spacing: 8) {
                                Text(model.settings.outputDirectory)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                                Button {
                                    chooseOutputDirectory()
                                } label: {
                                    Label("Choose…", systemImage: "folder")
                                }
                                .disabled(model.activeRun != nil)
                            }
                        }
                        Divider()
                        LabeledContent("Audio preference") {
                            HStack(spacing: 8) {
                                Picker("Format", selection: preferredFormatBinding) {
                                    ForEach(AudioPreference.allCases) { preference in
                                        Text(preference.label).tag(preference)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 150)

                                if model.settings.preferredFormat.usesLosslessQualityLabel {
                                    Text("Lossless")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 110, alignment: .trailing)
                                } else {
                                    Picker("Minimum bitrate", selection: preferredBitrateBinding) {
                                        ForEach(AudioBitratePreference.allCases) { bitrate in
                                            Text(bitrate.label).tag(String(bitrate.rawValue))
                                        }
                                        if hasCustomPreferredBitrate {
                                            Text("\(model.settings.preferredMinBitrateConfigValue) kbps (custom)")
                                                .tag(model.settings.preferredMinBitrateConfigValue)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(width: 110)
                                }
                            }
                        }
                        Text(qualityExplanation)
                            .font(.caption).foregroundStyle(.secondary)
                        Divider()
                        Toggle("Allow YouTube fallback by default", isOn: configBinding(\.allowYouTubeFallback))
                        Text("If Soulseek has no suitable candidate, allow yt-dlp to try YouTube. This may increase coverage but does not guarantee the preferred format.")
                            .font(.caption).foregroundStyle(.secondary)
                        Toggle("Look for preferred quality on every sync", isOn: configBinding(\.lookForPreferredQuality))
                        Text("Uses Sockseek's indexed-file check. A lossy file is revisited while FLAC is preferred; this is not a general audio-quality comparison.")
                            .font(.caption).foregroundStyle(.secondary)
                        Toggle("Write an M3U playlist", isOn: configBinding(\.writeM3UPlaylist))
                    }
                    .padding(4)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Soulseek")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if credentialsEditing {
                            LabeledContent("Username") {
                                TextField("Username", text: $credentialDraft.soulseekUsername)
                                    .multilineTextAlignment(.trailing)
                            }
                            LabeledContent("Password") {
                                CredentialSecretField(
                                    placeholder: "Password",
                                    text: $credentialDraft.soulseekPassword,
                                    isRevealed: $revealSoulseekPassword
                                )
                            }
                        } else {
                            LabeledContent("Username", value: configuredText(model.settings.soulseekUsername))
                            LabeledContent("Password", value: maskedText(model.settings.soulseekPassword))
                        }
                        Divider()
                        Text("Spotify")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if credentialsEditing {
                            LabeledContent("Client ID") {
                                TextField("Client ID", text: $credentialDraft.spotifyClientID)
                                    .multilineTextAlignment(.trailing)
                            }
                            LabeledContent("Client secret") {
                                CredentialSecretField(
                                    placeholder: "Client secret",
                                    text: $credentialDraft.spotifyClientSecret,
                                    isRevealed: $revealSpotifySecret
                                )
                            }
                        } else {
                            LabeledContent("Client ID", value: configuredText(model.settings.spotifyClientID, concealValue: true))
                            LabeledContent("Client secret", value: maskedText(model.settings.spotifyClientSecret))
                        }
                        HStack {
                            StatusPill(text: model.spotifyState.label, systemImage: "music.note", tone: spotifyTone)
                            Spacer()
                            Button("Refresh Playlists") { model.refreshSpotify() }
                        }
                        if case .failed(let detail) = model.spotifyState {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .accessibilityLabel("Spotify error: \(detail)")
                        }
                        Text("Access tokens stay hidden. Account changes are written to the Sockseek config only when you choose Save to Config below.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(4)
                } label: {
                    HStack {
                        Text("Accounts")
                        Spacer()
                        if credentialsEditing {
                            Button("Cancel") { cancelCredentialEditing() }
                            Button("Done") { finishCredentialEditing() }
                                .buttonStyle(.borderedProminent)
                        } else {
                            Button("Edit") { beginCredentialEditing() }
                        }
                    }
                }

                GroupBox("Automation") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Stepper("Hour: \(model.settings.dailyHour)", value: $model.settings.dailyHour, in: 0...23)
                            Stepper("Minute: \(model.settings.dailyMinute)", value: $model.settings.dailyMinute, in: 0...59, step: 5)
                        }
                        Text("Manual sync previews for real playlists start Sockseek after confirmation. Unattended daily downloads stay disarmed until separately confirmed below.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Closing the main window is fine because the menu-bar item keeps the app alive. Quitting stops this prototype scheduler.")
                            .font(.caption).foregroundStyle(.secondary)
                        Toggle("Arm unattended daily live downloads", isOn: liveArmBinding)
                            .disabled(!model.dependencyState.isReady)
                        Text(model.settings.isLiveSchedulingArmed
                             ? "Armed: due daily jobs may start without another preview while SeekSync is running."
                             : "Disarmed: daily live jobs will not start automatically.")
                            .font(.caption)
                            .foregroundStyle(model.settings.isLiveSchedulingArmed ? .orange : .secondary)
                        Button("Save Automation") { model.persistPreferences() }
                    }
                    .padding(4)
                }

                GroupBox("Sockseek") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            DependencyPill(state: model.dependencyState)
                            Spacer()
                            if model.dependencyState.isReady {
                                Button("Check Again") { model.checkSockseek() }
                            } else {
                                Button("Install Sockseek") {
                                    Task { await model.installSockseek() }
                                }
                                .disabled(model.dependencyState == .installing)
                            }
                        }
                        Text("SeekSync uses a compatible Sockseek 3 installation when it finds one. If none is available, it downloads and verifies an official managed copy for you.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(4)
                }

                GroupBox("Storage & saving") {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("Sockseek config") {
                            pathText(model.settings.configPath)
                        }
                        Text("Downloads, quality, fallback, and account changes are written to this file only when you choose Save to Config. Reload from Config discards any unsaved config edits.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(model.configMessage)
                            .font(.caption)
                            .foregroundStyle(model.isConfigDirty ? .orange : .secondary)
                        HStack {
                            Button("Reload from Config") { requestReload() }
                            Spacer()
                            Button("Save to Config") { model.saveConfig() }
                                .buttonStyle(.borderedProminent)
                                .disabled(!model.isConfigDirty || credentialsEditing)
                        }
                        Divider()
                        LabeledContent("Local app data") {
                            pathText(model.localAppDataPath)
                        }
                        Text("SeekSync restores playlists, activity, automation, and interface state from this local file when it starts. Account credentials and access tokens are excluded from it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(4)
                }

                DisclosureGroup(isExpanded: $advancedExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("Sockseek executable") {
                            HStack(spacing: 8) {
                                pathText(model.settings.binaryPath)
                                Button("Choose…") { chooseBinary() }
                                Button("Automatic") { model.useAutomaticBinaryPath() }
                            }
                        }
                        LabeledContent("Configuration file") {
                            HStack(spacing: 8) {
                                pathText(model.settings.configPath)
                                Button("Choose…") { chooseConfigFile() }
                                    .disabled(model.isConfigDirty)
                            }
                        }
                        LabeledContent("Config profile", value: model.settings.profileName.isEmpty ? "Global settings" : model.settings.profileName)
                        Text("These locations are detected automatically. Change them only when using a custom Sockseek installation or configuration.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 10)
                } label: {
                    Label("Advanced", systemImage: "gearshape.2")
                        .font(.headline)
                }
                .padding(.horizontal, 8)

                Button("Reset App Data", role: .destructive) { showResetConfirmation = true }
                    .disabled(model.activeRun != nil)
            }
            .padding(22)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .confirmationDialog(
            "Arm unattended daily downloads?",
            isPresented: $showArmConfirmation,
            titleVisibility: .visible
        ) {
            Button("Arm Daily Live Downloads", role: .destructive) { model.setLiveSchedulingArmed(true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Due playlists may start real Sockseek downloads without another preview while SeekSync is running.")
        }
        .confirmationDialog(
            "Reset all prototype data?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Prototype Data", role: .destructive) { model.resetPrototypeData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes imported prototype playlists, daily plans, and activity history. It does not touch music files or the Sockseek config.")
        }
        .confirmationDialog(
            "Discard unsaved config edits?",
            isPresented: $showReloadConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard and Reload Config", role: .destructive) { model.reloadConfig() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Reloading from the Sockseek config replaces the unsaved config values currently shown in Settings. Locally saved automation and app data are not changed.")
        }
        .confirmationDialog(
            "Use a new downloads folder?",
            isPresented: $showOutputDirectoryDecision,
            titleVisibility: .visible
        ) {
            if let candidate = outputDirectoryCandidate {
                Button("Move Existing Library") {
                    Task { await model.moveLibraryAndUpdateOutputDirectory(to: candidate) }
                }
                Button("Use New Folder Without Moving") {
                    model.updateOutputDirectory(candidate)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose whether SeekSync should move the contents of your current downloads folder. Existing files in the new folder are never overwritten.")
        }
        .onDisappear {
            revealSoulseekPassword = false
            revealSpotifySecret = false
        }
    }

    private func configBinding<T>(_ keyPath: WritableKeyPath<ClientSettings, T>) -> Binding<T> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: {
                model.settings[keyPath: keyPath] = $0
                model.markConfigDirty()
            }
        )
    }

    private var preferredFormatBinding: Binding<AudioPreference> {
        Binding(
            get: { model.settings.preferredFormat },
            set: {
                model.settings.preferredFormat = $0
                model.settings.preferredFormatRaw = $0.rawValue
                model.markConfigDirty()
            }
        )
    }

    private var preferredBitrateBinding: Binding<String> {
        Binding(
            get: { model.settings.preferredMinBitrateConfigValue },
            set: {
                model.settings.preferredMinBitrateRaw = $0
                model.settings.preferredMinBitrate = Int($0).flatMap(AudioBitratePreference.init(rawValue:))
                model.markConfigDirty()
            }
        )
    }

    private var hasCustomPreferredBitrate: Bool {
        guard let value = Int(model.settings.preferredMinBitrateConfigValue) else { return true }
        return AudioBitratePreference(rawValue: value) == nil
    }

    private var liveArmBinding: Binding<Bool> {
        Binding(
            get: { model.settings.isLiveSchedulingArmed },
            set: { newValue in
                if newValue { showArmConfirmation = true }
                else { model.setLiveSchedulingArmed(false) }
            }
        )
    }

    private var spotifyTone: StatusPill.Tone {
        switch model.spotifyState {
        case .connected, .cached: return .green
        case .failed: return .red
        case .loading: return .blue
        case .demo: return .neutral
        }
    }

    private func requestReload() {
        if model.isConfigDirty { showReloadConfirmation = true }
        else { model.reloadConfig() }
    }

    private var qualityExplanation: String {
        if model.settings.preferredFormat.usesLosslessQualityLabel {
            return "FLAC and WAV are lossless, so bitrate is not used as the quality label. This remains a soft preference, not a strict requirement."
        }
        return "SeekSync asks Sockseek to prefer \(model.settings.preferredFormat.label.lowercased()) at or above \(model.settings.preferredMinBitrateLabel). Other suitable files may still be accepted."
    }

    private func pathText(_ value: String) -> some View {
        Text(value)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
            .frame(maxWidth: 230, alignment: .trailing)
    }

    private func configuredText(_ value: String, concealValue: Bool = false) -> String {
        guard !value.isEmpty else { return "Not configured" }
        return concealValue ? "Configured" : value
    }

    private func maskedText(_ value: String) -> String {
        value.isEmpty ? "Not configured" : "••••••••"
    }

    private func beginCredentialEditing() {
        credentialDraft = CredentialDraft(settings: model.settings)
        credentialsEditing = true
    }

    private func cancelCredentialEditing() {
        credentialDraft = CredentialDraft()
        credentialsEditing = false
        revealSoulseekPassword = false
        revealSpotifySecret = false
    }

    private func finishCredentialEditing() {
        model.updateCredentials(
            soulseekUsername: credentialDraft.soulseekUsername,
            soulseekPassword: credentialDraft.soulseekPassword,
            spotifyClientID: credentialDraft.spotifyClientID,
            spotifyClientSecret: credentialDraft.spotifyClientSecret
        )
        credentialsEditing = false
        revealSoulseekPassword = false
        revealSpotifySecret = false
    }

    private func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose Downloads Folder"
        panel.message = "Choose where SeekSync should save downloaded music."
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(
            fileURLWithPath: NSString(string: model.settings.outputDirectory).expandingTildeInPath,
            isDirectory: true
        )
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let candidate = url.standardizedFileURL.path
            guard candidate != NSString(string: model.settings.outputDirectory).expandingTildeInPath else { return }
            outputDirectoryCandidate = candidate
            showOutputDirectoryDecision = true
        }
    }

    private func chooseBinary() {
        let panel = NSOpenPanel()
        panel.title = "Choose Sockseek Executable"
        panel.prompt = "Choose"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            model.setBinaryPath(url.standardizedFileURL.path)
        }
    }

    private func chooseConfigFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose Sockseek Configuration"
        panel.prompt = "Choose"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: model.settings.configPath).deletingLastPathComponent()
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            model.setConfigPath(url.standardizedFileURL.path)
        }
    }
}

private struct CredentialDraft {
    var soulseekUsername = ""
    var soulseekPassword = ""
    var spotifyClientID = ""
    var spotifyClientSecret = ""

    init() {}

    init(settings: ClientSettings) {
        soulseekUsername = settings.soulseekUsername
        soulseekPassword = settings.soulseekPassword
        spotifyClientID = settings.spotifyClientID
        spotifyClientSecret = settings.spotifyClientSecret
    }
}

private struct CredentialSecretField: View {
    let placeholder: String
    @Binding var text: String
    @Binding var isRevealed: Bool

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if isRevealed {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .multilineTextAlignment(.trailing)
            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .help(isRevealed ? "Hide \(placeholder.lowercased())" : "Show \(placeholder.lowercased())")
            .accessibilityLabel(isRevealed ? "Hide \(placeholder)" : "Show \(placeholder)")
        }
    }
}

struct PolicyExplainer: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 38))
                    .foregroundStyle(.blue)
                Text("Honest sync semantics").font(.title2.bold())
                explainer("Stable index", "Each playlist gets its own index, so reruns skip completed tracks and preserve an audit trail.")
                explainer("Preferred target", "A FLAC preference ranks FLAC first but can still accept lossy matches. Required format is a different, stricter policy.")
                explainer("YouTube fallback", "Tried only after Soulseek finds no suitable candidate. It improves coverage but may produce a lossy file.")
                explainer("Daily scheduler", "This prototype catches due work while the app is open. A production build needs a launch agent for quit-state reliability.")
            }
            .padding(22)
        }
    }

    private func explainer(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(detail).font(.callout).foregroundStyle(.secondary)
        }
    }
}
