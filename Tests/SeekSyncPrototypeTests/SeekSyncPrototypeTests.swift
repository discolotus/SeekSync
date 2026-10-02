import AppKit
import SwiftUI
import XCTest
@testable import SeekSyncPrototype

private actor OutputChunks {
    private var chunks: [String] = []

    func append(_ chunk: String) { chunks.append(chunk) }
    func joined() -> String { chunks.joined() }
}

final class SeekSyncLayoutModeTests: XCTestCase {
    func testCompactLayoutsCoverSupportedSmallWindowWidths() {
        XCTAssertEqual(SeekSyncLayoutMode(width: 860), .compact)
        XCTAssertEqual(SeekSyncLayoutMode(width: 994), .compact)
        XCTAssertFalse(SeekSyncLayoutMode(width: 994).defaultsToOpenInspector)
        XCTAssertTrue(SeekSyncLayoutMode(width: 1_049).usesOverlayInspector)
    }

    func testStandardAndWideLayoutsUseExpandedPresentation() {
        XCTAssertEqual(SeekSyncLayoutMode(width: 1_050), .standard)
        XCTAssertEqual(SeekSyncLayoutMode(width: 1_280), .wide)
        XCTAssertTrue(SeekSyncLayoutMode(width: 1_280).defaultsToOpenInspector)
        XCTAssertFalse(SeekSyncLayoutMode(width: 1_050).usesOverlayInspector)
    }
}

final class SeekSyncVersionTests: XCTestCase {
    func testDisplaysPackagedAppVersion() {
        XCTAssertEqual(
            SeekSyncVersion.label(infoDictionary: ["CFBundleShortVersionString": "0.3.5"]),
            "SeekSync 0.3.5"
        )
        XCTAssertEqual(
            SeekSyncVersion.shortLabel(infoDictionary: ["CFBundleShortVersionString": "0.3.5"]),
            "v0.3.5"
        )
    }

    func testLabelsUnpackagedSwiftBuildAsDevelopment() {
        XCTAssertEqual(SeekSyncVersion.label(infoDictionary: nil), "SeekSync development")
        XCTAssertEqual(SeekSyncVersion.shortLabel(infoDictionary: nil), "dev")
    }
}

@MainActor
final class SeekSyncVisualRenderTests: XCTestCase {
    func testSupportedWindowLayoutsAndSheetsRenderInAppScopedWindows() throws {
        let model = AppModel()
        model.selectedPlaylistID = Playlist.samples[0].id
        model.showSyncPreview(for: Playlist.samples[0])
        let pendingSync = try XCTUnwrap(model.pendingSync)

        let compact = LibraryInspectorVariant(
            showAddPlaylist: .constant(false),
            inspectorPresented: .constant(true)
        )
        .environmentObject(model)
        .frame(width: 994, height: 624)
        .background(Color(nsColor: .windowBackgroundColor))

        let standard = LibraryInspectorVariant(
            showAddPlaylist: .constant(false),
            inspectorPresented: .constant(true)
        )
        .environmentObject(model)
        .frame(width: 1_180, height: 720)
        .background(Color(nsColor: .windowBackgroundColor))

        model.selectedSection = .batchSync
        let batchSync = BatchSyncScreen()
            .environmentObject(model)
            .frame(width: 980, height: 720)
            .background(Color(nsColor: .windowBackgroundColor))

        model.showBatchSyncPreview(for: Array(Playlist.samples.prefix(3)))
        let pendingBatchSync = try XCTUnwrap(model.pendingBatchSync)
        let batchSyncPreview = BatchSyncPreviewSheet(pending: pendingBatchSync)
            .environmentObject(model)

        let settings = SettingsScreen()
            .environmentObject(model)
            .frame(width: 660, height: 560)
            .background(Color(nsColor: .windowBackgroundColor))

        let syncPreview = SyncPreviewSheet(pending: pendingSync)
            .environmentObject(model)

        let liveModel = AppModel()
        var livePlaylist = Playlist.samples[0]
        livePlaylist.isFixture = false
        liveModel.dependencyState = .ready(version: "3.0.5")
        liveModel.settings.libraryReuseEnabled = true
        liveModel.settings.libraryDirectory = FileManager.default.temporaryDirectory.path
        liveModel.showSyncPreview(for: livePlaylist)
        let livePendingSync = try XCTUnwrap(liveModel.pendingSync)
        let liveSyncPreview = SyncPreviewSheet(pending: livePendingSync)
            .environmentObject(liveModel)

        let queueModel = AppModel()
        queueModel.showSyncPreview(for: Playlist.samples[0])
        queueModel.confirmPendingSync()
        queueModel.showSyncPreview(for: Playlist.samples[1])
        queueModel.confirmPendingSync()
        queueModel.showSyncPreview(for: Playlist.samples[2])
        queueModel.confirmPendingSync()
        let queue = SyncQueueView()
            .environmentObject(queueModel)
            .padding(16)
            .frame(width: 620, height: 250)
            .background(Color(nsColor: .windowBackgroundColor))

        let queuePNG = try renderPNG(AnyView(queue), size: NSSize(width: 620, height: 250))
        let compactPNG = try renderPNG(AnyView(compact), size: NSSize(width: 994, height: 624))
        let standardPNG = try renderPNG(AnyView(standard), size: NSSize(width: 1_180, height: 720))
        let batchSyncPNG = try renderPNG(AnyView(batchSync), size: NSSize(width: 980, height: 720))
        let batchSyncPreviewPNG = try renderPNG(AnyView(batchSyncPreview), size: NSSize(width: 680, height: 620))
        let settingsPNG = try renderPNG(AnyView(settings), size: NSSize(width: 660, height: 560))
        let syncPreviewPNG = try renderPNG(AnyView(syncPreview), size: NSSize(width: 680, height: 660))
        let liveSyncPreviewPNG = try renderPNG(AnyView(liveSyncPreview), size: NSSize(width: 680, height: 660))
        let sourceIconURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/AppIconSource.png")
        let sourceIcon = try XCTUnwrap(NSImage(contentsOf: sourceIconURL))
        let brandHeader = SeekSyncBrandHeader(iconSize: 48, image: sourceIcon)
            .padding(16)
            .frame(width: 320, height: 80)
            .background(Color(nsColor: .windowBackgroundColor))
            .preferredColorScheme(.dark)
        let brandHeaderPNG = try renderPNG(AnyView(brandHeader), size: NSSize(width: 320, height: 80))
        let identityComparison = HStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("BUNDLED APP ICON")
                    .font(.caption2.bold())
                    .tracking(1)
                    .foregroundStyle(.secondary)
                SeekSyncAppIcon(size: 84, image: sourceIcon)
            }
            .frame(width: 180)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("FRONTEND IDENTITY")
                    .font(.caption2.bold())
                    .tracking(1)
                    .foregroundStyle(.secondary)
                SeekSyncBrandHeader(iconSize: 48, image: sourceIcon)
            }
            .frame(width: 360, alignment: .leading)
        }
        .padding(20)
        .frame(width: 640, height: 160)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
        let identityComparisonPNG = try renderPNG(
            AnyView(identityComparison),
            size: NSSize(width: 640, height: 160)
        )
        let failureRun = SyncRun(
            playlistID: "visual-failure-run",
            playlistName: "Visual failure run",
            trigger: .manual,
            phase: .partial,
            progress: 1,
            counts: RunCounts(unavailable: 2),
            trackFailures: [
                TrackSyncFailure(
                    position: 4,
                    artist: "Artist One",
                    title: "No Results",
                    album: "Album One",
                    terminalOutcome: "Failed",
                    failureReason: "NoSearchResults",
                    skipReason: nil,
                    rawResultCount: 0,
                    lockedCount: 0,
                    source: .soulseekAndYouTube
                ),
                TrackSyncFailure(
                    position: 9,
                    artist: "Artist Two",
                    title: "Locked Result",
                    album: "Album Two",
                    terminalOutcome: "Failed",
                    failureReason: "NoSearchResults",
                    skipReason: nil,
                    rawResultCount: 3,
                    lockedCount: 3,
                    source: .soulseek
                )
            ],
            youtubeFallbackEnabled: true,
            commandPreview: "sockseek <playlist>"
        )
        let failureDetails = TrackFailureDetailsView(run: failureRun)
            .padding(20)
            .frame(width: 680, height: 330, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
        let failureDetailsPNG = try renderPNG(
            AnyView(failureDetails),
            size: NSSize(width: 680, height: 330)
        )

        XCTAssertGreaterThan(compactPNG.count, 10_000)
        XCTAssertGreaterThan(standardPNG.count, 10_000)
        XCTAssertGreaterThan(batchSyncPNG.count, 10_000)
        XCTAssertGreaterThan(batchSyncPreviewPNG.count, 10_000)
        XCTAssertGreaterThan(settingsPNG.count, 10_000)
        XCTAssertGreaterThan(syncPreviewPNG.count, 10_000)
        XCTAssertGreaterThan(liveSyncPreviewPNG.count, 10_000)
        XCTAssertGreaterThan(queuePNG.count, 8_000)
        XCTAssertGreaterThan(brandHeaderPNG.count, 8_000)
        XCTAssertGreaterThan(identityComparisonPNG.count, 12_000)
        XCTAssertGreaterThan(failureDetailsPNG.count, 10_000)

        if let outputPath = ProcessInfo.processInfo.environment["SEEKSYNC_VISUAL_QA_DIR"], !outputPath.isEmpty {
            let outputDirectory = URL(fileURLWithPath: outputPath, isDirectory: true)
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            try compactPNG.write(to: outputDirectory.appendingPathComponent("implementation-compact-994x624@2x.png"), options: .atomic)
            try standardPNG.write(to: outputDirectory.appendingPathComponent("implementation-standard-1180x720@2x.png"), options: .atomic)
            try batchSyncPNG.write(to: outputDirectory.appendingPathComponent("implementation-batch-sync-980x720@2x.png"), options: .atomic)
            try batchSyncPreviewPNG.write(to: outputDirectory.appendingPathComponent("implementation-batch-sync-preview-680x620@2x.png"), options: .atomic)
            try settingsPNG.write(to: outputDirectory.appendingPathComponent("implementation-settings-660x560@2x.png"), options: .atomic)
            try syncPreviewPNG.write(to: outputDirectory.appendingPathComponent("implementation-sync-preview-680x660@2x.png"), options: .atomic)
            try liveSyncPreviewPNG.write(to: outputDirectory.appendingPathComponent("implementation-live-sync-preview-680x660@2x.png"), options: .atomic)
            try queuePNG.write(to: outputDirectory.appendingPathComponent("implementation-sync-queue-620x250@2x.png"), options: .atomic)
            try brandHeaderPNG.write(to: outputDirectory.appendingPathComponent("implementation-brand-header-320x80@2x.png"), options: .atomic)
            try identityComparisonPNG.write(to: outputDirectory.appendingPathComponent("comparison-app-icon-vs-brand-header-640x160@2x.png"), options: .atomic)
            try failureDetailsPNG.write(to: outputDirectory.appendingPathComponent("implementation-track-failure-details-680x330@2x.png"), options: .atomic)
        }
        queueModel.cancelActiveRun()
    }

    func testLibraryReuseSummaryAndTrackQualityListRender() throws {
        let analysis = PlaylistLibraryAnalysis(
            playlistID: "visual-library-reuse",
            playlistName: "Road Trip Archive",
            analyzedAt: Date(timeIntervalSince1970: 1_750_000_000),
            sourceLibraryPath: "/Users/listener/Music/Archive",
            preferredFormat: "mp3",
            minimumBitrateKbps: 256,
            tracks: [
                PlaylistTrackRecord(
                    seed: PlaylistTrackSeed(
                        position: 1,
                        artist: "The Existing Copies",
                        title: "Needs a Better Encode",
                        album: "Old Library",
                        lengthSeconds: 247
                    ),
                    disposition: .libraryBelowThreshold,
                    localPath: "/Users/listener/Music/Archive/The Existing Copies/Needs a Better Encode.mp3",
                    quality: AudioFileQuality(
                        format: "mp3",
                        bitrateKbps: 128,
                        sampleRateHz: 44_100,
                        bitDepth: nil,
                        durationSeconds: 247
                    )
                ),
                PlaylistTrackRecord(
                    seed: PlaylistTrackSeed(
                        position: 2,
                        artist: "Local Favorite",
                        title: "Already Excellent",
                        album: "Reference Masters",
                        lengthSeconds: 312
                    ),
                    disposition: .libraryReference,
                    localPath: "/Users/listener/Music/Archive/Local Favorite/Already Excellent.mp3",
                    quality: AudioFileQuality(
                        format: "mp3",
                        bitrateKbps: 320,
                        sampleRateHz: 48_000,
                        bitDepth: nil,
                        durationSeconds: 312
                    )
                ),
                PlaylistTrackRecord(
                    seed: PlaylistTrackSeed(
                        position: 3,
                        artist: "Missing Artist",
                        title: "Find This One",
                        album: "Next Download",
                        lengthSeconds: 198
                    ),
                    disposition: .downloadRequired,
                    localPath: nil,
                    quality: nil
                )
            ]
        )

        let summary = LibraryReuseAnalysisSummaryCard(analysis: analysis, onShowTracks: {})
            .padding(20)
            .frame(width: 680, height: 270, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))

        let trackList = PlaylistTrackListSheet(analysis: analysis)
            .frame(width: 860, height: 720)
            .background(Color(nsColor: .windowBackgroundColor))

        let summaryPNG = try renderPNG(AnyView(summary), size: NSSize(width: 680, height: 270))
        let trackListPNG = try renderPNG(AnyView(trackList), size: NSSize(width: 860, height: 720))

        XCTAssertGreaterThan(summaryPNG.count, 10_000)
        XCTAssertGreaterThan(trackListPNG.count, 20_000)

        if let outputPath = ProcessInfo.processInfo.environment["SEEKSYNC_VISUAL_QA_DIR"], !outputPath.isEmpty {
            let outputDirectory = URL(fileURLWithPath: outputPath, isDirectory: true)
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            try summaryPNG.write(
                to: outputDirectory.appendingPathComponent("implementation-library-reuse-summary-680x270@2x.png"),
                options: .atomic
            )
            try trackListPNG.write(
                to: outputDirectory.appendingPathComponent("implementation-library-reuse-track-quality-860x720@2x.png"),
                options: .atomic
            )
        }
    }

    private func renderPNG(_ view: AnyView, size: NSSize) throws -> Data {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
        window.contentView = hostingView
        window.orderFront(nil)
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * 2),
            pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw XCTSkip("Could not allocate the offscreen bitmap.")
        }
        bitmap.size = size
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw XCTSkip("Could not encode the offscreen render as PNG.")
        }
        window.orderOut(nil)
        return png
    }
}

private final class StubURLProtocol: URLProtocol {
    static var data = Data()
    static var statusCode = 200
    static var handler: ((URLRequest) throws -> (statusCode: Int, data: Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let result: (statusCode: Int, data: Data)
            if let handler = Self.handler {
                result = try handler(request)
            } else {
                result = (statusCode: Self.statusCode, data: Self.data)
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: result.statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: result.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class ConfigDocumentTests: XCTestCase {
    func testUpdatesProfileWithoutLosingCommentsOrUnknownKeys() {
        let original = """
        # keep this comment
        username = listener
        mystery-setting = untouched

        [playlist]
        path = ~/Music/old
        pref-format = mp3
        """
        var document = ConfigDocument(raw: original)
        document.set("~/Music/new", for: "path", section: "playlist")
        document.set("flac", for: "pref-format", section: "playlist")

        XCTAssertTrue(document.rendered.contains("# keep this comment"))
        XCTAssertTrue(document.rendered.contains("mystery-setting = untouched"))
        XCTAssertTrue(document.rendered.contains("path = ~/Music/new"))
        XCTAssertTrue(document.rendered.contains("pref-format = flac"))
        XCTAssertEqual(document.value(for: "username"), "listener")
        XCTAssertEqual(document.value(for: "path", section: "playlist"), "~/Music/new")
    }

    func testQuotedValuesAreReadWithoutQuotes() {
        let document = ConfigDocument(raw: "spotify-id = \"abc123\"\n")
        XCTAssertEqual(document.value(for: "spotify-id"), "abc123")
    }
}

final class PrototypePersistenceTests: XCTestCase {
    private var root: URL!
    private var currentURL: URL!
    private var legacyURL: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("SeekSyncPersistence-\(UUID().uuidString)")
        currentURL = root.appendingPathComponent("SeekSync/state.json")
        legacyURL = root.appendingPathComponent("SeekSyncPrototype/prototype-state.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testMigratesLegacyStateWithoutDeletingIt() throws {
        let legacyState = state(outputDirectory: "~/Music/legacy")
        try PrototypePersistence(url: legacyURL).save(legacyState)

        let persistence = PrototypePersistence(url: currentURL, legacyURL: legacyURL)
        let restored = try persistence.load()

        XCTAssertEqual(restored.settings.outputDirectory, "~/Music/legacy")
        XCTAssertTrue(FileManager.default.fileExists(atPath: currentURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertEqual(try PrototypePersistence(url: currentURL).load().settings.outputDirectory, "~/Music/legacy")
    }

    func testCurrentStateTakesPriorityOverLegacyState() throws {
        try PrototypePersistence(url: legacyURL).save(state(outputDirectory: "~/Music/legacy"))
        try PrototypePersistence(url: currentURL).save(state(outputDirectory: "~/Music/current"))

        let restored = try PrototypePersistence(url: currentURL, legacyURL: legacyURL).load()

        XCTAssertEqual(restored.settings.outputDirectory, "~/Music/current")
    }

    private func state(outputDirectory: String) -> PrototypeState {
        var settings = ClientSettings()
        settings.outputDirectory = outputDirectory
        return PrototypeState(
            importedPlaylists: [],
            cachedSpotifyPlaylists: [],
            plans: [],
            runs: [],
            settings: settings
        )
    }
}

final class ConfigStoreTests: XCTestCase {
    private var directory: URL!
    private var configURL: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("SeekSyncTests-\(UUID().uuidString)")
        configURL = directory.appendingPathComponent("sockseek.conf")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try """
        # fixture
        username = tester
        password = private-value
        path = ~/Music/downloads
        pref-format = flac
        yt-dlp = true

        [playlist]
        path = ~/Music/downloads
        pref-format = flac
        custom = keep-me
        """.write(to: configURL, atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testRoundTripCreatesBackupAndPreservesUnknownProfileKey() throws {
        let store = ConfigStore()
        var loaded = try store.load(from: configURL, binaryPath: "/tmp/sockseek")
        loaded.settings.outputDirectory = "~/Music/new"
        loaded.settings.allowYouTubeFallback = false
        _ = try store.save(
            settings: loaded.settings,
            document: loaded.document,
            to: configURL,
            expectedRevision: loaded.revision
        )

        let saved = try String(contentsOf: configURL)
        XCTAssertTrue(saved.contains("path = ~/Music/new"))
        XCTAssertTrue(saved.contains("yt-dlp = false"))
        XCTAssertTrue(saved.contains("custom = keep-me"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: configURL.path + ".seeksync-backup"))
        let permissions = try FileManager.default.attributesOfItem(atPath: configURL.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testRefusesToOverwriteExternalEdit() throws {
        let store = ConfigStore()
        let loaded = try store.load(from: configURL, binaryPath: "/tmp/sockseek")
        try "# externally changed and longer\nusername = somebody-else\n".write(to: configURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(
            try store.save(
                settings: loaded.settings,
                document: loaded.document,
                to: configURL,
                expectedRevision: loaded.revision
            )
        ) { error in
            guard case ConfigStoreError.externallyModified = error else {
                return XCTFail("Expected external modification error, got \(error)")
            }
        }
    }

    func testRefusesExistingFileWhenItWasNeverLoaded() throws {
        let store = ConfigStore()
        XCTAssertThrowsError(
            try store.save(
                settings: ClientSettings(),
                document: ConfigDocument(raw: ""),
                to: configURL,
                expectedRevision: nil
            )
        ) { error in
            guard case ConfigStoreError.existingFileWasNotLoaded = error else {
                return XCTFail("Expected safe existing-file refusal, got \(error)")
            }
        }
    }

    func testProfileFallbackAndCredentialClearingRoundTrip() throws {
        try """
        username = tester
        password = remove-me
        yt-dlp = false

        [lossless]
        output-dir = /Volumes/Music
        pref-format = flac
        yt-dlp = true
        """.write(to: configURL, atomically: true, encoding: .utf8)
        let store = ConfigStore()
        var loaded = try store.load(from: configURL, binaryPath: "/tmp/sockseek", preferredProfile: "lossless")
        XCTAssertEqual(loaded.settings.profileName, "lossless")
        XCTAssertTrue(loaded.settings.allowYouTubeFallback)
        loaded.settings.soulseekPassword = ""
        _ = try store.save(settings: loaded.settings, document: loaded.document, to: configURL, expectedRevision: loaded.revision)
        let saved = try String(contentsOf: configURL)
        XCTAssertTrue(saved.contains("password = \n") || saved.contains("password =\n"))
        XCTAssertTrue(saved.contains("[lossless]"))
        XCTAssertTrue(saved.contains("yt-dlp = true"))
    }

    func testPreservesMultiFormatPreferenceOnUnrelatedSave() throws {
        try """
        username = tester
        password = fixture
        output-dir = /Volumes/Music
        pref-format = flac,wav
        """.write(to: configURL, atomically: true, encoding: .utf8)
        let store = ConfigStore()
        var loaded = try store.load(from: configURL, binaryPath: "/tmp/sockseek")
        loaded.settings.allowYouTubeFallback = true
        _ = try store.save(settings: loaded.settings, document: loaded.document, to: configURL, expectedRevision: loaded.revision)
        XCTAssertTrue(try String(contentsOf: configURL).contains("pref-format = flac,wav"))
    }

    func testPreferredBitrateLoadsAndRoundTripsThroughSelectedProfile() throws {
        try """
        username = tester
        password = fixture

        [playlist]
        output-dir = /Volumes/Music
        pref-format = mp3
        pref-min-bitrate = 320
        """.write(to: configURL, atomically: true, encoding: .utf8)
        let store = ConfigStore()
        var loaded = try store.load(from: configURL, binaryPath: "/tmp/sockseek")
        XCTAssertEqual(loaded.settings.preferredFormat, .mp3)
        XCTAssertEqual(loaded.settings.preferredMinBitrateValue, .kbps320)

        loaded.settings.preferredMinBitrate = .kbps256
        loaded.settings.preferredMinBitrateRaw = "256"
        _ = try store.save(
            settings: loaded.settings,
            document: loaded.document,
            to: configURL,
            expectedRevision: loaded.revision
        )
        XCTAssertTrue(try String(contentsOf: configURL).contains("pref-min-bitrate = 256"))
    }

    func testPreservesCustomPreferredBitrateOnUnrelatedSave() throws {
        try """
        username = tester
        password = fixture
        output-dir = /Volumes/Music
        pref-format = mp3
        pref-min-bitrate = 224
        """.write(to: configURL, atomically: true, encoding: .utf8)
        let store = ConfigStore()
        var loaded = try store.load(from: configURL, binaryPath: "/tmp/sockseek")
        loaded.settings.allowYouTubeFallback = true

        _ = try store.save(
            settings: loaded.settings,
            document: loaded.document,
            to: configURL,
            expectedRevision: loaded.revision
        )

        XCTAssertTrue(try String(contentsOf: configURL).contains("pref-min-bitrate = 224"))
    }
}

final class LibraryMoverTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("SeekSyncLibraryMover-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testMovesLibraryContentsIntoChosenFolder() throws {
        let source = root.appendingPathComponent("Old", isDirectory: true)
        let destination = root.appendingPathComponent("New", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("track".utf8).write(to: source.appendingPathComponent("Track.flac"))
        try FileManager.default.createDirectory(at: source.appendingPathComponent("Playlist", isDirectory: true), withIntermediateDirectories: true)

        let result = try LibraryMover().moveContents(from: source, to: destination)

        XCTAssertEqual(result.movedItemCount, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Track.flac").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Playlist").path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: source.path), [])
    }

    func testConflictStopsBeforeAnythingMoves() throws {
        let source = root.appendingPathComponent("Old", isDirectory: true)
        let destination = root.appendingPathComponent("New", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: source.appendingPathComponent("Track.flac"))
        try Data("new".utf8).write(to: destination.appendingPathComponent("Track.flac"))

        XCTAssertThrowsError(try LibraryMover().moveContents(from: source, to: destination)) { error in
            XCTAssertEqual(error as? LibraryMoveError, .conflicts(["Track.flac"]))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.appendingPathComponent("Track.flac").path))
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("Track.flac")), "new")
    }
}

final class ClientSettingsCodingTests: XCTestCase {
    func testDecodesSavedSettingsFromBeforeBitratePreferenceWasAdded() throws {
        let encoded = try JSONEncoder().encode(ClientSettings())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "preferredMinBitrate")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(ClientSettings.self, from: legacyData)

        XCTAssertEqual(decoded.preferredMinBitrateValue, .kbps200)
    }

    func testDecodesSavedSettingsFromBeforeLibraryReuseWasAdded() throws {
        let encoded = try JSONEncoder().encode(ClientSettings())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "libraryReuseEnabled")
        object.removeValue(forKey: "libraryDirectory")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(ClientSettings.self, from: legacyData)

        XCTAssertFalse(decoded.isLibraryReuseEnabled)
        XCTAssertEqual(decoded.libraryDirectoryPath, "")
    }
}

final class SockseekCommandBuilderTests: XCTestCase {
    func testBuildsV3PlaylistCommandWithStableIndexAndExplicitFallback() {
        var settings = ClientSettings()
        settings.binaryPath = "/Users/test/.local/bin/sockseek"
        settings.configPath = "/Users/test/.config/sockseek/sockseek.conf"
        settings.outputDirectory = "~/Music/downloads"
        settings.profileName = "playlist"
        settings.preferredFormat = .flac
        settings.allowYouTubeFallback = true
        settings.lookForPreferredQuality = true

        let playlist = Playlist.samples[0]
        let command = SockseekCommandBuilder().command(for: playlist, settings: settings, youtubePolicy: .never)

        XCTAssertEqual(command.executable, settings.binaryPath)
        XCTAssertEqual(command.arguments.first, playlist.spotifyURL)
        XCTAssertTrue(command.arguments.contains("--progress-json"))
        XCTAssertTrue(command.arguments.contains("--no-progress"))
        XCTAssertTrue(command.arguments.contains("--skip-check-pref-cond"))
        XCTAssertTrue(command.arguments.contains("--write-playlist"))
        XCTAssertTrue(command.arguments.contains("--index-path"))
        XCTAssertTrue(command.arguments.contains("~/Music/downloads/.seeksync-index-midnight-drive.csv"))
        let fallbackIndex = try! XCTUnwrap(command.arguments.firstIndex(of: "--yt-dlp"))
        XCTAssertEqual(command.arguments[fallbackIndex + 1], "false")
        XCTAssertFalse(command.displayString.contains("password"))
        XCTAssertFalse(command.displayString.contains("secret"))
    }

    func testDoesNotForceQualityRecheckWhenDisabled() {
        var settings = ClientSettings()
        settings.binaryPath = "/tmp/sockseek"
        settings.configPath = "/tmp/sockseek.conf"
        settings.lookForPreferredQuality = false
        let command = SockseekCommandBuilder().command(for: Playlist.samples[0], settings: settings)
        let index = try! XCTUnwrap(command.arguments.firstIndex(of: "--skip-check-pref-cond"))
        XCTAssertEqual(command.arguments[index + 1], "false")
    }

    func testLibraryReuseAddsTagMatcherAndForcesQualityAndPlaylistOutput() {
        var settings = ClientSettings()
        settings.binaryPath = "/tmp/sockseek"
        settings.configPath = "/tmp/sockseek.conf"
        settings.libraryReuseEnabled = true
        settings.libraryDirectory = "/Volumes/Music Library"
        settings.lookForPreferredQuality = false
        settings.writeM3UPlaylist = false
        settings.preferredMinBitrateRaw = "320"
        let conditions = LibraryReuseConditionPolicy(arguments: ["--pref-max-bitrate", "384"])

        let command = SockseekCommandBuilder().command(
            for: Playlist.samples[0],
            settings: settings,
            libraryReuseConditionPolicy: conditions
        )

        XCTAssertEqual(value(after: "--skip-music-dir", in: command), "/Volumes/Music Library")
        XCTAssertEqual(value(after: "--skip-mode-music-dir", in: command), "tag")
        XCTAssertEqual(value(after: "--skip-mode-output-dir", in: command), "index")
        XCTAssertEqual(value(after: "--skip-existing", in: command), "true")
        XCTAssertEqual(value(after: "--skip-check-pref-cond", in: command), "true")
        XCTAssertEqual(value(after: "--write-playlist", in: command), "true")
        XCTAssertEqual(value(after: "--pref-min-bitrate", in: command), "320")
        XCTAssertEqual(value(after: "--pref-max-bitrate", in: command), "384")
    }

    func testAbsoluteOutputDirectoryKeepsLeadingSlash() {
        let path = SockseekCommandBuilder().indexPath(for: Playlist.samples[0], outputDirectory: "/Volumes/External4TB/Music")
        XCTAssertEqual(path, "/Volumes/External4TB/Music/.seeksync-index-midnight-drive.csv")
    }

    func testBoundedAcceptanceCommandLimitsTrackCount() {
        var settings = ClientSettings()
        settings.binaryPath = "/tmp/sockseek"
        settings.configPath = "/tmp/sockseek.conf"

        let command = SockseekCommandBuilder().command(
            for: Playlist.samples[0],
            settings: settings,
            youtubePolicy: .never,
            maximumTracks: 1
        )

        let numberIndex = try! XCTUnwrap(command.arguments.firstIndex(of: "--number"))
        XCTAssertEqual(command.arguments[numberIndex + 1], "1")
    }

    private func value(after flag: String, in command: SLDLCommand) -> String? {
        guard let index = command.arguments.firstIndex(of: flag),
              command.arguments.indices.contains(index + 1) else { return nil }
        return command.arguments[index + 1]
    }
}

@MainActor
final class LibraryInventoryRenderTests: XCTestCase {
    func testInventorySectionRendersTracksAcrossPlaylists() throws {
        let stateDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SeekSyncInventoryRender-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        defer {
            unsetenv("SEEKSYNC_STATE_PATH")
            try? FileManager.default.removeItem(at: stateDirectory)
        }

        var settings = ClientSettings()
        settings.libraryReuseEnabled = true
        settings.libraryDirectory = "/Users/example/Music/Library"
        let state = PrototypeState(
            importedPlaylists: [],
            cachedSpotifyPlaylists: nil,
            plans: [],
            runs: [],
            settings: settings,
            libraryAnalyses: [
                "late-night": Self.analysis(
                    id: "late-night",
                    name: "Late Night",
                    tracks: [
                        Self.track(1, "Radiohead", "Nude", .libraryBelowThreshold, "/Users/example/Music/Library/Radiohead/In Rainbows/Nude.mp3", 128),
                        Self.track(2, "Boards of Canada", "Roygbiv", .libraryReference, "/Users/example/Music/Library/BoC/Roygbiv.flac", nil),
                        Self.track(3, "Burial", "Archangel", .downloadRequired, nil, nil)
                    ]
                ),
                "focus": Self.analysis(
                    id: "focus",
                    name: "Focus",
                    tracks: [
                        Self.track(1, "Boards of Canada", "Roygbiv", .libraryReference, "/Users/example/Music/Library/BoC/Roygbiv.flac", nil),
                        Self.track(2, "Aphex Twin", "Xtal", .downloaded, "/Users/example/SeekSync/Xtal.mp3", 320),
                        Self.track(3, "Autechre", "Gantz Graf", .unavailable, nil, nil)
                    ]
                )
            ]
        )
        let stateURL = stateDirectory.appendingPathComponent("state.json")
        try PrototypePersistence(url: stateURL).save(state)
        setenv("SEEKSYNC_STATE_PATH", stateURL.path, 1)

        let model = AppModel()
        XCTAssertEqual(model.analyzedTrackCount, 5, "Roygbiv should collapse into a single row.")

        let screen = LibraryInventoryScreen()
            .environmentObject(model)
            .frame(width: 980, height: 720)
            .background(Color(nsColor: .windowBackgroundColor))
        let png = try renderPNG(AnyView(screen), size: NSSize(width: 980, height: 720))
        XCTAssertGreaterThan(png.count, 20_000)

        if let outputPath = ProcessInfo.processInfo.environment["SEEKSYNC_VISUAL_QA_DIR"], !outputPath.isEmpty {
            let outputDirectory = URL(fileURLWithPath: outputPath, isDirectory: true)
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            try png.write(
                to: outputDirectory.appendingPathComponent("implementation-track-inventory-980x720@2x.png"),
                options: .atomic
            )
        }
    }

    private static func track(
        _ position: Int,
        _ artist: String,
        _ title: String,
        _ disposition: PlaylistTrackDisposition,
        _ localPath: String?,
        _ bitrate: Int?
    ) -> PlaylistTrackRecord {
        PlaylistTrackRecord(
            seed: PlaylistTrackSeed(
                position: position,
                artist: artist,
                title: title,
                album: "Album",
                lengthSeconds: 243
            ),
            disposition: disposition,
            localPath: localPath,
            quality: bitrate.map {
                AudioFileQuality(
                    format: "mp3",
                    bitrateKbps: $0,
                    sampleRateHz: 44_100,
                    bitDepth: nil,
                    durationSeconds: 243
                )
            }
        )
    }

    private static func analysis(
        id: String,
        name: String,
        tracks: [PlaylistTrackRecord]
    ) -> PlaylistLibraryAnalysis {
        PlaylistLibraryAnalysis(
            playlistID: id,
            playlistName: name,
            analyzedAt: Date(timeIntervalSince1970: 1_780_000_000),
            sourceLibraryPath: "/Users/example/Music/Library",
            preferredFormat: "mp3",
            minimumBitrateKbps: 256,
            tracks: tracks,
            basis: .preview
        )
    }

    private func renderPNG(_ view: AnyView, size: NSSize) throws -> Data {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
        window.contentView = hostingView
        window.orderFront(nil)
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()

        guard let representation = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            throw XCTSkip("The renderer could not create a bitmap for the inventory screen.")
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)
        window.orderOut(nil)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw XCTSkip("The renderer could not encode the inventory screen.")
        }
        return data
    }
}

final class LibraryInventoryTests: XCTestCase {
    private func track(
        position: Int,
        artist: String,
        title: String,
        disposition: PlaylistTrackDisposition,
        localPath: String? = nil,
        quality: AudioFileQuality? = nil
    ) -> PlaylistTrackRecord {
        PlaylistTrackRecord(
            seed: PlaylistTrackSeed(
                position: position,
                artist: artist,
                title: title,
                album: "Album",
                lengthSeconds: 200
            ),
            disposition: disposition,
            localPath: localPath,
            quality: quality
        )
    }

    private func analysis(
        id: String,
        name: String,
        tracks: [PlaylistTrackRecord],
        analyzedAt: Date = Date(timeIntervalSince1970: 1_000)
    ) -> PlaylistLibraryAnalysis {
        PlaylistLibraryAnalysis(
            playlistID: id,
            playlistName: name,
            analyzedAt: analyzedAt,
            sourceLibraryPath: "/Music",
            preferredFormat: "mp3",
            minimumBitrateKbps: 256,
            tracks: tracks
        )
    }

    func testCollapsesATrackSharedByPlaylistsIntoOneRow() {
        let inventory = LibraryInventory(analyses: [
            analysis(id: "a", name: "Late Night", tracks: [
                track(position: 1, artist: "Boards of Canada", title: "Roygbiv", disposition: .libraryReference, localPath: "/Music/roygbiv.flac")
            ]),
            analysis(id: "b", name: "Focus", tracks: [
                track(position: 4, artist: "boards of canada", title: "  Roygbiv ", disposition: .libraryReference, localPath: "/Music/roygbiv.flac")
            ])
        ])

        XCTAssertEqual(inventory.entries.count, 1)
        let entry = try? XCTUnwrap(inventory.entries.first)
        XCTAssertEqual(entry?.playlistNames, ["Focus", "Late Night"])
        XCTAssertTrue(entry?.isSharedAcrossPlaylists == true)
        XCTAssertEqual(entry?.availability, .referenced)
        XCTAssertFalse(entry?.variesByPlaylist == true)
        XCTAssertEqual(inventory.playlistCount, 2)
    }

    func testReportsTheMostUsableStateAndFlagsPlaylistsThatDisagree() throws {
        let inventory = LibraryInventory(analyses: [
            analysis(id: "a", name: "Strict", tracks: [
                track(position: 1, artist: "Radiohead", title: "Nude", disposition: .libraryBelowThreshold, localPath: "/Music/nude.mp3")
            ]),
            analysis(id: "b", name: "Relaxed", tracks: [
                track(
                    position: 1,
                    artist: "Radiohead",
                    title: "Nude",
                    disposition: .libraryReference,
                    localPath: "/Music/nude.mp3",
                    quality: AudioFileQuality(format: "mp3", bitrateKbps: 192, sampleRateHz: 44_100, bitDepth: nil, durationSeconds: 250)
                )
            ])
        ])

        let entry = try XCTUnwrap(inventory.entries.first)
        XCTAssertEqual(entry.availability, .referenced)
        XCTAssertTrue(entry.variesByPlaylist)
        XCTAssertEqual(entry.localPath, "/Music/nude.mp3")
        XCTAssertEqual(entry.quality?.bitrateKbps, 192)
    }

    func testCountsWhatIsAlreadyOwnedSeparatelyFromWhatMustBeDownloaded() {
        let inventory = LibraryInventory(analyses: [
            analysis(id: "a", name: "Mixed", tracks: [
                track(position: 1, artist: "A", title: "Referenced", disposition: .libraryReference, localPath: "/Music/a.flac"),
                track(position: 2, artist: "B", title: "Below", disposition: .libraryBelowThreshold, localPath: "/Music/b.mp3"),
                track(position: 3, artist: "C", title: "Downloaded", disposition: .downloaded, localPath: "/Downloads/c.mp3"),
                track(position: 4, artist: "D", title: "Missing", disposition: .downloadRequired),
                track(position: 5, artist: "E", title: "Unresolved", disposition: .unknown)
            ])
        ])

        XCTAssertEqual(inventory.alreadyOwnedCount, 3)
        let counts = inventory.counts()
        XCTAssertEqual(counts[.referenced], 1)
        XCTAssertEqual(counts[.belowTarget], 1)
        XCTAssertEqual(counts[.downloaded], 1)
        XCTAssertEqual(counts[.missing], 1)
        XCTAssertEqual(counts[.unavailable], 1)
    }

    func testListsOwnedButUnusableTracksBeforeSettledOnes() {
        let inventory = LibraryInventory(analyses: [
            analysis(id: "a", name: "Mixed", tracks: [
                track(position: 1, artist: "A", title: "Referenced", disposition: .libraryReference, localPath: "/Music/a.flac"),
                track(position: 2, artist: "B", title: "Below", disposition: .libraryBelowThreshold, localPath: "/Music/b.mp3"),
                track(position: 3, artist: "C", title: "Missing", disposition: .downloadRequired)
            ])
        ])

        XCTAssertEqual(
            inventory.filtered(availability: nil, query: "").map(\.title),
            ["Below", "Missing", "Referenced"]
        )
    }

    func testFiltersByStateAndSearchesPathsAndPlaylistNames() {
        let inventory = LibraryInventory(analyses: [
            analysis(id: "a", name: "Late Night", tracks: [
                track(position: 1, artist: "Aphex Twin", title: "Xtal", disposition: .libraryBelowThreshold, localPath: "/Music/Ambient Works/xtal.mp3"),
                track(position: 2, artist: "Burial", title: "Archangel", disposition: .downloadRequired)
            ])
        ])

        XCTAssertEqual(
            inventory.filtered(availability: .belowTarget, query: "").map(\.title),
            ["Xtal"]
        )
        XCTAssertEqual(
            inventory.filtered(availability: nil, query: "ambient works").map(\.title),
            ["Xtal"]
        )
        XCTAssertEqual(
            inventory.filtered(availability: nil, query: "late night").count,
            2
        )
        XCTAssertTrue(inventory.filtered(availability: .referenced, query: "").isEmpty)
    }

    func testEmptyAnalysesProduceAnEmptyInventory() {
        let inventory = LibraryInventory(analyses: [])

        XCTAssertTrue(inventory.entries.isEmpty)
        XCTAssertEqual(inventory.playlistCount, 0)
        XCTAssertNil(inventory.analyzedAt)
        XCTAssertEqual(inventory.alreadyOwnedCount, 0)
    }
}

final class LibraryPreviewIndexCacheTests: XCTestCase {
    private var root: URL!
    private var library: URL!
    private var cache: LibraryPreviewIndexCache!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SeekSyncPreviewCache-\(UUID().uuidString)")
        library = root.appendingPathComponent("library")
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        cache = LibraryPreviewIndexCache(directory: root.appendingPathComponent("cache"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func key(conditionFingerprint: String = "fingerprint") -> LibraryPreviewIndexCache.Key {
        LibraryPreviewIndexCache.Key(
            playlistID: "playlist",
            libraryPath: library.path,
            preferredFormat: "mp3",
            minimumBitrateKbps: 256,
            conditionFingerprint: conditionFingerprint
        )
    }

    private func entry(path: String?, title: String, state: Int) -> SockseekIndexEntry {
        SockseekIndexEntry(
            path: path,
            artist: "Artist",
            album: "Album",
            title: title,
            lengthSeconds: 200,
            state: state,
            failureReason: 0
        )
    }

    @discardableResult
    private func addLibraryFile(named name: String) throws -> URL {
        let url = library.appendingPathComponent(name)
        try Data("audio".utf8).write(to: url)
        return url
    }

    func testReusesStoredIndexWhileTheLibraryIsUnchanged() throws {
        let file = try addLibraryFile(named: "track.mp3")
        let stamp = try XCTUnwrap(LibraryScanStamp.make(libraryPath: library.path))
        let snapshot = LibraryPreviewIndexCache.Snapshot(
            gated: [entry(path: file.path, title: "Kept", state: 3)],
            ungated: [entry(path: file.path, title: "Kept", state: 3)]
        )

        cache.store(key: key(), stamp: stamp, snapshot: snapshot)

        XCTAssertEqual(cache.load(key: key(), stamp: stamp), snapshot)
    }

    func testAddedLibraryFileInvalidatesTheStoredIndex() throws {
        let file = try addLibraryFile(named: "track.mp3")
        let stamp = try XCTUnwrap(LibraryScanStamp.make(libraryPath: library.path))
        cache.store(
            key: key(),
            stamp: stamp,
            snapshot: LibraryPreviewIndexCache.Snapshot(
                gated: [entry(path: file.path, title: "Kept", state: 3)],
                ungated: []
            )
        )

        try addLibraryFile(named: "newly-ripped.mp3")
        let currentStamp = try XCTUnwrap(LibraryScanStamp.make(libraryPath: library.path))

        XCTAssertNotEqual(currentStamp, stamp)
        XCTAssertNil(cache.load(key: key(), stamp: currentStamp))
    }

    func testDifferentReuseConditionsDoNotShareAStoredIndex() throws {
        let file = try addLibraryFile(named: "track.mp3")
        let stamp = try XCTUnwrap(LibraryScanStamp.make(libraryPath: library.path))
        cache.store(
            key: key(),
            stamp: stamp,
            snapshot: LibraryPreviewIndexCache.Snapshot(
                gated: [entry(path: file.path, title: "Kept", state: 3)],
                ungated: []
            )
        )

        XCTAssertNil(cache.load(key: key(conditionFingerprint: "stricter"), stamp: stamp))
    }

    func testDropsRowsWhoseFileDisappearedButKeepsUnresolvedRows() throws {
        let kept = try addLibraryFile(named: "kept.mp3")
        let removed = try addLibraryFile(named: "removed.mp3")
        let stamp = try XCTUnwrap(LibraryScanStamp.make(libraryPath: library.path))
        cache.store(
            key: key(),
            stamp: stamp,
            snapshot: LibraryPreviewIndexCache.Snapshot(
                gated: [
                    entry(path: kept.path, title: "Kept", state: 3),
                    entry(path: removed.path, title: "Removed", state: 3),
                    entry(path: nil, title: "Never Found", state: 2)
                ],
                ungated: []
            )
        )

        try FileManager.default.removeItem(at: removed)
        // The stamp is deliberately the recorded one: this asserts the row
        // filter, not the invalidation an actual removal would also trigger.
        let loaded = try XCTUnwrap(cache.load(key: key(), stamp: stamp))

        XCTAssertEqual(loaded.gated.map(\.title), ["Kept", "Never Found"])
    }

    func testExpiredEntriesAreNotReused() throws {
        let file = try addLibraryFile(named: "track.mp3")
        let stamp = try XCTUnwrap(LibraryScanStamp.make(libraryPath: library.path))
        let storedAt = Date()
        cache.store(
            key: key(),
            stamp: stamp,
            snapshot: LibraryPreviewIndexCache.Snapshot(
                gated: [entry(path: file.path, title: "Kept", state: 3)],
                ungated: []
            ),
            now: storedAt
        )

        let expired = storedAt.addingTimeInterval(LibraryPreviewIndexCache.maximumAge + 1)
        XCTAssertNil(cache.load(key: key(), stamp: stamp, now: expired))
    }
}

final class LibraryReuseTests: XCTestCase {
    func testParsesJobsFullOutputInPlaylistOrder() {
        let output = """
        [001] ExtractJob: Spotify: Input: playlist
        2 jobs:
          Song:
            Artist:             First Artist
            Title:              First Track
            Album:              First Album
            Length:             241s
            URL/ID:             spotify:track:first

          Song:
            Artist:             Second Artist
            Title:              Second Track
            Length:             199s
        """

        let tracks = SockseekJobsFullParser().parse(output)

        XCTAssertEqual(tracks.count, 2)
        XCTAssertEqual(tracks[0].position, 1)
        XCTAssertEqual(tracks[0].artist, "First Artist")
        XCTAssertEqual(tracks[0].album, "First Album")
        XCTAssertEqual(tracks[0].lengthSeconds, 241)
        XCTAssertEqual(tracks[1].position, 2)
        XCTAssertNil(tracks[1].album)
    }

    func testParsesQuotedAndRelativeSockseekIndexRows() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SeekSyncIndexParser-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let index = directory.appendingPathComponent("index.csv")
        try """
        filepath,artist,album,title,length,tracktype,state,failurereason
        "./Artist/Track, Mix.mp3","Artist, Guest",Album,"Track, Mix",240,0,3,0
        ,Missing Artist,,Missing Track,-1,0,2,9

        """.write(to: index, atomically: true, encoding: .utf8)

        let entries = try SockseekIndexParser().parse(url: index)

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].artist, "Artist, Guest")
        XCTAssertEqual(entries[0].title, "Track, Mix")
        XCTAssertEqual(
            entries[0].path,
            directory.appendingPathComponent("Artist/Track, Mix.mp3").standardizedFileURL.path
        )
        XCTAssertTrue(entries[0].isExisting)
        XCTAssertNil(entries[1].path)
        XCTAssertEqual(entries[1].state, 2)
    }

    func testCompletedRunInventoryUsesStableIndexAndKeepsAnUnreplacedBelowTargetFileVisible() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SeekSyncCompletedInventory-\(UUID().uuidString)")
        let library = root.appendingPathComponent("library")
        let output = root.appendingPathComponent("downloads")
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let referenced = library.appendingPathComponent("reference.mp3")
        let belowTarget = output.appendingPathComponent("below.mp3")
        let downloaded = output.appendingPathComponent("downloaded.mp3")
        try Data([0]).write(to: referenced)
        try Data([0]).write(to: belowTarget)
        try Data([0]).write(to: downloaded)

        let seeds = [
            PlaylistTrackSeed(position: 1, artist: "Local Artist", title: "Reference", album: "Album", lengthSeconds: 180),
            PlaylistTrackSeed(position: 2, artist: "New Artist", title: "Downloaded", album: "Album", lengthSeconds: 181),
            PlaylistTrackSeed(position: 3, artist: "Old Artist", title: "Upgrade Failed", album: "Album", lengthSeconds: 182)
        ]
        let playlist = Playlist.samples[0]
        let previous = PlaylistLibraryAnalysis(
            playlistID: playlist.id,
            playlistName: playlist.name,
            analyzedAt: Date(timeIntervalSince1970: 1),
            sourceLibraryPath: library.path,
            preferredFormat: "mp3",
            minimumBitrateKbps: 256,
            tracks: [
                PlaylistTrackRecord(seed: seeds[0], disposition: .libraryReference, localPath: referenced.path, quality: nil),
                PlaylistTrackRecord(seed: seeds[1], disposition: .downloadRequired, localPath: nil, quality: nil),
                PlaylistTrackRecord(
                    seed: seeds[2],
                    disposition: .libraryBelowThreshold,
                    localPath: belowTarget.path,
                    quality: AudioFileQuality(format: "mp3", bitrateKbps: 128, sampleRateHz: 44_100, bitDepth: nil, durationSeconds: 182)
                )
            ]
        )
        let index = output.appendingPathComponent("playlist-index.csv")
        try """
        filepath,artist,album,title,length,tracktype,state,failurereason
        \(referenced.path),Local Artist,Album,Reference,180,0,3,0
        \(downloaded.path),New Artist,Album,Downloaded,181,0,1,0
        ,Old Artist,Album,Upgrade Failed,182,0,2,9

        """.write(to: index, atomically: true, encoding: .utf8)
        let command = SLDLCommand(
            executable: "/tmp/sockseek",
            arguments: [
                playlist.spotifyURL,
                "--output-dir", output.path,
                "--index-path", index.path,
                "--skip-music-dir", library.path,
                "--pref-format", "mp3",
                "--pref-min-bitrate", "256"
            ]
        )

        // Real Sockseek track_list events include only a sample of pending
        // tracks; the stable index has the full playlist at completion.
        let sampledResult = try await LibraryReuseAnalyzer().completedAnalysis(
            playlist: playlist,
            seeds: Array(seeds.prefix(1)),
            previousAnalysis: nil,
            command: command
        )
        XCTAssertEqual(sampledResult?.tracks.count, 3)
        XCTAssertEqual(sampledResult?.tracks.map(\.seed.title), seeds.map(\.title))

        let result = try await LibraryReuseAnalyzer().completedAnalysis(
            playlist: playlist,
            seeds: seeds,
            previousAnalysis: previous,
            command: command
        )
        let analysis = try XCTUnwrap(result)

        XCTAssertEqual(analysis.tracks.map(\.disposition), [
            .libraryReference,
            .downloaded,
            .libraryBelowThreshold
        ])
        XCTAssertEqual(analysis.tracks[0].localPath, referenced.path)
        XCTAssertEqual(analysis.tracks[1].localPath, downloaded.path)
        XCTAssertEqual(analysis.tracks[2].localPath, belowTarget.path)
        XCTAssertEqual(analysis.tracks[2].quality?.bitrateKbps, 128)
        XCTAssertEqual(analysis.targetLabel, "MP3 · at least 256 kbps")
    }

    func testInstalledSockseekPreviewSeparatesReferenceBelowTargetAndDownload() async throws {
        let binary = ConfigStore.detectedBinaryPath()
        guard FileManager.default.isExecutableFile(atPath: binary) else {
            throw XCTSkip("Sockseek is not installed on this machine.")
        }
        let ffmpegCandidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
        guard let ffmpeg = ffmpegCandidates.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            throw XCTSkip("ffmpeg is unavailable for generating tagged audio fixtures.")
        }

        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SeekSyncLibraryReuse-\(UUID().uuidString)")
        let library = root.appendingPathComponent("library")
        let output = root.appendingPathComponent("downloads")
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let runner = SockseekProcessRunner()
        try await makeTaggedMP3(
            executable: ffmpeg,
            output: library.appendingPathComponent("qualifying.mp3"),
            artist: "Preview Artist",
            title: "Qualifying Track",
            bitrate: "320k",
            runner: runner
        )
        try await makeTaggedMP3(
            executable: ffmpeg,
            output: library.appendingPathComponent("below.mp3"),
            artist: "Preview Artist",
            title: "Below Track",
            bitrate: "128k",
            runner: runner
        )
        try await makeTaggedMP3(
            executable: ffmpeg,
            output: output.appendingPathComponent("already-downloaded.mp3"),
            artist: "Preview Artist",
            title: "Already Downloaded",
            bitrate: "320k",
            runner: runner
        )

        let playlistCSV = root.appendingPathComponent("playlist.csv")
        try """
        Artist,Album,Title,Length
        Preview Artist,Preview Album,Qualifying Track,0
        Preview Artist,Preview Album,Below Track,0
        Preview Artist,Preview Album,Missing Track,0
        Preview Artist,Preview Album,Already Downloaded,0
        """.write(to: playlistCSV, atomically: true, encoding: .utf8)

        var settings = ClientSettings()
        settings.binaryPath = binary
        settings.configPath = repository.appendingPathComponent("Fixtures/sockseek.qa.conf").path
        settings.profileName = ""
        settings.libraryReuseEnabled = true
        settings.libraryDirectory = library.path
        settings.outputDirectory = output.path
        settings.preferredFormat = .mp3
        settings.preferredFormatRaw = "mp3"
        settings.preferredMinBitrate = .kbps256
        settings.preferredMinBitrateRaw = "256"
        let playlist = Playlist(
            id: "library-reuse-test",
            name: "Library reuse test",
            owner: "Tests",
            detail: "",
            spotifyURL: playlistCSV.path,
            artworkURL: nil,
            artworkHue: 0,
            trackCount: 4,
            localCount: 0,
            upgradeCandidates: 0,
            needsReview: 0,
            lastSyncedAt: nil,
            health: .neverSynced,
            isFixture: false
        )
        let stableIndex = URL(
            fileURLWithPath: SockseekCommandBuilder().indexPath(
                for: playlist,
                outputDirectory: output.path
            )
        )
        try """
        filepath,artist,album,title,length,tracktype,state,failurereason
        ./already-downloaded.mp3,Preview Artist,Preview Album,Already Downloaded,0,0,1,0

        """.write(to: stableIndex, atomically: true, encoding: .utf8)

        let cache = LibraryPreviewIndexCache(directory: root.appendingPathComponent("preview-index-cache"))
        let analyzer = LibraryReuseAnalyzer(cache: cache)
        let analysis = try await analyzer.analyze(playlist: playlist, settings: settings)

        XCTAssertEqual(analysis.tracks.map(\.disposition), [
            .libraryReference,
            .libraryBelowThreshold,
            .downloadRequired,
            .downloaded
        ])
        XCTAssertEqual(analysis.referenceCount, 1)
        XCTAssertEqual(analysis.belowThresholdCount, 1)
        XCTAssertEqual(analysis.downloadRequiredCount, 1)
        XCTAssertEqual(analysis.downloadedCount, 1)
        XCTAssertEqual(analysis.tracks[0].quality?.format, "mp3")
        XCTAssertNotNil(analysis.tracks[0].localPath)
        XCTAssertNotNil(analysis.tracks[1].localPath)
        XCTAssertNil(analysis.tracks[2].localPath)
        XCTAssertEqual(analysis.tracks[3].localPath, output.appendingPathComponent("already-downloaded.mp3").path)

        let largeCSV = root.appendingPathComponent("large-playlist.csv")
        let extraRows = (1...70).map { "Missing Artist,Missing Album,Missing Track \($0),0" }
        let originalCSV = try String(contentsOf: playlistCSV)
        try (originalCSV + "\n" + extraRows.joined(separator: "\n") + "\n")
            .write(to: largeCSV, atomically: true, encoding: .utf8)
        var largePlaylist = playlist
        largePlaylist.spotifyURL = largeCSV.path
        largePlaylist.trackCount = 74
        let previewStarted = Date()
        let largeAnalysis = try await analyzer.analyze(playlist: largePlaylist, settings: settings, forceReindex: true)
        XCTAssertLessThan(Date().timeIntervalSince(previewStarted), 30, "Offline previews must not wait for live Soulseek rate limits")
        XCTAssertEqual(largeAnalysis.tracks.count, 74)
        XCTAssertEqual(largeAnalysis.referenceCount, 1)
        XCTAssertEqual(largeAnalysis.belowThresholdCount, 1)
        XCTAssertEqual(largeAnalysis.downloadedCount, 1)
        XCTAssertEqual(largeAnalysis.downloadRequiredCount, 71)

        let historicalIndex = output.appendingPathComponent("historical-index.csv")
        try """
        filepath,artist,album,title,length,tracktype,state,failurereason
        ./already-downloaded.mp3,Preview Artist,Preview Album,Already Downloaded,0,0,1,0
        ./already-downloaded.mp3,Preview Artist,Preview Album,Already Downloaded,0,0,1,0
        ,Removed Artist,Old Album,Removed Song,0,0,2,9

        """.write(to: historicalIndex, atomically: true, encoding: .utf8)
        var changedSettings = settings
        changedSettings.binaryPath = "/missing-binary"
        changedSettings.configPath = "/missing-config"
        changedSettings.profileName = "changed-profile"
        let completed = try await analyzer.completedAnalysis(
            playlist: largePlaylist,
            seeds: Array(largeAnalysis.tracks.prefix(20).map(\.seed)),
            previousAnalysis: nil,
            command: SLDLCommand(executable: binary, arguments: [
                "--config", settings.configPath,
                "--index-path", historicalIndex.path, "--output-dir", output.path,
                "--skip-music-dir", library.path, "--pref-format", "mp3", "--pref-min-bitrate", "256"
            ]),
            settings: changedSettings
        )
        XCTAssertEqual(completed?.tracks.count, 74)
        XCTAssertEqual(completed?.tracks.map(\.seed.title), largeAnalysis.tracks.map(\.seed.title))
        XCTAssertEqual(completed?.downloadedCount, 1)
        XCTAssertEqual(completed?.hasCompletePlaylistMetadata, true)
        var shrinkingPlaylist = largePlaylist
        shrinkingPlaylist.trackCount = 100
        shrinkingPlaylist.applyLibraryAnalysis(try XCTUnwrap(completed))
        XCTAssertEqual(shrinkingPlaylist.trackCount, 74)

        // A second preview of an unchanged library must be served from the
        // cached index without changing what it reports.
        let cacheKey = LibraryPreviewIndexCache.Key(
            playlistID: playlist.id,
            libraryPath: library.resolvingSymlinksInPath().path,
            preferredFormat: settings.preferredFormatValue,
            minimumBitrateKbps: Int(settings.preferredMinBitrateConfigValue),
            conditionFingerprint: LibraryReuseConditionPolicy(arguments: []).fingerprint
        )
        let stamp = try XCTUnwrap(LibraryScanStamp.make(libraryPath: library.path))
        XCTAssertNotNil(cache.load(key: cacheKey, stamp: stamp), "The preview did not cache its index.")

        var reusedStages: [String] = []
        let cachedAnalysis = try await analyzer.analyze(playlist: playlist, settings: settings) { stage in
            reusedStages.append(stage)
        }
        XCTAssertEqual(cachedAnalysis.tracks.map(\.disposition), analysis.tracks.map(\.disposition))
        XCTAssertEqual(cachedAnalysis.tracks.map(\.localPath), analysis.tracks.map(\.localPath))
        XCTAssertTrue(
            reusedStages.contains { $0.localizedCaseInsensitiveContains("cached library index") },
            "Expected the cached index to be reported to the user: \(reusedStages)"
        )

        var forcedStages: [String] = []
        let reindexed = try await analyzer.analyze(playlist: playlist, settings: settings, forceReindex: true) { stage in
            forcedStages.append(stage)
        }
        XCTAssertFalse(forcedStages.contains { $0.localizedCaseInsensitiveContains("cached library index") })
        XCTAssertEqual(reindexed.tracks.map(\.disposition), analysis.tracks.map(\.disposition))
        XCTAssertEqual(reindexed.tracks[3].localPath, output.appendingPathComponent("already-downloaded.mp3").path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stableIndex.path))

        let advancedConditions = LibraryReuseConditionPolicy(
            arguments: ["--pref-max-bitrate", "200"]
        )
        let stricterAnalysis = try await analyzer.analyze(
            playlist: playlist,
            settings: settings,
            conditionPolicy: advancedConditions
        )
        XCTAssertEqual(stricterAnalysis.tracks.map(\.disposition), [
            .libraryBelowThreshold,
            .libraryBelowThreshold,
            .downloadRequired,
            .libraryBelowThreshold
        ])
        XCTAssertEqual(stricterAnalysis.conditionFingerprint, advancedConditions.fingerprint)

        do {
            _ = try await analyzer.analyze(
                playlist: playlist,
                settings: settings,
                conditionPolicy: LibraryReuseConditionPolicy(
                    arguments: ["--seeksync-invalid-preview-option", "true"]
                )
            )
            XCTFail("A failed preview pass must not accept the preseeded stable index.")
        } catch LibraryReuseAnalysisError.previewPassIncomplete(let pass, let status, _) {
            XCTAssertEqual(pass, "quality-gated")
            XCTAssertNotEqual(status, 0)
        } catch {
            XCTFail("Unexpected preview validation error: \(error)")
        }
    }

    private func makeTaggedMP3(
        executable: String,
        output: URL,
        artist: String,
        title: String,
        bitrate: String,
        runner: SockseekProcessRunner
    ) async throws {
        let result = try await runner.run(
            SLDLCommand(
                executable: executable,
                arguments: [
                    "-hide_banner", "-loglevel", "error", "-y",
                    "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo",
                    "-t", "0.4", "-b:a", bitrate,
                    "-metadata", "artist=\(artist)",
                    "-metadata", "title=\(title)",
                    "-metadata", "album=Preview Album",
                    output.path
                ]
            )
        )
        XCTAssertEqual(result.exitCode, 0, result.output)
    }
}

final class SockseekProgressParserTests: XCTestCase {
    func testReportsCurrentTrackAndByteLevelDownloadProgress() {
        var tracker = SockseekProgressTracker()

        tracker.consume(#"{"type":"track_list","data":{"total":2,"tracks":[{"index":0,"artist":"Artist One","title":"First Song","album":"First Album","length":213,"lifecycleState":"Pending","terminalOutcome":"None","skipReason":"None"},{"index":1,"artist":"Artist Two","title":"Second Song","lifecycleState":"Pending","terminalOutcome":"None","skipReason":"None"}]}}"#)
        tracker.consume(#"{"type":"search_start","data":{"artist":"Artist One","title":"First Song"}}"#)

        XCTAssertEqual(tracker.snapshot.totalTracks, 2)
        XCTAssertEqual(tracker.playlistTracks.count, 2)
        XCTAssertEqual(tracker.playlistTracks[0].position, 1)
        XCTAssertEqual(tracker.playlistTracks[0].album, "First Album")
        XCTAssertEqual(tracker.playlistTracks[0].lengthSeconds, 213)
        XCTAssertEqual(tracker.snapshot.completedTracks, 0)
        XCTAssertEqual(tracker.snapshot.currentTrack?.position, 1)
        XCTAssertEqual(tracker.snapshot.currentTrack?.artist, "Artist One")
        XCTAssertEqual(tracker.snapshot.currentTrack?.title, "First Song")
        XCTAssertEqual(tracker.snapshot.currentTrack?.activity, .searching)

        tracker.consume(#"{"type":"download_start","data":{"artist":"Artist One","title":"First Song","size":1000}}"#)
        tracker.consume(#"{"type":"download_progress","data":{"bytesTransferred":425,"totalBytes":1000,"percent":42.5}}"#)

        XCTAssertEqual(tracker.snapshot.currentTrack?.activity, .downloading)
        XCTAssertEqual(tracker.snapshot.currentTrack?.bytesTransferred, 425)
        XCTAssertEqual(tracker.snapshot.currentTrack?.totalBytes, 1000)
        XCTAssertEqual(tracker.snapshot.currentTrack?.downloadFraction ?? 0, 0.425, accuracy: 0.0001)
    }

    func testCountsCompletedAndFailedTracksWhileAdvancingCurrentSong() {
        var tracker = SockseekProgressTracker()
        tracker.consume(#"{"type":"track_list","data":{"total":2,"tracks":[{"index":0,"artist":"Artist One","title":"First Song","lifecycleState":"Pending","terminalOutcome":"None","skipReason":"None"},{"index":1,"artist":"Artist Two","title":"Second Song","lifecycleState":"Pending","terminalOutcome":"None","skipReason":"None"}]}}"#)
        tracker.consume(#"{"type":"track_state","data":{"artist":"Artist One","title":"First Song","lifecycleState":"Terminal","terminalOutcome":"Succeeded","skipReason":"None"}}"#)
        tracker.consume(#"{"type":"search_start","data":{"artist":"Artist Two","title":"Second Song"}}"#)

        XCTAssertEqual(tracker.snapshot.completedTracks, 1)
        XCTAssertEqual(tracker.snapshot.currentTrack?.position, 2)
        XCTAssertEqual(tracker.counts.added, 1)

        tracker.consume(#"{"type":"track_state","data":{"artist":"Artist Two","title":"Second Song","lifecycleState":"Terminal","terminalOutcome":"Failed","skipReason":"None","failureReason":"NoMatchingResults","rawResultCount":12,"lockedCount":0}}"#)

        XCTAssertEqual(tracker.snapshot.completedTracks, 2)
        XCTAssertNil(tracker.snapshot.currentTrack)
        XCTAssertEqual(tracker.counts.unavailable, 1)
        XCTAssertEqual(tracker.failures.count, 1)
        XCTAssertEqual(tracker.failures[0].position, 2)
        XCTAssertEqual(tracker.failures[0].artist, "Artist Two")
        XCTAssertEqual(tracker.failures[0].title, "Second Song")
        XCTAssertEqual(tracker.failures[0].failureReason, "NoMatchingResults")
        XCTAssertEqual(
            tracker.failures[0].reasonDescription,
            "12 Soulseek results were found, but none matched this track's requirements."
        )
    }

    func testExplainsPreviouslyMissingAndLockedOnlyTracks() {
        var tracker = SockseekProgressTracker()
        tracker.consume(#"{"type":"track_list","data":{"total":2,"tracks":[{"index":0,"artist":"Artist One","title":"First Song","lifecycleState":"Terminal","terminalOutcome":"Skipped","skipReason":"PreviouslyNotFound","failureReason":"NoSearchResults","rawResultCount":0,"lockedCount":0},{"index":1,"artist":"Artist Two","title":"Second Song","lifecycleState":"Terminal","terminalOutcome":"Failed","skipReason":"None","failureReason":"NoSearchResults","rawResultCount":3,"lockedCount":3}]}}"#)

        XCTAssertEqual(tracker.failures.map(\.position), [1, 2])
        XCTAssertEqual(
            tracker.failures[0].reasonDescription,
            "Skipped because an earlier sync found no matching file."
        )
        XCTAssertEqual(
            tracker.failures[1].reasonDescription,
            "Only 3 locked results were found; no downloadable file was available."
        )
    }

    func testDoesNotDuplicateTerminalTrackEvents() {
        var tracker = SockseekProgressTracker()
        let terminalTrack = #"{"type":"track_state","data":{"artist":"Artist One","title":"First Song","lifecycleState":"Terminal","terminalOutcome":"Failed","failureReason":"AllDownloadsFailed"}}"#
        tracker.consume(#"{"type":"track_list","data":{"total":1,"tracks":[{"index":0,"artist":"Artist One","title":"First Song","lifecycleState":"Pending","terminalOutcome":"None","skipReason":"None"}]}}"#)
        tracker.consume(terminalTrack)
        tracker.consume(terminalTrack)

        XCTAssertEqual(tracker.snapshot.completedTracks, 1)
        XCTAssertEqual(tracker.counts.unavailable, 1)
        XCTAssertEqual(tracker.failures.count, 1)
    }

    func testIdentifiesSoulseekOnlyAndCombinedSoulseekYtDlpFailures() {
        let trackList = #"{"type":"track_list","data":{"total":1,"tracks":[{"index":0,"artist":"Artist One","title":"First Song","album":"Album One","lifecycleState":"Pending","terminalOutcome":"None"}]}}"#
        let failed = #"{"type":"track_state","data":{"artist":"Artist One","title":"First Song","lifecycleState":"Terminal","terminalOutcome":"Failed","failureReason":"NoSearchResults","rawResultCount":0,"lockedCount":0}}"#

        var soulseekOnly = SockseekProgressTracker(youtubeFallbackEnabled: false)
        soulseekOnly.consume(trackList)
        soulseekOnly.consume(failed)
        XCTAssertEqual(soulseekOnly.failures[0].album, "Album One")
        XCTAssertEqual(soulseekOnly.failures[0].source, .soulseek)
        XCTAssertEqual(
            soulseekOnly.failures[0].reasonDescription,
            "No Soulseek file results were found. YouTube fallback was disabled for this run."
        )

        var withFallback = SockseekProgressTracker(youtubeFallbackEnabled: true)
        withFallback.consume(trackList)
        withFallback.consume(failed)
        XCTAssertEqual(withFallback.failures[0].source, .soulseekAndYouTube)
        XCTAssertEqual(
            withFallback.failures[0].reasonDescription,
            "Soulseek found no file, and yt-dlp found no usable YouTube result."
        )
    }

    func testSampledExistingTracksUseFullAggregateCount() throws {
        var tracker = SockseekProgressTracker()
        let tracks = (0..<20).map { index in
            ["index": index, "artist": "Artist", "title": "Track \(index)",
             "lifecycleState": "Terminal", "terminalOutcome": "Skipped", "skipReason": "AlreadyExists"] as [String: Any]
        }
        let event: [String: Any] = ["type": "track_list", "data": ["total": 24, "existing": 23, "pending": 1, "tracks": tracks]]
        let line = String(decoding: try JSONSerialization.data(withJSONObject: event), as: UTF8.self)
        tracker.consume(line)
        tracker.consume(line)
        tracker.consume(#"{"type":"track_state","data":{"artist":"Missing","title":"Missing","lifecycleState":"Terminal","terminalOutcome":"Failed","failureReason":"NoSearchResults"}}"#)
        XCTAssertEqual(tracker.counts.alreadyBest, 23)
        XCTAssertEqual(tracker.counts.unavailable, 1)
        XCTAssertEqual(tracker.snapshot.completedTracks, 24)
    }

    func testConcurrentFallbackLogIsAttributedToItsOwnTrack() {
        var tracker = SockseekProgressTracker(youtubeFallbackEnabled: true)
        tracker.consume(#"{"type":"search_start","data":{"artist":"Soulseek Artist","title":"Peer Track"}}"#)
        tracker.consume("[011] SongJob: running fallback: Other Artist - Video Track (430s)")
        tracker.consume(#"{"type":"track_state","data":{"artist":"Soulseek Artist","title":"Peer Track","lifecycleState":"Terminal","terminalOutcome":"Failed","failureReason":"AllDownloadsFailed"}}"#)
        tracker.consume(#"{"type":"track_state","data":{"artist":"Other Artist","title":"Video Track","lifecycleState":"Terminal","terminalOutcome":"Failed","failureReason":"AllDownloadsFailed"}}"#)
        XCTAssertEqual(tracker.failures.map(\.source), [.soulseek, .youtubeFallback])
    }

    func testIdentifiesFailureDuringYtDlpFallback() {
        var tracker = SockseekProgressTracker(youtubeFallbackEnabled: true)
        tracker.consume(#"{"type":"track_list","data":{"total":1,"tracks":[{"index":0,"artist":"Artist One","title":"First Song","album":"Album One","lifecycleState":"Pending","terminalOutcome":"None"}]}}"#)
        tracker.consume(#"{"type":"search_start","data":{"artist":"Artist One","title":"First Song","album":"Album One"}}"#)
        tracker.consume(#"{"type":"track_state","data":{"artist":"Artist One","title":"First Song","lifecycleState":"Running","activityPhase":"RunningFallback","terminalOutcome":"None"}}"#)
        tracker.consume(#"{"type":"track_state","data":{"artist":"Artist One","title":"First Song","lifecycleState":"Terminal","activityPhase":"None","terminalOutcome":"Failed","failureReason":"Other","failureMessage":"yt-dlp search failed with exit code 1"}}"#)

        XCTAssertEqual(tracker.failures.count, 1)
        XCTAssertEqual(tracker.failures[0].source, .youtubeFallback)
        XCTAssertEqual(
            tracker.failures[0].reasonDescription,
            "The YouTube/yt-dlp fallback failed: yt-dlp search failed with exit code 1"
        )
    }

    @MainActor
    func testCountsTerminalOutcomesFromV3JSON() {
        let output = """
        human log line
        {"type":"track_state","timestamp":"2026-08-01T07:35:23Z","data":{"lifecycleState":"Terminal","terminalOutcome":"Succeeded","skipReason":"None"}}
        {"type":"track_state","timestamp":"2026-08-01T07:35:24Z","data":{"lifecycleState":"Terminal","terminalOutcome":"Skipped","skipReason":"AlreadyExists"}}
        {"type":"track_state","timestamp":"2026-08-01T07:35:25Z","data":{"lifecycleState":"Terminal","terminalOutcome":"Failed","skipReason":"None"}}
        """
        let counts = AppModel.counts(from: output, fallbackTrackCount: 3)
        XCTAssertEqual(counts.added, 1)
        XCTAssertEqual(counts.alreadyBest, 1)
        XCTAssertEqual(counts.unavailable, 1)
        XCTAssertEqual(counts.needsReview, 0)
    }

    @MainActor
    func testCountsAlreadyIndexedAndPreviouslyMissingTracksFromInitialTrackList() {
        let output = #"{"type":"track_list","data":{"total":2,"pending":0,"existing":1,"notFound":1,"tracks":[{"lifecycleState":"Terminal","terminalOutcome":"Skipped","skipReason":"AlreadyExists"},{"lifecycleState":"Terminal","terminalOutcome":"Skipped","skipReason":"PreviouslyNotFound"}]}}"#

        let counts = AppModel.counts(from: output, fallbackTrackCount: 2)

        XCTAssertEqual(counts.alreadyBest, 1)
        XCTAssertEqual(counts.unavailable, 1)
        XCTAssertEqual(counts.needsReview, 0)
    }
}

final class SyncExecutionKindTests: XCTestCase {
    func testRealPlaylistsRunSockseekAndFixturesRemainPreviewOnly() {
        var realPlaylist = Playlist.samples[0]
        realPlaylist.isFixture = false

        XCTAssertEqual(realPlaylist.executionKind, .sockseek)
        XCTAssertEqual(Playlist.samples[0].executionKind, .previewOnly)
    }
}

@MainActor
final class SyncQueueTests: XCTestCase {
    func testConfirmedSyncsQueueInFIFOOrderAndRejectDuplicates() {
        let model = AppModel()
        let first = Playlist.samples[0]
        let second = Playlist.samples[1]
        let third = Playlist.samples[2]

        model.showSyncPreview(for: first)
        model.confirmPendingSync()
        model.showSyncPreview(for: second)
        model.confirmPendingSync()
        model.showSyncPreview(for: third)
        model.confirmPendingSync()
        model.showSyncPreview(for: second)
        model.confirmPendingSync()

        XCTAssertEqual(model.activeRun?.playlistID, first.id)
        XCTAssertEqual(model.queuedSyncs.map(\.playlist.id), [second.id, third.id])
        XCTAssertEqual(model.queuedSyncCount, 2)
        XCTAssertEqual(model.toastMessage, "\(second.name) is already syncing or queued.")

        model.cancelActiveRun()
    }

    func testCancellingCurrentSyncAutomaticallyStartsNextQueuedPlaylist() async throws {
        let model = AppModel()
        let first = Playlist.samples[0]
        let second = Playlist.samples[1]

        model.showSyncPreview(for: first)
        model.confirmPendingSync()
        model.showSyncPreview(for: second)
        model.confirmPendingSync()
        let confirmedCommand = model.queuedSyncs[0].command.displayString
        model.settings.outputDirectory = "/tmp/changed-after-confirmation"
        model.cancelActiveRun()

        for _ in 0..<50 where model.activeRun?.playlistID != second.id {
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertEqual(model.activeRun?.playlistID, second.id)
        XCTAssertEqual(model.activeRun?.commandPreview, confirmedCommand)
        XCTAssertFalse(confirmedCommand.contains("changed-after-confirmation"))
        XCTAssertTrue(model.queuedSyncs.isEmpty)

        model.cancelActiveRun()
    }

    func testReorderingChangesNextJobWithoutChangingConfirmedCommands() async throws {
        let model = AppModel()
        for playlist in Playlist.samples.prefix(3) {
            model.showSyncPreview(for: playlist)
            model.confirmPendingSync()
        }
        let original = model.queuedSyncs
        XCTAssertEqual(original.count, 2)
        guard original.count == 2 else { return }
        model.moveQueuedSync(original[1].id, by: -1)
        XCTAssertEqual(model.queuedSyncs, [original[1], original[0]])
        model.moveQueuedSync(original[1].id, by: -1)
        XCTAssertEqual(model.queuedSyncs, [original[1], original[0]])
        model.cancelActiveRun()
        for _ in 0..<50 where model.activeRun?.playlistID != original[1].playlist.id {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(model.activeRun?.playlistID, original[1].playlist.id)
        XCTAssertEqual(model.activeRun?.commandPreview, original[1].command.displayString)
        model.removeQueuedSync(original[0].id)
        model.cancelActiveRun()
    }

    func testQueuedSyncCanBeRemoved() {
        let model = AppModel()
        let first = Playlist.samples[0]
        let second = Playlist.samples[1]

        model.showSyncPreview(for: first)
        model.confirmPendingSync()
        model.showSyncPreview(for: second)
        model.confirmPendingSync()
        let queuedID = model.queuedSyncs[0].id

        model.removeQueuedSync(queuedID)

        XCTAssertTrue(model.queuedSyncs.isEmpty)
        XCTAssertEqual(model.toastMessage, "Removed \(second.name) from the sync queue.")

        model.cancelActiveRun()
    }

    func testQueuedSyncFreezesReuseConditionsFromItsConfirmedConfig() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SeekSyncQueuedConditions-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("sockseek.conf")
        try """
        output-dir = /private/tmp/seeksync-queued-conditions
        pref-format = mp3
        pref-max-bitrate = 200

        """.write(to: config, atomically: true, encoding: .utf8)

        let model = AppModel()
        model.setConfigPath(config.path)
        model.settings.libraryReuseEnabled = true
        model.settings.libraryDirectory = root.path
        let first = Playlist.samples[0]
        let second = Playlist.samples[1]
        model.showSyncPreview(for: first)
        model.confirmPendingSync()
        model.showSyncPreview(for: second)
        model.confirmPendingSync()

        let queued = try XCTUnwrap(model.queuedSyncs.first)
        XCTAssertEqual(value(after: "--pref-max-bitrate", in: queued.command), "200")
        XCTAssertEqual(queued.libraryReuseConditionPolicy.arguments, ["--pref-max-bitrate", "200"])

        try """
        output-dir = /private/tmp/seeksync-queued-conditions
        pref-format = mp3
        pref-max-bitrate = 192

        """.write(to: config, atomically: true, encoding: .utf8)
        model.reloadConfig()

        XCTAssertEqual(value(after: "--pref-max-bitrate", in: model.queuedSyncs[0].command), "200")
        XCTAssertEqual(value(after: "--pref-max-bitrate", in: model.command(for: second)), "192")
        model.cancelActiveRun()
    }

    private func value(after flag: String, in command: SLDLCommand) -> String? {
        guard let index = command.arguments.firstIndex(of: flag),
              command.arguments.indices.contains(index + 1) else { return nil }
        return command.arguments[index + 1]
    }
}

final class SpotifyConnectionStateTests: XCTestCase {
    func testCachedRealCatalogIsNotLabeledAsDemoData() {
        XCTAssertEqual(
            SpotifyConnectionState.cached(count: 575).label,
            "Spotify catalog · 575 playlists"
        )
        XCTAssertEqual(SpotifyConnectionState.cached(count: 1).label, "Spotify catalog · 1 playlist")
    }
}

final class ProcessRunnerTests: XCTestCase {
    func testCancellationTerminatesOwnedProcess() async throws {
        let startedAt = Date()
        let task = Task {
            try await SockseekProcessRunner().run(
                SLDLCommand(executable: "/bin/sleep", arguments: ["5"])
            )
        }
        try await Task.sleep(nanoseconds: 150_000_000)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected: cancellation owns and terminates the child process.
        }
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 2)
    }

    @MainActor
    func testInstalledSockseekEmitsParseableTerminalProgressInLocalMockMode() async throws {
        let binary = ConfigStore.detectedBinaryPath()
        guard FileManager.default.isExecutableFile(atPath: binary) else {
            throw XCTSkip("Sockseek is not installed on this machine.")
        }

        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SeekSyncSockseekContract-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outputDirectory) }

        let command = SLDLCommand(
            executable: binary,
            arguments: [
                repository.appendingPathComponent("Fixtures/mock-playlist.csv").path,
                "--config", repository.appendingPathComponent("Fixtures/sockseek.qa.conf").path,
                "--output-dir", outputDirectory.path,
                "--progress-json", "--no-progress",
                "--mock-files-dir", repository.appendingPathComponent("Fixtures/mock-library").path,
                "--mock-files-no-read-tags",
                "--index-path", outputDirectory.appendingPathComponent("index.csv").path,
                "--write-playlist", "true",
                "--yt-dlp", "false"
            ]
        )

        let streamedOutput = OutputChunks()
        let result = try await SockseekProcessRunner().run(command) { chunk in
            await streamedOutput.append(chunk)
        }
        let counts = AppModel.counts(from: result.output, fallbackTrackCount: 1)
        var tracker = SockseekProgressTracker(youtubeFallbackEnabled: false)
        tracker.consume(result.output)
        let streamed = await streamedOutput.joined()

        XCTAssertTrue(result.output.contains(#""type":"track_state""#))
        XCTAssertEqual(streamed, result.output)
        XCTAssertEqual(counts.unavailable, 1)
        XCTAssertEqual(counts.added + counts.alreadyBest + counts.needsReview, 0)
        XCTAssertEqual(tracker.failures.count, 1)
        XCTAssertEqual(tracker.failures[0].artist, "SeekSync QA")
        XCTAssertEqual(tracker.failures[0].title, "Backend Contract")
        XCTAssertEqual(tracker.failures[0].failureReason, "NoSearchResults")
        XCTAssertEqual(tracker.failures[0].source, .soulseek)
        XCTAssertEqual(
            tracker.failures[0].reasonDescription,
            "No Soulseek file results were found. YouTube fallback was disabled for this run."
        )
    }

    @MainActor
    func testInstalledSockseekRepeatRunCountsInitialTrackListAsAlreadyLocal() async throws {
        let binary = ConfigStore.detectedBinaryPath()
        guard FileManager.default.isExecutableFile(atPath: binary) else {
            throw XCTSkip("Sockseek is not installed on this machine.")
        }

        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SeekSyncSockseekRepeat-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outputDirectory) }

        let command = SLDLCommand(
            executable: binary,
            arguments: [
                repository.appendingPathComponent("Fixtures/mock-playlist-success.csv").path,
                "--config", repository.appendingPathComponent("Fixtures/sockseek.qa.conf").path,
                "--output-dir", outputDirectory.path,
                "--progress-json", "--no-progress",
                "--mock-files-dir", repository.appendingPathComponent("Fixtures/mock-library").path,
                "--mock-files-no-read-tags",
                "--index-path", outputDirectory.appendingPathComponent("index.csv").path,
                "--write-playlist", "true",
                "--yt-dlp", "false"
            ]
        )

        let first = try await SockseekProcessRunner().run(command)
        let second = try await SockseekProcessRunner().run(command)
        let firstCounts = AppModel.counts(from: first.output, fallbackTrackCount: 1)
        let secondCounts = AppModel.counts(from: second.output, fallbackTrackCount: 1)

        XCTAssertEqual(first.exitCode, 0)
        XCTAssertEqual(firstCounts.added, 1)
        XCTAssertEqual(second.exitCode, 0)
        XCTAssertEqual(secondCounts.alreadyBest, 1)
        XCTAssertEqual(secondCounts.needsReview + secondCounts.unavailable, 0)
        XCTAssertTrue(second.output.contains(#""skipReason":"AlreadyExists""#))
    }
}

final class PlaylistSyncOutcomeTests: XCTestCase {
    func testPartialSyncInventoryDoesNotShrinkKnownPlaylist() {
        var playlist = Playlist.samples[0]
        playlist.trackCount = 100
        playlist.health = .ready
        let records = (1...20).map { position in
            PlaylistTrackRecord(
                seed: PlaylistTrackSeed(position: position, artist: "Artist", title: "Track \(position)", album: nil, lengthSeconds: 180),
                disposition: .downloaded, localPath: "/music/\(position).flac", quality: nil
            )
        }
        let analysis = PlaylistLibraryAnalysis(
            playlistID: playlist.id, playlistName: playlist.name, analyzedAt: Date(),
            sourceLibraryPath: "/music", preferredFormat: "flac", minimumBitrateKbps: 200,
            tracks: records, basis: .completedSync
        )
        playlist.applyLibraryAnalysis(analysis)
        XCTAssertEqual(playlist.trackCount, 100)
        XCTAssertEqual(playlist.localCount, 20)
        XCTAssertEqual(playlist.missingCount, 80)
        XCTAssertEqual(playlist.health, .partial)
    }

    func testSuccessfulSubsetDoesNotMarkWholePlaylistUpToDate() {
        var playlist = Playlist.samples[0]
        playlist.trackCount = 100
        playlist.applySyncOutcome(phase: .completed, counts: RunCounts(added: 20))
        XCTAssertEqual(playlist.localCount, 20)
        XCTAssertEqual(playlist.health, .partial)
    }

    func testPartialRunUpdatesCoverageFromResolvedAndUnavailableTracks() {
        var playlist = Playlist.samples[0]
        playlist.trackCount = 10
        playlist.localCount = 0

        playlist.applySyncOutcome(
            phase: .partial,
            counts: RunCounts(added: 4, upgraded: 0, alreadyBest: 3, unavailable: 2, needsReview: 1)
        )

        XCTAssertEqual(playlist.localCount, 7)
        XCTAssertEqual(playlist.missingCount, 3)
        XCTAssertEqual(playlist.health, .attention)
        XCTAssertEqual(playlist.needsReview, 1)
    }

    func testFirstRunDiscoversTrackCountForAnImportedURL() {
        var playlist = Playlist.samples[0]
        playlist.trackCount = 0
        playlist.localCount = 0

        playlist.applySyncOutcome(
            phase: .partial,
            counts: RunCounts(added: 2, upgraded: 0, alreadyBest: 1, unavailable: 1, needsReview: 0)
        )

        XCTAssertEqual(playlist.trackCount, 4)
        XCTAssertEqual(playlist.localCount, 3)
        XCTAssertEqual(playlist.missingCount, 1)
    }

    func testCompleteRunMarksAllKnownTracksLocalAndClearsUpgradeCandidates() {
        var playlist = Playlist.samples[0]
        playlist.trackCount = 5
        playlist.localCount = 2
        playlist.upgradeCandidates = 2

        playlist.applySyncOutcome(
            phase: .completed,
            counts: RunCounts(added: 2, upgraded: 1, alreadyBest: 2, unavailable: 0, needsReview: 0)
        )

        XCTAssertEqual(playlist.localCount, 5)
        XCTAssertEqual(playlist.upgradeCandidates, 0)
        XCTAssertEqual(playlist.health, .ready)
    }

    func testSpotifyRefreshPreservesCoverageAndMarksNewTracksMissing() {
        var previous = Playlist.samples[0]
        previous.trackCount = 5
        previous.localCount = 5
        previous.health = .ready
        previous.lastSyncedAt = Date(timeIntervalSince1970: 123)

        var refreshed = previous
        refreshed.trackCount = 7
        refreshed.localCount = 0
        refreshed.health = .neverSynced
        refreshed.lastSyncedAt = nil
        let merged = refreshed.preservingSyncState(from: previous)

        XCTAssertEqual(merged.trackCount, 7)
        XCTAssertEqual(merged.localCount, 5)
        XCTAssertEqual(merged.missingCount, 2)
        XCTAssertEqual(merged.health, .partial)
        XCTAssertEqual(merged.lastSyncedAt, previous.lastSyncedAt)
    }

    func testSpotifyRefreshKeepsKnownTrackCountWhenCatalogTemporarilyReturnsZero() {
        var previous = Playlist.samples[0]
        previous.trackCount = 12
        previous.localCount = 9
        var refreshed = previous
        refreshed.trackCount = 0
        refreshed.localCount = 0

        let merged = refreshed.preservingSyncState(from: previous)

        XCTAssertEqual(merged.trackCount, 12)
        XCTAssertEqual(merged.localCount, 9)
    }
}

final class PlaylistLibraryTests: XCTestCase {
    func testSearchMatchesPlaylistNameOwnerAndDescriptionCaseInsensitively() {
        let playlists = Array(Playlist.samples.prefix(3))

        XCTAssertEqual(PlaylistLibrary.filtered(playlists, searchText: "MIDNIGHT").map(\.id), [playlists[0].id])
        XCTAssertEqual(PlaylistLibrary.filtered(playlists, searchText: "spotify").map(\.id), [playlists[1].id])
        XCTAssertEqual(PlaylistLibrary.filtered(playlists, searchText: "dance-floor").map(\.id), [playlists[2].id])
        XCTAssertEqual(PlaylistLibrary.filtered(playlists, searchText: "   ").count, playlists.count)
    }

    func testLiveCatalogReplacesMatchingURLPlaceholderWithoutDroppingUniqueImports() {
        var placeholder = Playlist.samples[0]
        placeholder.name = "Imported Spotify playlist"
        placeholder.trackCount = 0
        var catalog = placeholder
        catalog.name = "Actual Spotify Name"
        catalog.trackCount = 42
        let uniqueImport = Playlist.samples[1]

        let merged = PlaylistLibrary.merged(imported: [placeholder, uniqueImport], catalog: [catalog])

        XCTAssertEqual(merged.map(\.id), [uniqueImport.id, placeholder.id])
        XCTAssertEqual(merged.last?.name, "Actual Spotify Name")
        XCTAssertEqual(merged.last?.trackCount, 42)
    }

    func testLegacyDuplicateCacheCannotCrashRefreshIndexing() {
        var first = Playlist.samples[0]
        first.localCount = 5
        var duplicate = first
        duplicate.localCount = 0

        let indexed = PlaylistLibrary.indexedByID([first, duplicate])

        XCTAssertEqual(indexed.count, 1)
        XCTAssertEqual(indexed[first.id]?.localCount, 5)
    }

    func testCatalogRefreshAbsorbsMatchingImportedPlaylistAndItsSyncState() {
        var imported = Playlist.samples[0]
        imported.name = "Pasted URL"
        imported.localCount = 3
        imported.trackCount = 4
        imported.health = .partial
        var incoming = imported
        incoming.name = "Spotify Catalog Name"
        incoming.localCount = 0
        incoming.health = .neverSynced

        let refreshed = PlaylistLibrary.refreshed(
            catalog: [incoming],
            previousCatalog: [],
            imported: [imported, Playlist.samples[1]]
        )

        XCTAssertEqual(refreshed.catalog.first?.name, "Spotify Catalog Name")
        XCTAssertEqual(refreshed.catalog.first?.localCount, 3)
        XCTAssertEqual(refreshed.catalog.first?.health, .partial)
        XCTAssertEqual(refreshed.remainingImports.map(\.id), [Playlist.samples[1].id])
    }
}

final class SockseekInstallerTests: XCTestCase {
    func testPinnedReleaseUsesOfficialMacAssetAndPublishedDigest() throws {
        let release = try XCTUnwrap(SockseekRelease.current)
        XCTAssertEqual(release.version, "3.0.4")
        XCTAssertTrue(release.archiveURL.host == "github.com")
        XCTAssertTrue(release.archiveURL.lastPathComponent.contains("osx-arm64"))
        XCTAssertEqual(release.sha256.count, 64)
    }

    func testRejectsDownloadWhenDigestDoesNotMatch() async throws {
        StubURLProtocol.handler = nil
        StubURLProtocol.data = Data("not a release archive".utf8)
        StubURLProtocol.statusCode = 200
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let installer = SockseekInstaller(fileManager: .default, session: session)
        let release = SockseekRelease(
            version: "test",
            archiveURL: URL(string: "https://example.com/sockseek.tar.gz")!,
            sha256: String(repeating: "0", count: 64)
        )

        do {
            _ = try await installer.install(release: release)
            XCTFail("Expected the installer to reject the mismatched digest")
        } catch SockseekInstallError.checksumMismatch {
            // Expected.
        } catch {
            XCTFail("Expected checksumMismatch, got \(error)")
        }
    }
}

final class SpotifyServiceTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        StubURLProtocol.data = Data()
        StubURLProtocol.statusCode = 200
        super.tearDown()
    }

    func testLoadsEveryPageWhenAPlaylistHasNullImages() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)

        StubURLProtocol.handler = { request in
            switch (request.url?.path, request.url?.query) {
            case ("/v1/me", _):
                return (200, Data(#"{"id":"listener","display_name":"Listener"}"#.utf8))
            case ("/v1/me/playlists", "limit=50"):
                return (200, Data(#"{"items":[{"id":"one","name":"One","description":null,"owner":{"id":"listener","display_name":"Listener"},"images":null,"external_urls":{"spotify":"https://open.spotify.com/playlist/one"},"items":{"total":1},"collaborative":false},null],"next":"https://api.spotify.com/v1/me/playlists?limit=50&offset=2"}"#.utf8))
            case ("/v1/me/playlists", "limit=50&offset=2"):
                return (200, Data(#"{"items":[{"id":"one","name":"One duplicate","description":null,"owner":{"id":"listener","display_name":"Listener"},"images":[],"external_urls":{"spotify":"https://open.spotify.com/playlist/one"},"items":{"total":1},"collaborative":false},{"id":"two","name":"Two","description":"Second","owner":{"id":"friend","display_name":null},"images":[{"url":"https://example.com/two.jpg"}],"external_urls":{"spotify":"https://open.spotify.com/playlist/two"},"tracks":{"total":2},"collaborative":false}],"next":null}"#.utf8))
            default:
                XCTFail("Unexpected Spotify request: \(request.url?.absoluteString ?? "nil")")
                return (404, Data())
            }
        }

        var settings = ClientSettings()
        settings.spotifyAccessToken = "access-token"
        let result = try await SpotifyService(session: session).loadPlaylists(settings: settings)

        XCTAssertEqual(result.accountName, "Listener")
        XCTAssertEqual(result.playlists.map(\.id), ["one", "two"])
        XCTAssertNil(result.playlists[0].artworkURL)
        XCTAssertEqual(result.playlists[0].trackCount, 1)
        XCTAssertEqual(result.playlists[1].owner, "friend")
    }

    func testExpiredAccessTokenRefreshesAndRetriesTheWholeCatalog() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        var accountRequestCount = 0
        var observedAuthorizationHeaders: [String] = []

        StubURLProtocol.handler = { request in
            if let authorization = request.value(forHTTPHeaderField: "Authorization") {
                observedAuthorizationHeaders.append(authorization)
            }

            switch (request.url?.host, request.url?.path, request.url?.query) {
            case ("api.spotify.com", "/v1/me", _):
                accountRequestCount += 1
                if accountRequestCount == 1 {
                    return (401, Data(#"{"error":{"status":401,"message":"expired"}}"#.utf8))
                }
                return (200, Data(#"{"id":"listener","display_name":"Listener"}"#.utf8))
            case ("accounts.spotify.com", "/api/token", _):
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
                return (200, Data(#"{"access_token":"fresh-access-token","refresh_token":"rotated-refresh-token"}"#.utf8))
            case ("api.spotify.com", "/v1/me/playlists", "limit=50"):
                return (200, Data(#"{"items":[{"id":"one","name":"One","description":"Ready","owner":{"id":"listener","display_name":"Listener"},"images":[],"external_urls":{"spotify":"https://open.spotify.com/playlist/one"},"items":{"total":1}}],"next":null}"#.utf8))
            default:
                XCTFail("Unexpected Spotify request: \(request.url?.absoluteString ?? "nil")")
                return (404, Data())
            }
        }

        var settings = ClientSettings()
        settings.spotifyAccessToken = "expired-access-token"
        settings.spotifyRefreshToken = "refresh-token"
        settings.spotifyClientID = "client-id"
        settings.spotifyClientSecret = "client-secret"

        let result = try await SpotifyService(session: session).loadPlaylists(settings: settings)

        XCTAssertEqual(accountRequestCount, 2)
        XCTAssertEqual(result.playlists.map(\.id), ["one"])
        XCTAssertEqual(result.refreshedAccessToken, "fresh-access-token")
        XCTAssertEqual(result.refreshedRefreshToken, "rotated-refresh-token")
        XCTAssertTrue(observedAuthorizationHeaders.contains("Bearer expired-access-token"))
        XCTAssertTrue(observedAuthorizationHeaders.contains("Bearer fresh-access-token"))
        XCTAssertTrue(observedAuthorizationHeaders.contains { $0.hasPrefix("Basic ") })
    }

    func testRejectsCyclicPaginationInsteadOfLoopingOrReturningPartialCatalog() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)

        StubURLProtocol.handler = { request in
            switch request.url?.path {
            case "/v1/me":
                return (200, Data(#"{"id":"listener","display_name":"Listener"}"#.utf8))
            case "/v1/me/playlists":
                return (200, Data(#"{"items":[],"next":"https://api.spotify.com/v1/me/playlists?limit=50"}"#.utf8))
            default:
                return (404, Data())
            }
        }

        var settings = ClientSettings()
        settings.spotifyAccessToken = "access-token"

        do {
            _ = try await SpotifyService(session: session).loadPlaylists(settings: settings)
            XCTFail("Expected cyclic Spotify pagination to be rejected.")
        } catch SpotifyServiceError.malformed {
            // Expected: a partial catalog must not be presented as complete.
        }
    }

    func testRejectsPaginationOutsideSpotifyWithoutForwardingBearerToken() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        var requestedHosts: [String] = []

        StubURLProtocol.handler = { request in
            requestedHosts.append(request.url?.host ?? "")
            switch request.url?.path {
            case "/v1/me":
                return (200, Data(#"{"id":"listener","display_name":"Listener"}"#.utf8))
            case "/v1/me/playlists":
                return (200, Data(#"{"items":[],"next":"https://example.com/steal-token"}"#.utf8))
            default:
                return (404, Data())
            }
        }

        var settings = ClientSettings()
        settings.spotifyAccessToken = "private-access-token"

        do {
            _ = try await SpotifyService(session: session).loadPlaylists(settings: settings)
            XCTFail("Expected non-Spotify pagination to be rejected.")
        } catch SpotifyServiceError.malformed {
            XCTAssertFalse(requestedHosts.contains("example.com"))
        }
    }
}

final class SpotifyURLParserTests: XCTestCase {
    func testAcceptsWebURLAndURI() {
        XCTAssertEqual(
            SpotifyURLParser.playlistID(from: "https://open.spotify.com/playlist/37i9dQZF1DX4dyzvuaRJ0n?si=abc"),
            "37i9dQZF1DX4dyzvuaRJ0n"
        )
        XCTAssertEqual(SpotifyURLParser.playlistID(from: "spotify:playlist:abc123"), "abc123")
    }

    func testRejectsNonPlaylistAndWrongHost() {
        XCTAssertNil(SpotifyURLParser.playlistID(from: "https://open.spotify.com/album/abc"))
        XCTAssertNil(SpotifyURLParser.playlistID(from: "https://example.com/playlist/abc"))
    }
}

final class SpotifyCredentialReadinessTests: XCTestCase {
    func testAccessTokenAloneCanLoadLibrary() {
        var settings = ClientSettings()
        settings.spotifyAccessToken = "short-lived-token"
        XCTAssertTrue(settings.canLoadSpotifyLibrary)
    }

    func testRefreshCredentialsCanLoadLibraryWithoutAccessToken() {
        var settings = ClientSettings()
        settings.spotifyClientID = "client"
        settings.spotifyClientSecret = "secret"
        settings.spotifyRefreshToken = "refresh"
        XCTAssertTrue(settings.canLoadSpotifyLibrary)
    }

    func testIncompleteCredentialsDoNotAutoLoad() {
        var settings = ClientSettings()
        settings.spotifyClientID = "client"
        XCTAssertFalse(settings.canLoadSpotifyLibrary)
    }
}

final class SpotifyLiveIntegrationTests: XCTestCase {
    func testLoadsConfiguredSpotifyCatalogWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["SEEKSYNC_LIVE_SPOTIFY_TEST"] == "1" else {
            throw XCTSkip("Set SEEKSYNC_LIVE_SPOTIFY_TEST=1 to run the read-only live Spotify check.")
        }

        let store = ConfigStore()
        let configURL = ConfigStore.detectedConfigURL()
        let loaded = try store.load(from: configURL)
        let result = try await SpotifyService().loadPlaylists(settings: loaded.settings)

        XCTAssertFalse(result.accountName.isEmpty)
        XCTAssertFalse(result.playlists.isEmpty, "Spotify connected but returned no playlists.")
        XCTAssertEqual(Set(result.playlists.map(\.id)).count, result.playlists.count, "Spotify returned duplicate playlist IDs across pages.")
    }
}

final class SeekSyncLiveAcceptanceTests: XCTestCase {
    @MainActor
    func testLoadsRealCatalogAndCompletesOneTrackThroughSockseek() async throws {
        guard ProcessInfo.processInfo.environment["SEEKSYNC_LIVE_ACCEPTANCE_TEST"] == "1" else {
            throw XCTSkip("Set SEEKSYNC_LIVE_ACCEPTANCE_TEST=1 only after authorizing private Spotify access and one bounded download.")
        }

        let configURL = ConfigStore.detectedConfigURL()
        let binaryPath = ConfigStore.detectedBinaryPath()
        var loaded = try ConfigStore().load(from: configURL, binaryPath: binaryPath)
        let catalog = try await SpotifyService().loadPlaylists(settings: loaded.settings)
        let candidates = catalog.playlists
            .filter { $0.trackCount > 0 }
            .sorted { $0.trackCount < $1.trackCount }
        let playlist = try XCTUnwrap(
            candidates.first(where: { $0.owner == catalog.accountName }) ?? candidates.first,
            "The connected Spotify account has no non-empty playlist available for bounded QA."
        )

        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SeekSyncLiveAcceptance-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }

        loaded.settings.outputDirectory = outputDirectory.path
        loaded.settings.allowYouTubeFallback = false
        let command = SockseekCommandBuilder().command(
            for: playlist,
            settings: loaded.settings,
            youtubePolicy: .never,
            maximumTracks: 1
        )
        let result = try await SockseekProcessRunner().run(command)
        let counts = AppModel.counts(from: result.output, fallbackTrackCount: 1)
        let indexPath = SockseekCommandBuilder().indexPath(for: playlist, outputDirectory: outputDirectory.path)
        let audioExtensions = Set(["flac", "mp3", "m4a", "aac", "alac", "wav", "ogg", "opus"])
        let downloadedAudio = (FileManager.default.enumerator(at: outputDirectory, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { audioExtensions.contains($0.pathExtension.lowercased()) }) ?? []

        XCTAssertEqual(result.exitCode, 0, "Sockseek did not complete the bounded live sync.\n\(result.output)")
        XCTAssertEqual(counts.added + counts.alreadyBest + counts.upgraded, 1)
        XCTAssertEqual(counts.unavailable + counts.needsReview, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: indexPath), "Sockseek did not write the stable playlist index.")
        XCTAssertEqual(downloadedAudio.count, 1, "Expected one downloaded audio file in the isolated QA folder.")
    }
}

// MARK: - Rekordbox XML export

private func indexEntry(
    path: String?,
    artist: String = "Artist",
    album: String = "Album",
    title: String = "Title",
    lengthSeconds: Int = 200,
    state: Int = 1
) -> SockseekIndexEntry {
    SockseekIndexEntry(
        path: path,
        artist: artist,
        album: album,
        title: title,
        lengthSeconds: lengthSeconds,
        state: state,
        failureReason: 0
    )
}

final class RekordboxCollectionBuilderTests: XCTestCase {
    func testSharedFileAcrossPlaylistsBecomesOneTrackReferencedTwice() {
        let shared = indexEntry(path: "/Music/downloads/shared.flac", title: "Shared")
        let collection = RekordboxCollectionBuilder().build(from: [
            .init(name: "Warm Up", entries: [shared]),
            .init(name: "Peak Time", entries: [shared, indexEntry(path: "/Music/downloads/other.flac", title: "Other")])
        ])

        XCTAssertEqual(collection.tracks.count, 2)
        XCTAssertEqual(collection.nodes.map(\.name), ["Warm Up", "Peak Time"])
        let sharedID = try? XCTUnwrap(collection.tracks.first { $0.title == "Shared" }?.id)
        XCTAssertEqual(collection.nodes[0].trackIDs, [sharedID])
        XCTAssertEqual(collection.nodes[1].trackIDs.first, sharedID)
        XCTAssertEqual(collection.nodes[1].trackIDs.count, 2)
    }

    func testExcludesEntriesWithoutAPathOrWithoutAnAvailableState() {
        let collection = RekordboxCollectionBuilder().build(from: [
            .init(name: "Mixed", entries: [
                indexEntry(path: "/Music/downloads/downloaded.flac", title: "Downloaded", state: 1),
                indexEntry(path: "/Music/library/existing.flac", title: "Existing", state: 3),
                indexEntry(path: nil, title: "No Path", state: 1),
                indexEntry(path: "/Music/downloads/failed.flac", title: "Failed", state: 2)
            ])
        ])

        XCTAssertEqual(collection.tracks.map(\.title).sorted(), ["Downloaded", "Existing"])
        XCTAssertEqual(collection.nodes[0].trackIDs.count, 2)
    }

    func testPreservesIndexOrderWithinAPlaylistAndDropsEmptyPlaylists() {
        let collection = RekordboxCollectionBuilder().build(from: [
            .init(name: "Ordered", entries: [
                indexEntry(path: "/a.flac", title: "First"),
                indexEntry(path: "/b.flac", title: "Second"),
                indexEntry(path: "/c.flac", title: "Third")
            ]),
            .init(name: "Empty", entries: [indexEntry(path: nil, title: "Nope")])
        ])

        let titlesInOrder = collection.nodes[0].trackIDs.compactMap { id in
            collection.tracks.first { $0.id == id }?.title
        }
        XCTAssertEqual(titlesInOrder, ["First", "Second", "Third"])
        XCTAssertEqual(collection.nodes.map(\.name), ["Ordered"])
    }

    func testDerivesRekordboxKindFromTheFileExtension() {
        let collection = RekordboxCollectionBuilder().build(from: [
            .init(name: "Kinds", entries: [
                indexEntry(path: "/a.flac", title: "Flac"),
                indexEntry(path: "/b.MP3", title: "Mp3"),
                indexEntry(path: "/c.weird", title: "Weird")
            ])
        ])

        func kind(_ title: String) -> String? { collection.tracks.first { $0.title == title }?.kind }
        XCTAssertEqual(kind("Flac"), "FLAC File")
        XCTAssertEqual(kind("Mp3"), "MP3 File")
        XCTAssertEqual(kind("Weird"), "WEIRD File")
    }
}

final class RekordboxXMLWriterTests: XCTestCase {
    private func collection(
        tracks: [RekordboxTrack],
        nodes: [RekordboxPlaylistNode]
    ) -> RekordboxCollection {
        RekordboxCollection(tracks: tracks, nodes: nodes)
    }

    func testEscapesReservedCharactersInTrackMetadata() throws {
        let xml = RekordboxXMLWriter().xml(for: collection(
            tracks: [
                RekordboxTrack(
                    id: 1,
                    path: "/Music/one.flac",
                    title: "Rock & <Roll>",
                    artist: "The \"Quotes\"",
                    album: "A & B",
                    lengthSeconds: 200,
                    kind: "FLAC File"
                )
            ],
            nodes: [RekordboxPlaylistNode(name: "Set & Setting", trackIDs: [1])]
        ))

        XCTAssertFalse(xml.contains("Rock & <Roll>"))
        XCTAssertTrue(xml.contains("Rock &amp; &lt;Roll&gt;"))
        XCTAssertTrue(xml.contains("The &quot;Quotes&quot;"))
        let document = try XMLDocument(xmlString: xml, options: [])
        let names = try document.nodes(forXPath: "//TRACK/@Name").compactMap(\.stringValue)
        XCTAssertEqual(names, ["Rock & <Roll>"])
        let playlists = try document.nodes(forXPath: "//NODE[@Type='1']/@Name").compactMap(\.stringValue)
        XCTAssertEqual(playlists, ["Set & Setting"])
    }

    func testEncodesPathsWithSpacesAndNonASCIICharactersAsFileURIs() throws {
        let xml = RekordboxXMLWriter().xml(for: collection(
            tracks: [
                RekordboxTrack(
                    id: 1,
                    path: "/Music/Été Sessions/track one.flac",
                    title: "One",
                    artist: "A",
                    album: "B",
                    lengthSeconds: 100,
                    kind: "FLAC File"
                )
            ],
            nodes: [RekordboxPlaylistNode(name: "Set", trackIDs: [1])]
        ))

        let document = try XMLDocument(xmlString: xml, options: [])
        let location = try XCTUnwrap(document.nodes(forXPath: "//TRACK/@Location").first?.stringValue)
        XCTAssertTrue(location.hasPrefix("file://localhost/"), location)
        XCTAssertFalse(location.contains(" "), location)
        XCTAssertTrue(location.contains("%20"), location)
        XCTAssertEqual(URL(string: location)?.path, "/Music/Été Sessions/track one.flac")
    }

    func testWritesACollectionAndPlaylistTreeRekordboxCanRead() throws {
        let xml = RekordboxXMLWriter().xml(for: collection(
            tracks: [
                RekordboxTrack(id: 1, path: "/a.flac", title: "One", artist: "A", album: "B", lengthSeconds: 100, kind: "FLAC File"),
                RekordboxTrack(id: 2, path: "/b.flac", title: "Two", artist: "A", album: "B", lengthSeconds: -1, kind: "FLAC File")
            ],
            nodes: [
                RekordboxPlaylistNode(name: "Warm Up", trackIDs: [1]),
                RekordboxPlaylistNode(name: "Peak", trackIDs: [1, 2])
            ]
        ))

        let document = try XMLDocument(xmlString: xml, options: [])
        XCTAssertEqual(document.rootElement()?.name, "DJ_PLAYLISTS")
        XCTAssertEqual(document.rootElement()?.attribute(forName: "Version")?.stringValue, "1.0.0")
        XCTAssertEqual(try document.nodes(forXPath: "//COLLECTION/@Entries").first?.stringValue, "2")
        XCTAssertEqual(try document.nodes(forXPath: "//COLLECTION/TRACK").count, 2)
        let rootFolder = "/DJ_PLAYLISTS/PLAYLISTS/NODE[@Type='0'][@Name='ROOT']"
        XCTAssertEqual(try document.nodes(forXPath: rootFolder).count, 1)
        XCTAssertEqual(
            try document.nodes(forXPath: "\(rootFolder)/NODE[@Type='0']/@Name").compactMap(\.stringValue),
            ["SeekSync"]
        )
        let playlists = try document.nodes(forXPath: "\(rootFolder)/NODE/NODE[@Type='1']/@Name").compactMap(\.stringValue)
        XCTAssertEqual(playlists, ["Warm Up", "Peak"])
        XCTAssertEqual(try document.nodes(forXPath: "//NODE[@Name='Peak']/TRACK/@Key").compactMap(\.stringValue), ["1", "2"])
        XCTAssertEqual(try document.nodes(forXPath: "//NODE[@Name='Peak']/@Entries").first?.stringValue, "2")
        // An unknown length must be omitted rather than written as a negative time.
        XCTAssertEqual(try document.nodes(forXPath: "//TRACK[@Name='Two']/@TotalTime").count, 0)
        XCTAssertEqual(try document.nodes(forXPath: "//TRACK[@Name='One']/@TotalTime").first?.stringValue, "100")
    }
}

final class RekordboxXMLExporterTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("SeekSyncRekordbox-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func writeIndex(named name: String, rows: [(path: String, title: String, state: Int)]) throws -> String {
        let url = directory.appendingPathComponent(name)
        var lines = ["filepath,artist,album,title,length,tracktype,state,failurereason"]
        lines += rows.map { "\($0.path),Artist,Album,\($0.title),200,0,\($0.state),0" }
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    func testSkipsPlaylistsWhoseIndexIsMissingAndExportsTheRest() throws {
        let present = try writeIndex(named: "present.csv", rows: [
            (path: "/Music/downloads/one.flac", title: "One", state: 1)
        ])
        let output = directory.appendingPathComponent("SeekSync.rekordbox.xml")

        let written = try RekordboxXMLExporter().export(
            sources: [
                .init(name: "Present", indexPath: present),
                .init(name: "Missing", indexPath: directory.appendingPathComponent("nope.csv").path)
            ],
            to: output
        )

        XCTAssertEqual(written, 1)
        let document = try XMLDocument(contentsOf: output, options: [])
        XCTAssertEqual(try document.nodes(forXPath: "//NODE[@Type='1']/@Name").compactMap(\.stringValue), ["Present"])
        XCTAssertEqual(try document.nodes(forXPath: "//COLLECTION/TRACK").count, 1)
    }

    func testLeavesAnExistingExportUntouchedWhenThereIsNothingToWrite() throws {
        let output = directory.appendingPathComponent("SeekSync.rekordbox.xml")
        try "<!-- previous good export -->".write(to: output, atomically: true, encoding: .utf8)
        let empty = try writeIndex(named: "empty.csv", rows: [
            (path: "", title: "Unavailable", state: 2)
        ])

        let written = try RekordboxXMLExporter().export(
            sources: [.init(name: "Empty", indexPath: empty)],
            to: output
        )

        XCTAssertEqual(written, 0)
        XCTAssertEqual(try String(contentsOf: output), "<!-- previous good export -->")
    }

    func testResolvesTheExportURLBesideTheDownloadsFolder() {
        let url = RekordboxXMLExporter.exportURL(outputDirectory: "~/Music/downloads/")
        XCTAssertEqual(url.lastPathComponent, "SeekSync.rekordbox.xml")
        XCTAssertFalse(url.path.contains("~"), url.path)
        XCTAssertTrue(url.deletingLastPathComponent().path.hasSuffix("/Music/downloads"), url.path)
    }
}

final class RekordboxSettingsTests: XCTestCase {
    func testExportIsEnabledUntilTheUserTurnsItOff() {
        var settings = ClientSettings()
        XCTAssertNil(settings.rekordboxXMLEnabled)
        XCTAssertTrue(settings.isRekordboxXMLEnabled)

        settings.rekordboxXMLEnabled = false
        XCTAssertFalse(settings.isRekordboxXMLEnabled)
    }

    func testExportPreferenceIsNeverWrittenIntoTheSockseekConfig() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SeekSyncRekordboxConf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configURL = directory.appendingPathComponent("sockseek.conf")
        try "username = tester\npath = ~/Music/downloads\n".write(to: configURL, atomically: true, encoding: .utf8)

        let store = ConfigStore()
        var loaded = try store.load(from: configURL, binaryPath: "/tmp/sockseek")
        XCTAssertNil(loaded.settings.rekordboxXMLEnabled, "Sockseek's config must not be the source of an app-local preference.")

        loaded.settings.rekordboxXMLEnabled = false
        _ = try store.save(
            settings: loaded.settings,
            document: loaded.document,
            to: configURL,
            expectedRevision: loaded.revision
        )

        let saved = try String(contentsOf: configURL)
        XCTAssertFalse(saved.lowercased().contains("rekordbox"), saved)
    }
}

final class RekordboxWiringTests: XCTestCase {
    func testPreservesAppLocalPreferencesAcrossAConfigReload() {
        var fromDisk = ClientSettings()
        fromDisk.outputDirectory = "~/Music/from-config"
        var appLocal = ClientSettings()
        appLocal.rekordboxXMLEnabled = false
        appLocal.libraryReuseEnabled = true
        appLocal.libraryDirectory = "~/Music/library"
        appLocal.dailyHour = 5
        appLocal.dailyMinute = 30
        appLocal.liveSchedulingArmed = true

        let merged = fromDisk.mergingPrototypePreferences(from: appLocal)

        XCTAssertEqual(merged.outputDirectory, "~/Music/from-config")
        XCTAssertEqual(merged.rekordboxXMLEnabled, false)
        XCTAssertEqual(merged.libraryReuseEnabled, true)
        XCTAssertEqual(merged.libraryDirectory, "~/Music/library")
        XCTAssertEqual(merged.dailyHour, 5)
        XCTAssertEqual(merged.dailyMinute, 30)
        XCTAssertEqual(merged.liveSchedulingArmed, true)
    }

    func testBuildsExporterSourcesFromPlaylistsThatCanHaveAnIndex() {
        var synced = Playlist.samples[0]
        synced.isFixture = false
        var fixture = Playlist.samples[1]
        fixture.isFixture = true

        let sources = RekordboxXMLExporter.sources(
            for: [synced, fixture],
            outputDirectory: "~/Music/downloads"
        )

        XCTAssertEqual(sources.map(\.name), [synced.name])
        let expected = SockseekCommandBuilder().indexPath(for: synced, outputDirectory: "~/Music/downloads")
        XCTAssertEqual(sources.first?.indexPath, expected)
    }
}

@MainActor
final class GlobalLibraryReindexTests: XCTestCase {
    private func makeModel(root: URL, delay: Bool) throws -> AppModel {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let binary = root.appendingPathComponent("sockseek")
        try ("#!/bin/sh\nif [ \"$1\" = \"--version\" ]; then echo 3.0.5; exit 0; fi\n" + (delay ? "sleep 2\n" : "") + "echo 'Test metadata unavailable'\nexit 1\n")
            .write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
        let model = AppModel()
        model.liveSpotifyPlaylists = []
        model.spotifyCatalogLoaded = true
        model.importedPlaylists = Array(Playlist.samples.prefix(2)).map {
            var playlist = $0
            playlist.isFixture = false
            return playlist
        }
        model.settings.libraryReuseEnabled = true
        model.settings.libraryDirectory = root.path
        model.settings.binaryPath = binary.path
        model.dependencyState = .ready(version: "3.0.5")
        return model
    }

    func testGlobalReindexContinuesAfterFailuresWithoutQueueingDownloads() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = try makeModel(root: root, delay: false)
        XCTAssertEqual(model.libraryReindexPlaylists.count, 2)
        model.reindexLibrary()
        model.reindexLibrary() // A second click must not launch another batch.
        for _ in 0..<250 where model.isReindexingLibrary {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertFalse(model.isReindexingLibrary)
        XCTAssertEqual(model.libraryReindexCompleted, 2)
        XCTAssertEqual(model.libraryReindexMessage, "Reindex finished: 0 refreshed, 2 failed.")
        XCTAssertEqual(model.libraryAnalysisMessages.count, 2)
        XCTAssertTrue(model.queuedSyncs.isEmpty)
        XCTAssertNil(model.activeRun)
    }

    func testFailedPlaylistReadBlocksConfirmationAndSuccessfulReadClearsIt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = try makeModel(root: root, delay: false)
        let playlist = try XCTUnwrap(model.libraryReindexPlaylists.first)
        model.analyzeLibraryReuse(for: playlist)
        for _ in 0..<250 where model.isAnalyzingLibrary(for: playlist.id) {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertNotNil(model.playlistReadBlocker(for: playlist))
        model.showSyncPreview(for: playlist)
        model.confirmPendingSync()
        XCTAssertNotNil(model.pendingSync)
        XCTAssertNil(model.activeRun)
        XCTAssertTrue(model.queuedSyncs.isEmpty)

        // Restore metadata access. The fake backend still cannot scan local
        // files, but that must not leave a stale playlist-access blocker.
        let binary = URL(fileURLWithPath: model.settings.binaryPath)
        try """
        #!/bin/sh
        if [ "$1" = "--version" ]; then echo 3.0.5; exit 0; fi
        printf '1 jobs:\n  Song:\n    Artist: Test Artist\n    Title: Test Track\n'
        exit 0
        """.write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
        model.analyzeLibraryReuse(for: playlist)
        for _ in 0..<250 where model.isAnalyzingLibrary(for: playlist.id) {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertNil(model.playlistReadBlocker(for: playlist))
        XCTAssertNil(model.activeRun)
    }

    func testCancellationStopsBeforeTheNextPlaylist() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = try makeModel(root: root, delay: true)
        model.reindexLibrary()
        for _ in 0..<50 where model.libraryAnalysisPlaylistIDs.isEmpty {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        model.cancelLibraryReindex()
        for _ in 0..<250 where model.isReindexingLibrary {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertFalse(model.isReindexingLibrary)
        XCTAssertEqual(model.libraryReindexCompleted, 0)
        XCTAssertTrue(model.libraryAnalysisPlaylistIDs.isEmpty)
        XCTAssertTrue(model.libraryReindexMessage?.contains("cancelled") == true)
        XCTAssertLessThanOrEqual(model.libraryAnalysisMessages.count, 1)
        XCTAssertTrue(model.queuedSyncs.isEmpty)
    }
}

final class PlaylistAccessErrorTests: XCTestCase {
    func testSpotify404ExplainsAccessAndRecoveryWithoutClaimingDeletion() {
        let error = LibraryReuseAnalysisError.playlistExtractionFailed(
            "ExtractJob: Spotify playlist request after user authorization failed: HTTP 404 NotFound"
        )
        let message = error.localizedDescription
        XCTAssertTrue(message.contains("Spotify could not provide this playlist"))
        XCTAssertTrue(message.contains("playlist you own"))
        XCTAssertTrue(message.contains("404"))
        XCTAssertFalse(message.contains("was deleted"))
    }

    func testNonSpotify404DoesNotSuggestSpotifyRecovery() {
        let error = LibraryReuseAnalysisError.playlistExtractionFailed("Other provider: HTTP 404 NotFound")
        XCTAssertFalse(error.localizedDescription.contains("playlist you own"))
    }
}
