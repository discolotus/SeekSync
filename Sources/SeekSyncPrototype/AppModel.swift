import Combine
import Foundation

struct PendingSync: Identifiable {
    let id = UUID()
    let playlist: Playlist
    let trigger: SyncTrigger
    var youtubePolicy: YouTubePolicy
}

struct PendingBatchSync: Identifiable {
    let id = UUID()
    let playlists: [Playlist]
    var youtubePolicy: YouTubePolicy
}

struct SyncQueueItem: Identifiable, Equatable {
    let id = UUID()
    let playlist: Playlist
    let trigger: SyncTrigger
    let youtubePolicy: YouTubePolicy
    let command: SLDLCommand
    let youtubeFallbackEnabled: Bool
    let libraryReuseConditionPolicy: LibraryReuseConditionPolicy
    let queuedAt = Date()
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
    @Published var pendingBatchSync: PendingBatchSync?
    @Published private(set) var syncQueue: [SyncQueueItem] = []
    @Published private(set) var libraryAnalyses: [String: PlaylistLibraryAnalysis]
    @Published private(set) var libraryAnalysisPlaylistIDs: Set<String> = []
    @Published private(set) var libraryAnalysisMessages: [String: String] = [:]
    @Published private(set) var playlistReadFailures: [String: String] = [:]

    func playlistReadBlocker(for playlist: Playlist) -> String? {
        guard playlist.executionKind == .sockseek else { return nil }
        return playlistReadFailures[playlist.id]
    }

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
    private var libraryAnalysisTasks: [String: Task<Bool, Never>] = [:]
    private var libraryReindexTask: Task<Void, Never>?
    @Published private(set) var isReindexingLibrary = false
    @Published private(set) var libraryReindexMessage: String?
    @Published private(set) var libraryReindexCompleted = 0
    @Published private(set) var libraryReindexTotal = 0
    @Published private(set) var libraryReindexPlaylistID: String?

    var libraryReindexPlaylists: [Playlist] {
        allPlaylists.filter { $0.executionKind == .sockseek }
    }

    var canReindexLibrary: Bool {
        settings.isLibraryReuseEnabled && dependencyState.isReady
            && libraryReuseBlocker == nil && !libraryReindexPlaylists.isEmpty
            && libraryAnalysisTasks.isEmpty && !isReindexingLibrary
    }

    func reindexLibrary() {
        guard canReindexLibrary else { return }
        let playlists = libraryReindexPlaylists
        let originalSettings = settings
        let originalConditions = libraryReuseConditionPolicy
        isReindexingLibrary = true
        libraryReindexCompleted = 0
        libraryReindexTotal = playlists.count
        libraryReindexTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isReindexingLibrary = false
                self.libraryReindexPlaylistID = nil
                self.libraryReindexTask = nil
            }
            var failed = 0
            for playlist in playlists {
                guard !Task.isCancelled else { break }
                guard self.settings == originalSettings,
                      self.libraryReuseConditionPolicy == originalConditions else {
                    self.libraryReindexMessage = "Reindex stopped because settings changed. Refreshed inventories were kept."
                    return
                }
                self.libraryReindexPlaylistID = playlist.id
                self.libraryReindexMessage = "Checking \(self.libraryReindexCompleted + 1) of \(playlists.count): \(playlist.name)"
                guard let task = self.startLibraryAnalysis(for: playlist, forceReindex: true) else {
                    failed += 1
                    self.libraryReindexCompleted += 1
                    continue
                }
                let succeeded = await task.value
                guard !Task.isCancelled else { break }
                if !succeeded { failed += 1 }
                self.libraryReindexCompleted += 1
            }
            self.libraryReindexMessage = Task.isCancelled
                ? "Reindex cancelled after \(self.libraryReindexCompleted) of \(playlists.count) playlists. Refreshed inventories were kept."
                : "Reindex finished: \(playlists.count - failed) refreshed, \(failed) failed."
        }
    }

    func cancelLibraryReindex() {
        libraryReindexTask?.cancel()
        if let id = libraryReindexPlaylistID { libraryAnalysisTasks[id]?.cancel() }
    }

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
        self.libraryAnalyses = restored?.libraryAnalyses ?? [:]
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
            settings = loaded.settings.mergingPrototypePreferences(from: settings)
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

    deinit {
        activeRunTask?.cancel()
        libraryReindexTask?.cancel()
        libraryAnalysisTasks.values.forEach { $0.cancel() }
    }

    var allPlaylists: [Playlist] {
        let base = spotifyCatalogLoaded ? liveSpotifyPlaylists : Playlist.samples
        return PlaylistLibrary.merged(imported: importedPlaylists, catalog: base)
    }

    var filteredPlaylists: [Playlist] {
        PlaylistLibrary.filtered(allPlaylists, searchText: searchText)
    }

    var selectedPlaylist: Playlist? {
        guard let selectedPlaylistID else { return nil }
        return allPlaylists.first { $0.id == selectedPlaylistID }
    }

    var localAppDataPath: String {
        persistence.storageURL.path
    }

    var activeRun: SyncRun? { runs.first(where: { $0.phase.isActive }) }
    var attentionCount: Int { allPlaylists.filter(needsAttention).count }
    var enabledPlanCount: Int { plans.filter { $0.enabled && playlist(for: $0) != nil }.count }
    var queuedSyncCount: Int { syncQueue.count }
    var queuedSyncs: [SyncQueueItem] { syncQueue }

    func playlist(for plan: SyncPlan) -> Playlist? {
        allPlaylists.first { $0.id == plan.playlistID }
    }

    func plan(for playlistID: String) -> SyncPlan? {
        plans.first { $0.playlistID == playlistID }
    }

    func latestRun(for playlistID: String) -> SyncRun? {
        runs.first { $0.playlistID == playlistID }
    }

    func libraryAnalysis(for playlistID: String) -> PlaylistLibraryAnalysis? {
        libraryAnalyses[playlistID]
    }

    /// Distinct tracks the previews have examined, badged in the sidebar so the
    /// inventory advertises that it has something to show.
    var analyzedTrackCount: Int {
        LibraryInventory(analyses: Array(libraryAnalyses.values)).entries.count
    }

    func isLibraryAnalysisCurrent(_ analysis: PlaylistLibraryAnalysis, for playlist: Playlist) -> Bool {
        analysis.isCurrent(
            for: settings,
            playlist: playlist,
            conditionFingerprint: libraryReuseConditionPolicy.fingerprint
        )
    }

    func isAnalyzingLibrary(for playlistID: String) -> Bool {
        libraryAnalysisPlaylistIDs.contains(playlistID)
    }

    var libraryReuseBlocker: String? {
        guard settings.isLibraryReuseEnabled else { return nil }
        guard !settings.libraryDirectoryPath.isEmpty else {
            return "Choose an existing music library folder in Settings before using library references."
        }
        let path = NSString(string: settings.libraryDirectoryPath).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return "The existing music library folder is unavailable. Reconnect its drive or choose another folder in Settings."
        }
        guard FileManager.default.isReadableFile(atPath: path) else {
            return "SeekSync cannot read the existing music library folder."
        }
        return nil
    }

    func isInPool(_ playlistID: String) -> Bool { plan(for: playlistID) != nil }

    func needsAttention(_ playlist: Playlist) -> Bool {
        if playlist.health == .attention || playlist.needsReview > 0 { return true }
        guard let latestRun = latestRun(for: playlist.id) else { return false }
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

    func showBatchSyncPreview(for playlists: [Playlist]) {
        let unique = playlists.reduce(into: [Playlist]()) { result, playlist in
            if !result.contains(where: { $0.id == playlist.id }) { result.append(playlist) }
        }
        guard !unique.isEmpty else { return }
        pendingBatchSync = PendingBatchSync(playlists: unique, youtubePolicy: .inherit)
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
        if let blocker = playlistReadBlocker(for: pendingSync.playlist) {
            toastMessage = blocker
            return
        }
        guard !isAnalyzingLibrary(for: pendingSync.playlist.id) else { return }
        self.pendingSync = nil
        if activeRun == nil {
            startSync(playlist: pendingSync.playlist, trigger: pendingSync.trigger, youtubePolicy: pendingSync.youtubePolicy)
        } else {
            enqueueSync(
                playlist: pendingSync.playlist,
                trigger: pendingSync.trigger,
                youtubePolicy: pendingSync.youtubePolicy
            )
        }
    }

    func isQueued(_ playlistID: String) -> Bool {
        syncQueue.contains { $0.playlist.id == playlistID }
    }

    func moveQueuedSync(_ id: UUID, by offset: Int) {
        guard let index = syncQueue.firstIndex(where: { $0.id == id }),
              offset == -1 || offset == 1,
              syncQueue.indices.contains(index + offset) else { return }
        syncQueue.swapAt(index, index + offset)
    }

    func removeQueuedSync(_ id: UUID) {
        guard let index = syncQueue.firstIndex(where: { $0.id == id }) else { return }
        let removed = syncQueue.remove(at: index)
        toastMessage = "Removed \(removed.playlist.name) from the sync queue."
    }

    func confirmPendingBatchSync() {
        guard let pending = pendingBatchSync else { return }
        pendingBatchSync = nil
        let hasLiveSync = pending.playlists.contains { $0.executionKind == .sockseek }
        if hasLiveSync, !dependencyState.isReady {
            toastMessage = "Sockseek 3 must be ready before live syncs can start."
            return
        }
        if hasLiveSync, isConfigDirty {
            toastMessage = "Save or reload the edited settings before starting live syncs."
            return
        }
        if hasLiveSync, let libraryReuseBlocker {
            toastMessage = libraryReuseBlocker
            return
        }

        let queuedPlaylistIDs = Set(syncQueue.map(\.playlist.id))
        let candidates = pending.playlists.filter {
            $0.id != activeRun?.playlistID && !queuedPlaylistIDs.contains($0.id)
        }
        guard !candidates.isEmpty else {
            toastMessage = "Those playlists are already syncing or queued."
            return
        }
        syncQueue.append(contentsOf: candidates.map {
            makeQueueItem(playlist: $0, trigger: .manual, youtubePolicy: pending.youtubePolicy)
        })
        if activeRun == nil { startNextQueuedSync() }
        toastMessage = "Queued \(candidates.count) playlist\(candidates.count == 1 ? "" : "s") for sync."
    }

    func command(for pending: PendingSync) -> SLDLCommand {
        commandBuilder.command(
            for: pending.playlist,
            settings: settings,
            youtubePolicy: pending.youtubePolicy,
            libraryReuseConditionPolicy: libraryReuseConditionPolicy
        )
    }

    func command(for playlist: Playlist) -> SLDLCommand {
        commandBuilder.command(
            for: playlist,
            settings: settings,
            youtubePolicy: plan(for: playlist.id)?.youtubePolicy ?? .inherit,
            libraryReuseConditionPolicy: libraryReuseConditionPolicy
        )
    }

    func command(for playlist: Playlist, youtubePolicy: YouTubePolicy) -> SLDLCommand {
        commandBuilder.command(
            for: playlist,
            settings: settings,
            youtubePolicy: youtubePolicy,
            libraryReuseConditionPolicy: libraryReuseConditionPolicy
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
            settings = loaded.settings.mergingPrototypePreferences(from: settings)
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
        guard activeRun == nil, queuedSyncs.isEmpty else {
            toastMessage = "Cancel the active sync and clear the queue before resetting prototype data."
            return
        }
        importedPlaylists = []
        liveSpotifyPlaylists = []
        spotifyCatalogLoaded = false
        plans = Self.samplePlans
        runs = Self.sampleRuns
        libraryAnalyses = [:]
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
        if persist() { toastMessage = "Automation preferences and daily run times saved locally." }
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

    func setLibraryReuseEnabled(_ enabled: Bool) {
        settings.libraryReuseEnabled = enabled
        if persist() {
            toastMessage = enabled
                ? "Existing-library references enabled."
                : "Existing-library references disabled."
        }
    }

    func setRekordboxXMLEnabled(_ enabled: Bool) {
        settings.rekordboxXMLEnabled = enabled
        if persist() {
            toastMessage = enabled
                ? "Rekordbox library will be written after each sync."
                : "Rekordbox library export disabled."
        }
    }

    func setLibraryDirectory(_ path: String) {
        settings.libraryDirectory = path
        settings.libraryReuseEnabled = true
        if persist() {
            toastMessage = "Existing music library updated. Preview a playlist to check its matches."
        }
    }

    func analyzeLibraryReuse(for requestedPlaylist: Playlist) {
        guard !isReindexingLibrary else { return }
        startLibraryAnalysis(for: requestedPlaylist)
    }

    @discardableResult
    private func startLibraryAnalysis(for requestedPlaylist: Playlist, forceReindex: Bool = false) -> Task<Bool, Never>? {
        let playlist = allPlaylists.first(where: { $0.id == requestedPlaylist.id }) ?? requestedPlaylist
        guard settings.isLibraryReuseEnabled else {
            toastMessage = "Enable existing-library references in Settings before running a preview."
            return nil
        }
        guard playlist.executionKind == .sockseek else {
            toastMessage = "Library reuse previews are available for real Spotify playlists."
            return nil
        }
        guard dependencyState.isReady else {
            toastMessage = "Sockseek 3 must be ready before analyzing a playlist."
            return nil
        }
        if let libraryReuseBlocker {
            toastMessage = libraryReuseBlocker
            return nil
        }
        guard libraryAnalysisTasks[playlist.id] == nil else { return nil }

        let settingsSnapshot = settings
        let conditionPolicySnapshot = libraryReuseConditionPolicy
        libraryAnalysisPlaylistIDs.insert(playlist.id)
        libraryAnalysisMessages[playlist.id] = "Preparing a read-only library preview…"
        let analyzer = LibraryReuseAnalyzer()
        let task = Task { [weak self] in
            guard let self else { return false }
            do {
                let analysis = try await analyzer.analyze(
                    playlist: playlist,
                    settings: settingsSnapshot,
                    conditionPolicy: conditionPolicySnapshot,
                    forceReindex: forceReindex,
                    onPlaylistRead: { [weak self] in
                        await MainActor.run {
                            _ = self?.playlistReadFailures.removeValue(forKey: playlist.id)
                        }
                    }
                ) { [weak self] stage in
                    await MainActor.run {
                        self?.libraryAnalysisMessages[playlist.id] = stage
                    }
                }
                try Task.checkCancellation()
                let currentPlaylist = self.allPlaylists.first(where: { $0.id == playlist.id }) ?? playlist
                guard self.isLibraryAnalysisCurrent(analysis, for: currentPlaylist) else {
                    self.libraryAnalysisMessages[playlist.id] = "The playlist or reuse settings changed while the preview was running. Analyze again for a current inventory."
                    self.libraryAnalysisPlaylistIDs.remove(playlist.id)
                    self.libraryAnalysisTasks.removeValue(forKey: playlist.id)
                    return false
                }
                self.playlistReadFailures.removeValue(forKey: playlist.id)
                self.libraryAnalyses[playlist.id] = analysis
                self.applyLibraryAnalysisSummary(analysis)
                self.libraryAnalysisMessages[playlist.id] = "Analysis complete."
                self.libraryAnalysisPlaylistIDs.remove(playlist.id)
                self.libraryAnalysisTasks.removeValue(forKey: playlist.id)
                self.persist()
                return true
            } catch is CancellationError {
                self.libraryAnalysisMessages[playlist.id] = "Library preview cancelled."
                self.libraryAnalysisPlaylistIDs.remove(playlist.id)
                self.libraryAnalysisTasks.removeValue(forKey: playlist.id)
            } catch {
                if let failure = error as? LibraryReuseAnalysisError {
                    switch failure {
                    case .playlistExtractionFailed, .noPlaylistTracks:
                        self.playlistReadFailures[playlist.id] = failure.localizedDescription
                    case .missingLibrary, .previewPassIncomplete:
                        break
                    }
                }
                self.libraryAnalysisMessages[playlist.id] = error.localizedDescription
                self.libraryAnalysisPlaylistIDs.remove(playlist.id)
                self.libraryAnalysisTasks.removeValue(forKey: playlist.id)
            }
            return false
        }
        libraryAnalysisTasks[playlist.id] = task
        return task
    }

    func cancelActiveRun() {
        guard let active = activeRun else { return }
        updateRun(active.id) { $0.message = "Cancelling…" }
        activeRunTask?.cancel()
        if !syncQueue.isEmpty {
            toastMessage = "Cancelling the current sync. The next queued playlist will start automatically."
        }
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
        if playlist.executionKind == .sockseek, let libraryReuseBlocker {
            toastMessage = libraryReuseBlocker
            return
        }
        let conditionPolicy = libraryReuseConditionPolicy
        let command = commandBuilder.command(
            for: playlist,
            settings: settings,
            youtubePolicy: youtubePolicy,
            libraryReuseConditionPolicy: conditionPolicy
        )
        let youtubeFallbackEnabled = youtubePolicy.allowsFallback(using: settings)
        launchSync(
            playlist: playlist,
            trigger: trigger,
            command: command,
            youtubeFallbackEnabled: youtubeFallbackEnabled,
            libraryReuseConditionPolicy: conditionPolicy
        )
    }

    private func launchSync(
        playlist: Playlist,
        trigger: SyncTrigger,
        command: SLDLCommand,
        youtubeFallbackEnabled: Bool,
        libraryReuseConditionPolicy: LibraryReuseConditionPolicy
    ) {
        let run = SyncRun(
            playlistID: playlist.id,
            playlistName: playlist.name,
            trigger: trigger,
            youtubeFallbackEnabled: youtubeFallbackEnabled,
            commandPreview: command.displayString
        )
        runs.insert(run, at: 0)
        persist()

        switch playlist.executionKind {
        case .previewOnly:
            activeRunTask = Task { [weak self] in await self?.previewDemoRun(runID: run.id, playlist: playlist) }
        case .sockseek:
            activeRunTask = Task { [weak self] in
                await self?.executeRun(
                    runID: run.id,
                    playlist: playlist,
                    command: command,
                    youtubeFallbackEnabled: youtubeFallbackEnabled,
                    libraryReuseConditionPolicy: libraryReuseConditionPolicy
                )
            }
        }
    }

    private func enqueueSync(playlist: Playlist, trigger: SyncTrigger, youtubePolicy: YouTubePolicy) {
        if activeRun?.playlistID == playlist.id || isQueued(playlist.id) {
            toastMessage = "\(playlist.name) is already syncing or queued."
            return
        }
        syncQueue.append(makeQueueItem(playlist: playlist, trigger: trigger, youtubePolicy: youtubePolicy))
        let position = syncQueue.count
        toastMessage = position == 1
            ? "\(playlist.name) is next in the sync queue."
            : "\(playlist.name) is number \(position) in the sync queue."
    }

    private func makeQueueItem(
        playlist: Playlist,
        trigger: SyncTrigger,
        youtubePolicy: YouTubePolicy
    ) -> SyncQueueItem {
        let conditionPolicy = libraryReuseConditionPolicy
        return SyncQueueItem(
            playlist: playlist,
            trigger: trigger,
            youtubePolicy: youtubePolicy,
            command: commandBuilder.command(
                for: playlist,
                settings: settings,
                youtubePolicy: youtubePolicy,
                libraryReuseConditionPolicy: conditionPolicy
            ),
            youtubeFallbackEnabled: youtubePolicy.allowsFallback(using: settings),
            libraryReuseConditionPolicy: conditionPolicy
        )
    }

    private func startNextQueuedSync() {
        guard activeRun == nil, !syncQueue.isEmpty else { return }
        let next = syncQueue.removeFirst()
        launchSync(
            playlist: next.playlist,
            trigger: next.trigger,
            command: next.command,
            youtubeFallbackEnabled: next.youtubeFallbackEnabled,
            libraryReuseConditionPolicy: next.libraryReuseConditionPolicy
        )
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

    private func executeRun(
        runID: UUID,
        playlist: Playlist,
        command: SLDLCommand,
        youtubeFallbackEnabled: Bool,
        libraryReuseConditionPolicy: LibraryReuseConditionPolicy
    ) async {
        liveRunProgress[runID] = SockseekProgressTracker(youtubeFallbackEnabled: youtubeFallbackEnabled)
        updateRun(runID) {
            $0.phase = .searching
            $0.progress = 0.08
            $0.message = "Starting Sockseek"
        }
        do {
            let result = try await processRunner.run(command) { [weak self] chunk in
                await self?.consumeSockseekOutput(chunk, runID: runID)
            }
            var finalTracker = SockseekProgressTracker(youtubeFallbackEnabled: youtubeFallbackEnabled)
            finalTracker.consume(result.output)
            liveRunProgress.removeValue(forKey: runID)
            await reconcileLibraryAnalysis(
                playlist: playlist,
                progressSeeds: finalTracker.playlistTracks,
                command: command,
                conditionPolicy: libraryReuseConditionPolicy
            )
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
            finishRun(
                runID,
                phase: phase,
                counts: counts,
                trackFailures: finalTracker.failures,
                message: message
            )
        } catch is CancellationError {
            let progress = liveRunProgress.removeValue(forKey: runID)
            finishRun(
                runID,
                phase: .cancelled,
                counts: progress?.counts ?? RunCounts(),
                trackFailures: progress?.failures,
                message: "Cancelled"
            )
        } catch {
            let progress = liveRunProgress.removeValue(forKey: runID)
            finishRun(
                runID,
                phase: .failed,
                counts: progress?.counts ?? RunCounts(),
                trackFailures: progress?.failures,
                message: error.localizedDescription
            )
        }
    }

    private func reconcileLibraryAnalysis(
        playlist: Playlist,
        progressSeeds: [PlaylistTrackSeed],
        command: SLDLCommand,
        conditionPolicy: LibraryReuseConditionPolicy
    ) async {
        guard command.arguments.contains("--skip-music-dir") || libraryAnalyses[playlist.id] != nil else { return }
        let previousAnalysis = libraryAnalyses[playlist.id]
        do {
            guard let analysis = try await LibraryReuseAnalyzer().completedAnalysis(
                playlist: playlist,
                seeds: progressSeeds,
                previousAnalysis: previousAnalysis,
                command: command,
                conditionPolicy: conditionPolicy,
                settings: settings
            ) else {
                libraryAnalysisMessages[playlist.id] = "The sync finished, but no readable stable index was available to refresh its track inventory."
                return
            }
            libraryAnalyses[playlist.id] = analysis
            applyLibraryAnalysisSummary(analysis)
            libraryAnalysisMessages[playlist.id] = "Track inventory updated from the completed Sockseek index."
        } catch {
            libraryAnalysisMessages[playlist.id] = "The sync finished, but its track inventory could not be refreshed: \(error.localizedDescription)"
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
            $0.trackFailures = state.failures
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

    private func finishRun(
        _ id: UUID,
        phase: RunPhase,
        counts: RunCounts,
        trackFailures: [TrackSyncFailure]? = nil,
        message: String
    ) {
        updateRun(id) {
            $0.phase = phase
            $0.progress = 1
            $0.finishedAt = Date()
            $0.counts = counts
            if let trackFailures { $0.trackFailures = trackFailures }
            $0.message = message
        }
        guard let run = runs.first(where: { $0.id == id }) else { return }
        updatePlaylistOutcome(for: run.playlistID, phase: phase, counts: counts)
        if let index = plans.firstIndex(where: { $0.playlistID == run.playlistID }) {
            plans[index].lastRunAt = Date()
            plans[index].nextRunAt = nextDailyRun(after: Date())
        }
        persist()
        regenerateRekordboxXML()
        startNextQueuedSync()
    }

    /// Rebuilds the combined rekordbox library from the indices on disk. This
    /// is a side effect of syncing and must never fail a run, so every error
    /// stops here.
    private func regenerateRekordboxXML() {
        guard settings.isRekordboxXMLEnabled else { return }
        let sources = RekordboxXMLExporter.sources(
            for: allPlaylists,
            outputDirectory: settings.outputDirectory
        )
        guard !sources.isEmpty else { return }
        do {
            try RekordboxXMLExporter().export(
                sources: sources,
                to: RekordboxXMLExporter.exportURL(outputDirectory: settings.outputDirectory)
            )
        } catch {
            toastMessage = "Could not write the rekordbox library: \(error.localizedDescription)"
        }
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

    private func applyLibraryAnalysisSummary(_ analysis: PlaylistLibraryAnalysis) {
        func apply(_ playlist: inout Playlist) {
            playlist.applyLibraryAnalysis(analysis)
        }
        if let index = importedPlaylists.firstIndex(where: { $0.id == analysis.playlistID }) {
            apply(&importedPlaylists[index])
        }
        if let index = liveSpotifyPlaylists.firstIndex(where: { $0.id == analysis.playlistID }) {
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

    private var libraryReuseConditionPolicy: LibraryReuseConditionPolicy {
        let mappings: [(String, String)] = [
            ("format", "--format"),
            ("length-tol", "--length-tol"),
            ("min-bitrate", "--min-bitrate"),
            ("max-bitrate", "--max-bitrate"),
            ("min-samplerate", "--min-samplerate"),
            ("max-samplerate", "--max-samplerate"),
            ("min-bitdepth", "--min-bitdepth"),
            ("max-bitdepth", "--max-bitdepth"),
            ("strict-title", "--strict-title"),
            ("strict-artist", "--strict-artist"),
            ("strict-album", "--strict-album"),
            ("accept-no-length", "--accept-no-length"),
            ("cond", "--cond"),
            ("pref-length-tol", "--pref-length-tol"),
            ("pref-max-bitrate", "--pref-max-bitrate"),
            ("pref-min-samplerate", "--pref-min-samplerate"),
            ("pref-max-samplerate", "--pref-max-samplerate"),
            ("pref-min-bitdepth", "--pref-min-bitdepth"),
            ("pref-max-bitdepth", "--pref-max-bitdepth"),
            ("pref-strict-title", "--pref-strict-title"),
            ("pref-strict-artist", "--pref-strict-artist"),
            ("pref-strict-album", "--pref-strict-album"),
            ("pref-accept-no-length", "--pref-accept-no-length"),
            ("pref", "--pref"),
            ("strict-conditions", "--strict-conditions"),
            ("skip-check-cond", "--skip-check-cond")
        ]
        let profile = settings.profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        var arguments: [String] = []
        for (key, option) in mappings {
            let profileValue = profile.isEmpty ? nil : configDocument.value(for: key, section: profile)
            guard let value = profileValue ?? configDocument.value(for: key) else { continue }
            arguments += [option, value]
        }
        return LibraryReuseConditionPolicy(arguments: arguments)
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
            settings: safeSettings,
            libraryAnalyses: libraryAnalyses
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
        var tracker = SockseekProgressTracker()
        tracker.consume(output)
        var counts = tracker.counts
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
            trackFailures: [
                TrackSyncFailure(
                    position: 83,
                    artist: "Static Bloom",
                    title: "Afterimage",
                    album: "Signals After Dark",
                    terminalOutcome: "Failed",
                    failureReason: "NoMatchingResults",
                    skipReason: nil,
                    rawResultCount: 12,
                    lockedCount: 0,
                    source: .soulseekAndYouTube
                ),
                TrackSyncFailure(
                    position: 84,
                    artist: "Night Service",
                    title: "Last Platform",
                    album: "Terminal Lights",
                    terminalOutcome: "Skipped",
                    failureReason: nil,
                    skipReason: "PreviouslyNotFound",
                    rawResultCount: nil,
                    lockedCount: nil,
                    source: .cachedPreviousResult
                )
            ],
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
    private let legacyURL: URL?

    var storageURL: URL { url }

    init(fileManager: FileManager = .default, url: URL? = nil, legacyURL: URL? = nil) {
        self.fileManager = fileManager
        if let url {
            self.url = url
            self.legacyURL = legacyURL
        } else if let override = ProcessInfo.processInfo.environment["SEEKSYNC_STATE_PATH"], !override.isEmpty {
            self.url = URL(fileURLWithPath: NSString(string: override).expandingTildeInPath)
            self.legacyURL = nil
        } else {
            self.url = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/SeekSync/state.json")
            self.legacyURL = legacyURL ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/SeekSyncPrototype/prototype-state.json")
        }
    }

    func load() throws -> PrototypeState {
        if fileManager.fileExists(atPath: url.path) {
            return try decode(from: url)
        }
        guard let legacyURL, fileManager.fileExists(atPath: legacyURL.path) else {
            return try decode(from: url)
        }

        let state = try decode(from: legacyURL)
        try? save(state)
        return state
    }

    func save(_ state: PrototypeState) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func decode(from url: URL) throws -> PrototypeState {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(PrototypeState.self, from: data)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

extension ClientSettings {
    /// Carries the settings SeekSync owns over a set of settings just read
    /// from Sockseek's config. Every app-local preference belongs here, and
    /// only here, so reloading the config cannot silently drop one.
    func mergingPrototypePreferences(from other: ClientSettings) -> ClientSettings {
        var merged = self
        merged.dailyHour = other.dailyHour
        merged.dailyMinute = other.dailyMinute
        merged.liveSchedulingArmed = other.liveSchedulingArmed
        merged.libraryReuseEnabled = other.libraryReuseEnabled
        merged.libraryDirectory = other.libraryDirectory
        merged.rekordboxXMLEnabled = other.rekordboxXMLEnabled
        return merged
    }
}
