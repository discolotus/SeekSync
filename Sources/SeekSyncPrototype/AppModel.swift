import Combine
import Foundation

struct PendingSync: Identifiable {
    let id = UUID()
    let playlist: Playlist
    let trigger: SyncTrigger
    var youtubePolicy: YouTubePolicy
}

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedSection: AppSection = .playlists
    @Published var selectedPlaylistID: String?
    @Published var searchText = ""
    @Published var importedPlaylists: [Playlist]
    @Published var liveSpotifyPlaylists: [Playlist]
    @Published var spotifyCatalogLoaded: Bool
    @Published var plans: [SyncPlan]
    @Published var runs: [SyncRun]
    @Published var settings: ClientSettings
    @Published var dependencyState: DependencyState = .checking
    @Published var spotifyState: SpotifyConnectionState = .demo
    @Published var pendingSync: PendingSync?
    @Published var toastMessage: String?
    @Published var configMessage = "Loaded without changing the file."
    @Published var isConfigDirty = false

    private var configDocument = ConfigDocument(raw: "")
    private var configRevision: ConfigRevision?
    private var loadedConfigURL: URL?
    private var loadedProfileName = ""
    private let configStore = ConfigStore()
    private let commandBuilder = SockseekCommandBuilder()
    private let processRunner = SockseekProcessRunner()
    private let sockseekInstaller = SockseekInstaller()
    private let spotifyService = SpotifyService()
    private let persistence = PrototypePersistence()
    private var schedulerCancellable: AnyCancellable?
    private var activeRunTask: Task<Void, Never>?
    private var liveRunProgress: [UUID: SockseekProgressTracker] = [:]

    init() {
        let restored = try? persistence.load()
        self.importedPlaylists = restored?.importedPlaylists ?? []
        self.liveSpotifyPlaylists = restored?.cachedSpotifyPlaylists ?? []
        self.spotifyCatalogLoaded = !(restored?.cachedSpotifyPlaylists ?? []).isEmpty
        self.plans = restored?.plans ?? Self.samplePlans
        self.runs = (restored?.runs ?? Self.sampleRuns).map { run in
            guard run.phase.isActive else { return run }
            var interrupted = run
            interrupted.phase = .cancelled
            interrupted.finishedAt = Date()
            interrupted.message = "Interrupted when SeekSync previously stopped"
            return interrupted
        }
        self.settings = restored?.settings ?? ClientSettings()
        if !self.liveSpotifyPlaylists.isEmpty {
            self.spotifyState = .cached(count: self.liveSpotifyPlaylists.count)
        }

        let autoDetectedConfig = ConfigStore.detectedConfigURL()
        let restoredConfigPath = NSString(string: settings.configPath).expandingTildeInPath
        let detectedConfig = !restoredConfigPath.isEmpty && FileManager.default.fileExists(atPath: restoredConfigPath)
            ? URL(fileURLWithPath: restoredConfigPath)
            : autoDetectedConfig
        let autoDetectedBinary = ConfigStore.detectedBinaryPath()
        let restoredBinaryPath = NSString(string: settings.binaryPath).expandingTildeInPath
        let detectedBinary = !restoredBinaryPath.isEmpty && FileManager.default.isExecutableFile(atPath: restoredBinaryPath)
            ? restoredBinaryPath
            : autoDetectedBinary
        settings.configPath = detectedConfig.path
        settings.binaryPath = detectedBinary

        do {
            let loaded = try configStore.load(
                from: detectedConfig,
                binaryPath: detectedBinary,
                preferredProfile: settings.profileName
            )
            let prototypeOnly = settings
            settings = loaded.settings
            settings.dailyHour = prototypeOnly.dailyHour
            settings.dailyMinute = prototypeOnly.dailyMinute
            settings.liveSchedulingArmed = prototypeOnly.liveSchedulingArmed
            configDocument = loaded.document
            configRevision = loaded.revision
            loadedConfigURL = detectedConfig.standardizedFileURL
            loadedProfileName = loaded.settings.profileName
        } catch {
            configMessage = error.localizedDescription
        }

        selectedPlaylistID = allPlaylists.first?.id
        if !liveSpotifyPlaylists.isEmpty || !importedPlaylists.isEmpty { removeFixturePlans() }

        Task { [weak self] in
            guard let self else { return }
            let state = await self.processRunner.version(at: self.settings.binaryPath)
            self.dependencyState = state
            if state == .missing { await self.installSockseek() }
        }
        if settings.canLoadSpotifyLibrary {
            Task { [weak self] in self?.refreshSpotify() }
        }
        schedulerCancellable = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in self?.tickScheduler(now: date) }
    }

    deinit { activeRunTask?.cancel() }

    var allPlaylists: [Playlist] {
        let base = spotifyCatalogLoaded ? liveSpotifyPlaylists : Playlist.samples
        return PlaylistLibrary.merged(imported: importedPlaylists, catalog: base)
    }

    var filteredPlaylists: [Playlist] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return allPlaylists }
        let needle = searchText.lowercased()
        return allPlaylists.filter {
            $0.name.lowercased().contains(needle)
                || $0.owner.lowercased().contains(needle)
                || $0.detail.lowercased().contains(needle)
        }
    }

    var selectedPlaylist: Playlist? {
        guard let selectedPlaylistID else { return nil }
        return allPlaylists.first { $0.id == selectedPlaylistID }
    }

    var activeRun: SyncRun? { runs.first(where: { $0.phase.isActive }) }
    var attentionCount: Int { allPlaylists.filter(needsAttention).count }
    var enabledPlanCount: Int { plans.filter { $0.enabled && playlist(for: $0) != nil }.count }

    func playlist(for plan: SyncPlan) -> Playlist? {
        allPlaylists.first { $0.id == plan.playlistID }
    }

    func plan(for playlistID: String) -> SyncPlan? {
        plans.first { $0.playlistID == playlistID }
    }

    func isInPool(_ playlistID: String) -> Bool { plan(for: playlistID) != nil }

    func needsAttention(_ playlist: Playlist) -> Bool {
        if playlist.health == .attention || playlist.needsReview > 0 { return true }
        guard let latestRun = runs.first(where: { $0.playlistID == playlist.id }) else { return false }
        return latestRun.phase == .partial || latestRun.phase == .failed
    }

    func select(_ playlist: Playlist) {
        selectedPlaylistID = playlist.id
    }

    func showSyncPreview(for playlist: Playlist, trigger: SyncTrigger = .manual) {
        pendingSync = PendingSync(
            playlist: playlist,
            trigger: trigger,
            youtubePolicy: plan(for: playlist.id)?.youtubePolicy ?? .inherit
        )
    }

    func togglePlan(for playlist: Playlist) {
        if let index = plans.firstIndex(where: { $0.playlistID == playlist.id }) {
            plans.remove(at: index)
            toastMessage = "Removed \(playlist.name) from daily sync."
        } else {
            plans.append(
                SyncPlan(
                    playlistID: playlist.id,
                    nextRunAt: nextDailyRun(after: Date())
                )
            )
            toastMessage = "\(playlist.name) will be checked daily."
        }
        persist()
    }

    func setPlanEnabled(_ planID: UUID, enabled: Bool) {
        guard let index = plans.firstIndex(where: { $0.id == planID }) else { return }
        plans[index].enabled = enabled
        if enabled, plans[index].nextRunAt < Date() {
            plans[index].nextRunAt = nextDailyRun(after: Date())
        }
        persist()
    }

    func setYouTubePolicy(_ planID: UUID, policy: YouTubePolicy) {
        guard let index = plans.firstIndex(where: { $0.id == planID }) else { return }
        plans[index].youtubePolicy = policy
        persist()
    }

    func addPlaylist(url: String, name: String?) -> Bool {
        guard let id = SpotifyURLParser.playlistID(from: url),
              let canonical = SpotifyURLParser.canonicalURL(from: url) else { return false }
        if let existing = allPlaylists.first(where: { $0.id == id }) {
            select(existing)
            return true
        }
        let playlist = Playlist(
            id: id,
            name: name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Imported Spotify playlist",
            owner: "Spotify URL",
            detail: "Added directly by URL. Track metadata will be extracted when Sockseek runs.",
            spotifyURL: canonical,
            artworkURL: nil,
            artworkHue: Double(importedPlaylists.count % 10) / 10,
            trackCount: 0,
            localCount: 0,
            upgradeCandidates: 0,
            needsReview: 0,
            lastSyncedAt: nil,
            health: .neverSynced,
            isFixture: false
        )
        importedPlaylists.insert(playlist, at: 0)
        removeFixturePlans()
        selectedPlaylistID = playlist.id
        persist()
        return true
    }

    func confirmPendingSync() {
        guard let pendingSync else { return }
        self.pendingSync = nil
        startSync(playlist: pendingSync.playlist, trigger: pendingSync.trigger, youtubePolicy: pendingSync.youtubePolicy)
    }

    func command(for pending: PendingSync) -> SLDLCommand {
        commandBuilder.command(for: pending.playlist, settings: settings, youtubePolicy: pending.youtubePolicy)
    }

    func command(for playlist: Playlist) -> SLDLCommand {
        commandBuilder.command(
            for: playlist,
            settings: settings,
            youtubePolicy: plan(for: playlist.id)?.youtubePolicy ?? .inherit
        )
    }

    func refreshSpotify() {
        guard spotifyState != .loading else { return }
        spotifyState = .loading
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.spotifyService.loadPlaylists(settings: self.settings)
                let refreshed = PlaylistLibrary.refreshed(
                    catalog: result.playlists,
                    previousCatalog: self.liveSpotifyPlaylists,
                    imported: self.importedPlaylists
                )
                self.liveSpotifyPlaylists = refreshed.catalog
                self.importedPlaylists = refreshed.remainingImports
                self.spotifyCatalogLoaded = true
                self.removeFixturePlans()
                if let token = result.refreshedAccessToken {
                    self.settings.spotifyAccessToken = token
                    self.configMessage = "Spotify refreshed its short-lived access token for this session."
                }
                if let refreshToken = result.refreshedRefreshToken {
                    self.settings.spotifyRefreshToken = refreshToken
                    self.isConfigDirty = true
                    self.configMessage = "Spotify rotated its refresh token. Save config to retain continued access."
                }
                self.spotifyState = .connected(account: result.accountName)
                if self.selectedPlaylistID == nil || !self.allPlaylists.contains(where: { $0.id == self.selectedPlaylistID }) {
                    self.selectedPlaylistID = self.allPlaylists.first?.id
                }
                self.persist()
            } catch {
                self.spotifyState = .failed(error.localizedDescription)
                self.toastMessage = error.localizedDescription
            }
        }
    }

    func reloadConfig() {
        let path = NSString(string: settings.configPath).expandingTildeInPath
        do {
            let loaded = try configStore.load(
                from: URL(fileURLWithPath: path),
                binaryPath: settings.binaryPath,
                preferredProfile: settings.profileName
            )
            let prototypeOnly = settings
            settings = loaded.settings
            settings.dailyHour = prototypeOnly.dailyHour
            settings.dailyMinute = prototypeOnly.dailyMinute
            settings.liveSchedulingArmed = prototypeOnly.liveSchedulingArmed
            configDocument = loaded.document
            configRevision = loaded.revision
            loadedConfigURL = URL(fileURLWithPath: path).standardizedFileURL
            loadedProfileName = loaded.settings.profileName
            isConfigDirty = false
            configMessage = "Reloaded \(path)."
            toastMessage = "Config reloaded."
            Task { dependencyState = await processRunner.version(at: settings.binaryPath) }
        } catch {
            configMessage = error.localizedDescription
            toastMessage = error.localizedDescription
        }
    }

    func markConfigDirty() {
        isConfigDirty = true
        configMessage = "Unsaved settings — the config file has not changed yet."
    }

    func saveConfig() {
        let path = NSString(string: settings.configPath).expandingTildeInPath
        do {
            let requestedProfile = settings.profileName.trimmingCharacters(in: .whitespacesAndNewlines)
            if requestedProfile.caseInsensitiveCompare(loadedProfileName) != .orderedSame,
               configDocument.hasSection(requestedProfile) {
                configMessage = "That profile already exists. Reload it before editing so its values are not overwritten."
                toastMessage = configMessage
                return
            }
            let destination = URL(fileURLWithPath: path).standardizedFileURL
            let expectedRevision = loadedConfigURL == destination ? configRevision : nil
            let saved = try configStore.save(
                settings: settings,
                document: configDocument,
                to: destination,
                expectedRevision: expectedRevision
            )
            configDocument = saved.document
            configRevision = saved.revision
            loadedConfigURL = destination
            loadedProfileName = saved.settings.profileName
            settings = saved.settings.mergingPrototypePreferences(from: settings)
            isConfigDirty = false
            configMessage = "Saved atomically. The first save also keeps a .seeksync-backup beside the config."
            toastMessage = "Sockseek config saved."
            persist()
            Task { dependencyState = await processRunner.version(at: settings.binaryPath) }
        } catch {
            configMessage = error.localizedDescription
            toastMessage = error.localizedDescription
        }
    }

    func tickScheduler(now: Date = Date()) {
        guard activeRun == nil else { return }
        let due = plans
            .filter { $0.enabled && $0.nextRunAt <= now }
            .compactMap { plan in playlist(for: plan).map { (plan, $0) } }
            .sorted { $0.0.nextRunAt < $1.0.nextRunAt }
        guard let (plan, playlist) = due.first else { return }
        if playlist.executionKind == .sockseek {
            guard settings.isLiveSchedulingArmed, dependencyState.isReady, !isConfigDirty else { return }
        }
        startSync(playlist: playlist, trigger: .scheduled, youtubePolicy: plan.youtubePolicy)
    }

    func resetPrototypeData() {
        guard activeRun == nil else {
            toastMessage = "Cancel the active sync and wait for it to stop before resetting prototype data."
            return
        }
        importedPlaylists = []
        liveSpotifyPlaylists = []
        spotifyCatalogLoaded = false
        plans = Self.samplePlans
        runs = Self.sampleRuns
        settings.liveSchedulingArmed = false
        selectedPlaylistID = allPlaylists.first?.id
        spotifyState = .demo
        persist()
        toastMessage = "Prototype library and activity reset."
    }

    func persistPreferences() {
        for index in plans.indices where plans[index].enabled {
            plans[index].nextRunAt = nextDailyRun(after: Date())
        }
        if persist() { toastMessage = "Prototype preferences and daily run times saved." }
    }

    func setBinaryPath(_ path: String) {
        settings.binaryPath = path
        persist()
        let expanded = NSString(string: path).expandingTildeInPath
        guard FileManager.default.isExecutableFile(atPath: expanded) else {
            dependencyState = .missing
            return
        }
        dependencyState = .checking
        Task { [weak self] in
            guard let self else { return }
            let state = await self.processRunner.version(at: expanded)
            guard NSString(string: self.settings.binaryPath).expandingTildeInPath == expanded else { return }
            self.dependencyState = state
        }
    }

    func useAutomaticBinaryPath() {
        setBinaryPath(ConfigStore.detectedBinaryPath())
        toastMessage = "Sockseek location set automatically."
    }

    func checkSockseek() {
        let expanded = NSString(string: settings.binaryPath).expandingTildeInPath
        dependencyState = .checking
        Task { [weak self] in
            guard let self else { return }
            self.dependencyState = await self.processRunner.version(at: expanded)
        }
    }

    func setConfigPath(_ path: String) {
        settings.configPath = path
        reloadConfig()
    }

    func updateOutputDirectory(_ path: String) {
        guard settings.outputDirectory != path else { return }
        settings.outputDirectory = path
        markConfigDirty()
        toastMessage = "Downloads folder updated. Save changes to apply it."
    }

    func moveLibraryAndUpdateOutputDirectory(to path: String) async {
        guard activeRun == nil else {
            toastMessage = "Wait for the active sync to finish before moving the library."
            return
        }
        let sourcePath = NSString(string: settings.outputDirectory).expandingTildeInPath
        let destinationPath = NSString(string: path).expandingTildeInPath
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try LibraryMover().moveContents(
                    from: URL(fileURLWithPath: sourcePath, isDirectory: true),
                    to: URL(fileURLWithPath: destinationPath, isDirectory: true)
                )
            }.value
            settings.outputDirectory = path
            markConfigDirty()
            let itemLabel = result.movedItemCount == 1 ? "item" : "items"
            toastMessage = result.movedItemCount == 0
                ? "Downloads folder updated; there was no existing library to move."
                : "Moved \(result.movedItemCount) \(itemLabel) to the new downloads folder."
        } catch {
            configMessage = error.localizedDescription
            toastMessage = error.localizedDescription
        }
    }

    func updateCredentials(
        soulseekUsername: String,
        soulseekPassword: String,
        spotifyClientID: String,
        spotifyClientSecret: String
    ) {
        guard settings.soulseekUsername != soulseekUsername
                || settings.soulseekPassword != soulseekPassword
                || settings.spotifyClientID != spotifyClientID
                || settings.spotifyClientSecret != spotifyClientSecret else { return }
        settings.soulseekUsername = soulseekUsername
        settings.soulseekPassword = soulseekPassword
        settings.spotifyClientID = spotifyClientID
        settings.spotifyClientSecret = spotifyClientSecret
        markConfigDirty()
    }

    func installSockseek() async {
        guard dependencyState != .installing else { return }
        dependencyState = .installing
        do {
            let installedURL = try await sockseekInstaller.install()
            let state = await processRunner.version(at: installedURL.path)
            guard state.isReady else {
                dependencyState = state
                return
            }
            settings.binaryPath = installedURL.path
            dependencyState = state
            persist()
            toastMessage = "Sockseek installed and verified."
        } catch {
            dependencyState = .failed("Sockseek install failed")
            configMessage = error.localizedDescription
            toastMessage = error.localizedDescription
        }
    }

    func setLiveSchedulingArmed(_ armed: Bool) {
        if armed, !dependencyState.isReady {
            toastMessage = "Sockseek 3 must be ready before daily live downloads can be armed."
            return
        }
        settings.liveSchedulingArmed = armed
        if persist() {
            toastMessage = armed ? "Daily live downloads armed." : "Daily live downloads disarmed."
        }
    }

    func cancelActiveRun() {
        guard let active = activeRun else { return }
        updateRun(active.id) { $0.message = "Cancelling…" }
        activeRunTask?.cancel()
    }

    private func startSync(playlist: Playlist, trigger: SyncTrigger, youtubePolicy: YouTubePolicy) {
        guard activeRun == nil else {
            toastMessage = "A sync is already running. SeekSync serializes jobs to protect the Soulseek session."
            return
        }
        if playlist.executionKind == .sockseek, !dependencyState.isReady {
            toastMessage = "Sockseek 3 must be ready before a live run can start."
            return
        }
        if playlist.executionKind == .sockseek, isConfigDirty {
            toastMessage = "Save or reload the edited settings before starting a live run."
            return
        }
        let command = commandBuilder.command(for: playlist, settings: settings, youtubePolicy: youtubePolicy)
        let run = SyncRun(
            playlistID: playlist.id,
            playlistName: playlist.name,
            trigger: trigger,
            commandPreview: command.displayString
        )
        runs.insert(run, at: 0)
        persist()

        switch playlist.executionKind {
        case .previewOnly:
            activeRunTask = Task { [weak self] in await self?.previewDemoRun(runID: run.id, playlist: playlist) }
        case .sockseek:
            activeRunTask = Task { [weak self] in await self?.executeRun(runID: run.id, playlist: playlist, command: command) }
        }
    }

    private func previewDemoRun(runID: UUID, playlist: Playlist) async {
        let stages: [(RunPhase, Double, String)] = [
            (.refreshing, 0.12, "Reading playlist metadata"),
            (.searching, 0.35, "Checking the stable index and preferred format"),
            (.downloading, 0.68, settings.allowYouTubeFallback ? "Searching Soulseek; YouTube fallback is allowed" : "Searching Soulseek only"),
            (.verifying, 0.9, "Verifying downloaded files before completion")
        ]
        do {
            for stage in stages {
                try await Task.sleep(nanoseconds: 420_000_000)
                try Task.checkCancellation()
                updateRun(runID) {
                    $0.phase = stage.0
                    $0.progress = stage.1
                    $0.message = stage.2
                }
            }
            try await Task.sleep(nanoseconds: 420_000_000)
            try Task.checkCancellation()
            let counts = RunCounts(
                added: min(max(playlist.missingCount, 0), 2),
                upgraded: min(playlist.upgradeCandidates, 3),
                alreadyBest: max(playlist.localCount - min(playlist.upgradeCandidates, 3), 0),
                unavailable: playlist.missingCount > 2 ? playlist.missingCount - 2 : 0,
                needsReview: playlist.needsReview
            )
            finishRun(runID, phase: counts.unavailable + counts.needsReview > 0 ? .partial : .completed, counts: counts, message: "Demo preview complete — no files were changed")
        } catch is CancellationError {
            finishRun(runID, phase: .cancelled, counts: RunCounts(), message: "Cancelled by user")
        } catch {
            finishRun(runID, phase: .failed, counts: RunCounts(), message: error.localizedDescription)
        }
    }

    private func executeRun(runID: UUID, playlist: Playlist, command: SLDLCommand) async {
        liveRunProgress[runID] = SockseekProgressTracker()
        updateRun(runID) {
            $0.phase = .searching
            $0.progress = 0.08
            $0.message = "Starting Sockseek"
        }
        do {
            let result = try await processRunner.run(command) { [weak self] chunk in
                await self?.consumeSockseekOutput(chunk, runID: runID)
            }
            liveRunProgress.removeValue(forKey: runID)
            let counts = Self.counts(from: result.output, fallbackTrackCount: playlist.trackCount)
            let completedItems = counts.added + counts.upgraded + counts.alreadyBest
            let phase: RunPhase
            if result.exitCode == 0, counts.unavailable == 0, counts.needsReview == 0 {
                phase = .completed
            } else if completedItems > 0 {
                phase = .partial
            } else {
                phase = .failed
            }
            let message: String
            if phase == .completed {
                message = "Sockseek completed successfully"
            } else if result.exitCode == 0 {
                message = "Sockseek completed with items that need review"
            } else {
                message = "Sockseek exited with status \(result.exitCode)"
            }
            finishRun(runID, phase: phase, counts: counts, message: message)
        } catch is CancellationError {
            liveRunProgress.removeValue(forKey: runID)
            finishRun(runID, phase: .cancelled, counts: RunCounts(), message: "Cancelled")
        } catch {
            liveRunProgress.removeValue(forKey: runID)
            finishRun(runID, phase: .failed, counts: RunCounts(), message: error.localizedDescription)
        }
    }

    private func consumeSockseekOutput(_ chunk: String, runID: UUID) {
        var state = liveRunProgress[runID] ?? SockseekProgressTracker()
        state.consume(chunk)

        liveRunProgress[runID] = state
        let snapshot = state.snapshot
        updateRun(runID) {
            $0.phase = snapshot.currentTrack?.activity == .downloading ? .downloading : .searching
            $0.progress = snapshot.playlistFraction
            $0.counts = state.counts
            $0.progressDetails = snapshot
            if snapshot.totalTracks > 0 {
                if snapshot.completedTracks == snapshot.totalTracks {
                    $0.message = "Verifying \(snapshot.totalTracks) track results"
                    $0.phase = .verifying
                } else if let track = snapshot.currentTrack {
                    let position = track.position.map { "Track \($0) of \(snapshot.totalTracks)" } ?? "Current track"
                    $0.message = "\(position) · \(track.activity.rawValue): \(track.artist) — \(track.title)"
                } else {
                    $0.message = "\(snapshot.completedTracks) of \(snapshot.totalTracks) tracks finished"
                }
            } else {
                $0.message = "Reading playlist tracks"
            }
        }
    }

    private func updateRun(_ id: UUID, update: (inout SyncRun) -> Void) {
        guard let index = runs.firstIndex(where: { $0.id == id }) else { return }
        update(&runs[index])
    }

    private func finishRun(_ id: UUID, phase: RunPhase, counts: RunCounts, message: String) {
        updateRun(id) {
            $0.phase = phase
            $0.progress = 1
            $0.finishedAt = Date()
            $0.counts = counts
            $0.message = message
        }
        guard let run = runs.first(where: { $0.id == id }) else { return }
        updatePlaylistOutcome(for: run.playlistID, phase: phase, counts: counts)
        if let index = plans.firstIndex(where: { $0.playlistID == run.playlistID }) {
            plans[index].lastRunAt = Date()
            plans[index].nextRunAt = nextDailyRun(after: Date())
        }
        persist()
    }

    private func updatePlaylistOutcome(for playlistID: String, phase: RunPhase, counts: RunCounts) {
        func apply(_ playlist: inout Playlist) {
            playlist.applySyncOutcome(phase: phase, counts: counts)
        }
        if let index = importedPlaylists.firstIndex(where: { $0.id == playlistID }) {
            apply(&importedPlaylists[index])
        }
        if let index = liveSpotifyPlaylists.firstIndex(where: { $0.id == playlistID }) {
            apply(&liveSpotifyPlaylists[index])
        }
    }

    private func nextDailyRun(after date: Date) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        components.hour = settings.dailyHour
        components.minute = settings.dailyMinute
        components.second = 0
        let today = Calendar.current.date(from: components) ?? date.addingTimeInterval(86_400)
        if today > date { return today }
        return Calendar.current.date(byAdding: .day, value: 1, to: today) ?? date.addingTimeInterval(86_400)
    }

    private func removeFixturePlans() {
        let fixtureIDs = Set(Playlist.samples.map(\.id))
        plans.removeAll { fixtureIDs.contains($0.playlistID) }
    }

    @discardableResult
    private func persist() -> Bool {
        var safeSettings = settings
        safeSettings.soulseekUsername = ""
        safeSettings.soulseekPassword = ""
        safeSettings.spotifyClientID = ""
        safeSettings.spotifyClientSecret = ""
        safeSettings.spotifyAccessToken = ""
        safeSettings.spotifyRefreshToken = ""
        let state = PrototypeState(
            importedPlaylists: importedPlaylists,
            cachedSpotifyPlaylists: liveSpotifyPlaylists,
            plans: plans,
            runs: Array(runs.prefix(30)),
            settings: safeSettings
        )
        do {
            try persistence.save(state)
            return true
        } catch {
            toastMessage = "Could not save prototype state: \(error.localizedDescription)"
            return false
        }
    }

    static func counts(from output: String, fallbackTrackCount: Int) -> RunCounts {
        var counts = RunCounts()
        let decoder = JSONDecoder()
        for line in output.split(whereSeparator: \.isNewline) {
            guard let data = line.data(using: .utf8),
                  let event = try? decoder.decode(SockseekProgressEvent.self, from: data) else { continue }
            if event.type == "track_state",
               let delta = terminalCounts(
                lifecycleState: event.data?.lifecycleState,
                terminalOutcome: event.data?.terminalOutcome,
                skipReason: event.data?.skipReason
               ) {
                counts.add(delta)
            } else if event.type == "track_list" {
                for track in event.data?.tracks ?? [] {
                    if let delta = terminalCounts(
                        lifecycleState: track.lifecycleState,
                        terminalOutcome: track.terminalOutcome,
                        skipReason: track.skipReason
                    ) {
                        counts.add(delta)
                    }
                }
            }
        }
        if counts.added + counts.alreadyBest + counts.unavailable + counts.needsReview == 0, fallbackTrackCount > 0 {
            counts.needsReview = fallbackTrackCount
        }
        return counts
    }

    nonisolated static func terminalCounts(
        lifecycleState: String?,
        terminalOutcome: String?,
        skipReason: String?
    ) -> RunCounts? {
        guard lifecycleState?.lowercased() == "terminal" else { return nil }
        var counts = RunCounts()
        switch terminalOutcome?.lowercased() {
        case "succeeded":
            if skipReason?.lowercased() == "none" || skipReason == nil {
                counts.added = 1
            } else {
                counts.alreadyBest = 1
            }
        case "skipped":
            let reason = skipReason?.lowercased() ?? ""
            if reason.contains("already") || reason.contains("exists") {
                counts.alreadyBest = 1
            } else if reason.contains("notfound") || reason.contains("not_found") || reason.contains("previously") {
                counts.unavailable = 1
            } else {
                counts.needsReview = 1
            }
        case "failed": counts.unavailable = 1
        case "cancelled": break
        default: counts.needsReview = 1
        }
        return counts
    }

    private static let samplePlans: [SyncPlan] = [
        SyncPlan(playlistID: "midnight-drive"),
        SyncPlan(playlistID: "rekordbox-warm-up", youtubePolicy: .never),
        SyncPlan(playlistID: "release-radar", enabled: false)
    ]

    private static let sampleRuns: [SyncRun] = [
        SyncRun(
            playlistID: "midnight-drive",
            playlistName: "Midnight Drive",
            trigger: .scheduled,
            phase: .partial,
            progress: 1,
            startedAt: Date().addingTimeInterval(-6_800),
            finishedAt: Date().addingTimeInterval(-6_200),
            counts: RunCounts(added: 2, upgraded: 3, alreadyBest: 77, unavailable: 1, needsReview: 1),
            message: "2 additions, 3 preferred-format upgrades, 2 items need attention",
            commandPreview: "sockseek <spotify-playlist> --progress-json --skip-check-pref-cond"
        ),
        SyncRun(
            playlistID: "rekordbox-warm-up",
            playlistName: "Rekordbox · Warm Up",
            trigger: .manual,
            phase: .completed,
            progress: 1,
            startedAt: Date().addingTimeInterval(-88_000),
            finishedAt: Date().addingTimeInterval(-87_400),
            counts: RunCounts(added: 0, upgraded: 1, alreadyBest: 111, unavailable: 0, needsReview: 0),
            message: "All tracks satisfy the current policy",
            commandPreview: "sockseek <spotify-playlist> --progress-json --yt-dlp false"
        )
    ]
}

extension RunCounts {
    mutating func add(_ other: RunCounts) {
        added += other.added
        upgraded += other.upgraded
        alreadyBest += other.alreadyBest
        unavailable += other.unavailable
        needsReview += other.needsReview
    }
}

struct PrototypePersistence {
    private let fileManager: FileManager
    private let url: URL

    init(fileManager: FileManager = .default, url: URL? = nil) {
        self.fileManager = fileManager
        if let url {
            self.url = url
        } else if let override = ProcessInfo.processInfo.environment["SEEKSYNC_STATE_PATH"], !override.isEmpty {
            self.url = URL(fileURLWithPath: NSString(string: override).expandingTildeInPath)
        } else {
            self.url = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/SeekSyncPrototype/prototype-state.json")
        }
    }

    func load() throws -> PrototypeState {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(PrototypeState.self, from: data)
    }

    func save(_ state: PrototypeState) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private extension ClientSettings {
    func mergingPrototypePreferences(from other: ClientSettings) -> ClientSettings {
        var merged = self
        merged.dailyHour = other.dailyHour
        merged.dailyMinute = other.dailyMinute
        merged.liveSchedulingArmed = other.liveSchedulingArmed
        return merged
    }
}
