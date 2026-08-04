import AppKit
import SwiftUI

struct AppSidebar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(.blue.gradient)
                    Image(systemName: "waveform.badge.magnifyingglass")
                        .foregroundStyle(.white)
                        .font(.system(size: 18, weight: .bold))
                }
                .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text("SeekSync").font(.headline)
                    Text("PROTOTYPE").font(.system(size: 9, weight: .bold)).tracking(1.1).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)

            List(selection: $model.selectedSection) {
                Section("Library") {
                    sidebarRow(.playlists, badge: nil)
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
                Text(model.settings.executionMode == .simulate ? "Simulation mode · music files stay untouched" : "Live mode · previews require confirmation")
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
        case .connected: return .green
        case .failed: return .red
        default: return .neutral
        }
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
                    Label("Demo data · \(modeLabel) — connect or refresh Spotify to replace these sample playlists.", systemImage: "testtube.2")
                        .font(.caption)
                        .foregroundStyle(model.settings.executionMode == .simulate ? Color.secondary : Color.orange)
                        .accessibilityLabel("Demo data. \(modeLabel). Sample playlists are currently visible.")
                }
                HStack {
                    TextField("Search playlists", text: $model.searchText)
                        .textFieldStyle(.roundedBorder)
                    StatusPill(text: "\(model.allPlaylists.count) playlists", systemImage: nil)
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

    private var modeLabel: String {
        model.settings.executionMode == .simulate ? "Simulation mode" : "Live mode"
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

                HStack {
                    Button {
                        model.showSyncPreview(for: playlist)
                    } label: {
                        Label("Sync Now…", systemImage: "arrow.down.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        model.togglePlan(for: playlist)
                    } label: {
                        Label(model.isInPool(playlist.id) ? "Daily sync on" : "Enable daily sync", systemImage: model.isInPool(playlist.id) ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)

                if playlist.trackCount > 0 {
                    GroupBox("Local coverage") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("\(playlist.localCount)").font(.title.bold())
                                Text("of \(playlist.trackCount) indexed locally").foregroundStyle(.secondary)
                                Spacer()
                                Text("\(Int(playlist.coverage * 100))%").font(.headline.monospacedDigit())
                            }
                            ProgressView(value: playlist.coverage)
                                .accessibilityLabel("Local coverage for \(playlist.name)")
                                .accessibilityValue("\(playlist.localCount) of \(playlist.trackCount) tracks available locally")
                            HStack {
                                if playlist.missingCount > 0 { StatusPill(text: "\(playlist.missingCount) missing", systemImage: "plus", tone: .orange) }
                                if playlist.upgradeCandidates > 0 { StatusPill(text: "\(playlist.upgradeCandidates) below target", systemImage: "arrow.up", tone: .blue) }
                                if playlist.needsReview > 0 { StatusPill(text: "\(playlist.needsReview) review", systemImage: "questionmark", tone: .red) }
                            }
                        }
                        .padding(4)
                    }
                }

                GroupBox("Effective download policy") {
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("Destination", value: model.settings.outputDirectory)
                        LabeledContent("Target", value: model.settings.preferredFormatLabel)
                        LabeledContent("YouTube fallback", value: effectiveYouTubeLabel)
                        LabeledContent("Recheck", value: model.settings.lookForPreferredQuality ? "Files below preferred conditions" : "Missing files only")
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

    private var effectiveYouTubeLabel: String {
        switch model.plan(for: playlist.id)?.youtubePolicy ?? .inherit {
        case .allow: return "Allowed for this playlist"
        case .never: return "Disabled for this playlist"
        case .inherit: return model.settings.allowYouTubeFallback ? "Allowed by default" : "Disabled by default"
        }
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
                ProgressView(value: run.progress)
                    .accessibilityLabel("Sync progress for \(run.playlistName)")
                    .accessibilityValue("\(Int(run.progress * 100)) percent")
                Text(run.message).font(.caption).foregroundStyle(.secondary)
            } else {
                RunCountsView(counts: run.counts)
                Text(run.message).font(.caption).foregroundStyle(.secondary)
            }
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeader(eyebrow: "Configuration", title: "Settings", detail: "Global values round-trip the selected Sockseek config only when you press Save config.")

                GroupBox("Dependency & config") {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("Sockseek binary") {
                            TextField("Path", text: binaryPathBinding)
                                .multilineTextAlignment(.trailing)
                        }
                        LabeledContent("Config file") {
                            TextField("Path", text: configBinding(\.configPath))
                                .multilineTextAlignment(.trailing)
                        }
                        HStack {
                            DependencyPill(state: model.dependencyState)
                            Spacer()
                            if !model.dependencyState.isReady {
                                Button("Install Sockseek") {
                                    Task { await model.installSockseek() }
                                }
                                .disabled(model.dependencyState == .installing)
                            }
                            Button("Reload Config") { requestReload() }
                        }
                        Text("If missing, SeekSync downloads the pinned official Sockseek 3.0.4 release, verifies its published SHA-256 digest, and installs it as a separate AGPL-3.0 tool. Source and license: github.com/fiso64/sockseek")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(model.configMessage)
                            .font(.caption)
                            .foregroundStyle(model.isConfigDirty ? .orange : .secondary)
                    }
                    .padding(4)
                }

                GroupBox("Downloads") {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("Output directory") {
                            TextField("Path", text: configBinding(\.outputDirectory))
                                .multilineTextAlignment(.trailing)
                        }
                        LabeledContent("Preferred formats") {
                            TextField("flac,wav", text: preferredFormatBinding)
                                .multilineTextAlignment(.trailing)
                        }
                        Text("Comma-separated values are an unordered soft preference (for example `flac,wav`); Sockseek may still accept another allowed format.")
                            .font(.caption).foregroundStyle(.secondary)
                        Toggle("Allow YouTube fallback by default", isOn: configBinding(\.allowYouTubeFallback))
                        Text("If Soulseek has no suitable candidate, allow yt-dlp to try YouTube. This may increase coverage but does not guarantee the preferred format.")
                            .font(.caption).foregroundStyle(.secondary)
                        Toggle("Look for preferred quality on every sync", isOn: configBinding(\.lookForPreferredQuality))
                        Text("Uses Sockseek's indexed-file check. A lossy file is revisited while FLAC is preferred; this is not a general audio-quality comparison.")
                            .font(.caption).foregroundStyle(.secondary)
                        Toggle("Write an M3U playlist", isOn: configBinding(\.writeM3UPlaylist))
                        LabeledContent("Config profile", value: model.settings.profileName.isEmpty ? "Global settings" : model.settings.profileName)
                    }
                    .padding(4)
                }

                GroupBox("Accounts") {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("Soulseek username") { TextField("Username", text: configBinding(\.soulseekUsername)) }
                        LabeledContent("Soulseek password") { SecureField("Password", text: configBinding(\.soulseekPassword)) }
                        Divider()
                        LabeledContent("Spotify client ID") { SecureField("Client ID", text: configBinding(\.spotifyClientID)) }
                        LabeledContent("Spotify client secret") { SecureField("Client secret", text: configBinding(\.spotifyClientSecret)) }
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
                        Text("Tokens are read from the config and never displayed or copied into prototype state. Production should store app-owned secrets in Keychain.")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("A distributed product that combines Spotify API metadata with download workflows needs a Spotify Developer Policy review. This prototype is local and personal-use only.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    .padding(4)
                }

                GroupBox("Prototype scheduler") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Stepper("Hour: \(model.settings.dailyHour)", value: $model.settings.dailyHour, in: 0...23)
                            Stepper("Minute: \(model.settings.dailyMinute)", value: $model.settings.dailyMinute, in: 0...59, step: 5)
                        }
                        Picker("Manual execution", selection: executionModeBinding) {
                            ForEach(ExecutionMode.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Text(model.settings.executionMode == .simulate
                             ? "Safe default: scheduled and manual runs are simulated."
                             : "Manual previews can start real Sockseek processes. Unattended daily downloads stay disarmed until separately confirmed below.")
                            .font(.caption)
                            .foregroundStyle(model.settings.executionMode == .live ? .orange : .secondary)
                        Text("Closing the main window is fine because the menu-bar item keeps the app alive. Quitting stops this prototype scheduler.")
                            .font(.caption).foregroundStyle(.secondary)
                        Toggle("Arm unattended daily live downloads", isOn: liveArmBinding)
                            .disabled(model.settings.executionMode != .live || !model.dependencyState.isReady)
                        Text(model.settings.isLiveSchedulingArmed
                             ? "Armed: due daily jobs may start without another preview while SeekSync is running."
                             : "Disarmed: daily live jobs will not start automatically.")
                            .font(.caption)
                            .foregroundStyle(model.settings.isLiveSchedulingArmed ? .orange : .secondary)
                        Button("Save Prototype Preferences") { model.persistPreferences() }
                    }
                    .padding(4)
                }

                HStack {
                    Button("Reset Prototype Data", role: .destructive) { showResetConfirmation = true }
                        .disabled(model.activeRun != nil)
                    Spacer()
                    Button("Reload") { requestReload() }
                    Button("Save config") { model.saveConfig() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.isConfigDirty)
                }
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
            Button("Discard and Reload", role: .destructive) { model.reloadConfig() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Reloading replaces the unsaved values currently shown in Settings.")
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

    private var preferredFormatBinding: Binding<String> {
        Binding(
            get: { model.settings.preferredFormatValue },
            set: {
                model.settings.preferredFormatRaw = $0
                model.markConfigDirty()
            }
        )
    }

    private var binaryPathBinding: Binding<String> {
        Binding(get: { model.settings.binaryPath }, set: { model.setBinaryPath($0) })
    }

    private var executionModeBinding: Binding<ExecutionMode> {
        Binding(get: { model.settings.executionMode }, set: { model.setExecutionMode($0) })
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
        case .connected: return .green
        case .failed: return .red
        case .loading: return .blue
        case .demo: return .neutral
        }
    }

    private func requestReload() {
        if model.isConfigDirty { showReloadConfirmation = true }
        else { model.reloadConfig() }
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
