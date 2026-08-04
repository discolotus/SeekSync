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
    }

    func testStandardAndWideLayoutsUseExpandedPresentation() {
        XCTAssertEqual(SeekSyncLayoutMode(width: 1_050), .standard)
        XCTAssertEqual(SeekSyncLayoutMode(width: 1_280), .wide)
        XCTAssertTrue(SeekSyncLayoutMode(width: 1_280).defaultsToOpenInspector)
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
}

final class SockseekProgressParserTests: XCTestCase {
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
        let streamed = await streamedOutput.joined()

        XCTAssertTrue(result.output.contains(#""type":"track_state""#))
        XCTAssertEqual(streamed, result.output)
        XCTAssertEqual(counts.unavailable, 1)
        XCTAssertEqual(counts.added + counts.alreadyBest + counts.needsReview, 0)
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
