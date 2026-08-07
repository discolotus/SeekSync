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

        let analysis = try await LibraryReuseAnalyzer().analyze(playlist: playlist, settings: settings)

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

        let advancedConditions = LibraryReuseConditionPolicy(
            arguments: ["--pref-max-bitrate", "200"]
        )
        let stricterAnalysis = try await LibraryReuseAnalyzer().analyze(
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
            _ = try await LibraryReuseAnalyzer().analyze(
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
