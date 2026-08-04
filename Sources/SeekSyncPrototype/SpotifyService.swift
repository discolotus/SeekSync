import Foundation

enum SpotifyServiceError: LocalizedError {
    case missingCredentials
    case unauthorized
    case response(Int)
    case malformed

    var errorDescription: String? {
        switch self {
        case .missingCredentials: return "Spotify credentials or tokens are missing. Paste a playlist URL or reconnect with Sockseek."
        case .unauthorized: return "Spotify authorization expired. Reconnect with Sockseek, then reload the config."
        case .response(403): return "Spotify denied this request. Reconnect the account and confirm playlist access is granted."
        case .response(429): return "Spotify is temporarily rate-limiting playlist requests. Wait a moment, then try again."
        case .response(let status): return "Spotify returned HTTP \(status). Try reloading the library; reconnect if the problem continues."
        case .malformed: return "Spotify returned an unexpected response."
        }
    }
}

struct SpotifyLoadResult {
    let playlists: [Playlist]
    let accountName: String
    let refreshedAccessToken: String?
    let refreshedRefreshToken: String?
}

struct SpotifyService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func loadPlaylists(settings: ClientSettings) async throws -> SpotifyLoadResult {
        var token = settings.spotifyAccessToken
        var refreshedToken: String?
        var refreshedRefreshToken: String?
        if token.isEmpty {
            let refreshed = try await refreshAccessToken(settings: settings)
            token = refreshed.accessToken
            refreshedToken = token
            refreshedRefreshToken = refreshed.refreshToken
        }

        do {
            return try await fetchAllPlaylists(accessToken: token, refreshedToken: refreshedToken, refreshedRefreshToken: refreshedRefreshToken)
        } catch SpotifyServiceError.unauthorized where !settings.spotifyRefreshToken.isEmpty {
            let refreshed = try await refreshAccessToken(settings: settings)
            token = refreshed.accessToken
            return try await fetchAllPlaylists(accessToken: token, refreshedToken: token, refreshedRefreshToken: refreshed.refreshToken)
        }
    }

    private func refreshAccessToken(settings: ClientSettings) async throws -> TokenResponse {
        guard !settings.spotifyClientID.isEmpty,
              !settings.spotifyClientSecret.isEmpty,
              !settings.spotifyRefreshToken.isEmpty else {
            throw SpotifyServiceError.missingCredentials
        }

        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let credentials = Data("\(settings.spotifyClientID):\(settings.spotifyClientSecret)".utf8).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: settings.spotifyRefreshToken)
        ]
        request.httpBody = Data((form.percentEncodedQuery ?? "").utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SpotifyServiceError.malformed }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 400 || http.statusCode == 401 { throw SpotifyServiceError.unauthorized }
            throw SpotifyServiceError.response(http.statusCode)
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private func fetchAllPlaylists(accessToken: String, refreshedToken: String?, refreshedRefreshToken: String?) async throws -> SpotifyLoadResult {
        let account = try await fetchAccount(accessToken: accessToken)
        var url: URL? = URL(string: "https://api.spotify.com/v1/me/playlists?limit=50")
        var playlists: [Playlist] = []
        var seenPlaylistIDs = Set<String>()
        var visitedPages = Set<URL>()

        while let pageURL = url {
            guard visitedPages.insert(pageURL).inserted else { throw SpotifyServiceError.malformed }
            let page: PlaylistPage = try await authorizedRequest(pageURL, accessToken: accessToken)
            let availableItems = (page.items ?? []).compactMap { $0 }.filter { seenPlaylistIDs.insert($0.id).inserted }
            playlists.append(contentsOf: availableItems.enumerated().map { index, item in
                Playlist(
                    id: item.id,
                    name: item.name,
                    owner: item.owner.displayName ?? item.owner.id,
                    detail: item.description?.strippingHTML ?? "Spotify playlist",
                    spotifyURL: item.externalURLs?.spotify ?? "https://open.spotify.com/playlist/\(item.id)",
                    artworkURL: item.images?.first.flatMap { URL(string: $0.url) },
                    artworkHue: Double((playlists.count + index) % 12) / 12,
                    trackCount: item.items?.total ?? item.tracks?.total ?? 0,
                    localCount: 0,
                    upgradeCandidates: 0,
                    needsReview: 0,
                    lastSyncedAt: nil,
                    health: .neverSynced,
                    isFixture: false
                )
            })
            if let next = page.next {
                guard let nextURL = URL(string: next),
                      nextURL.scheme == "https",
                      nextURL.host?.lowercased() == "api.spotify.com" else {
                    throw SpotifyServiceError.malformed
                }
                url = nextURL
            } else {
                url = nil
            }
        }
        return SpotifyLoadResult(
            playlists: playlists,
            accountName: account.displayName ?? account.id,
            refreshedAccessToken: refreshedToken,
            refreshedRefreshToken: refreshedRefreshToken
        )
    }

    private func fetchAccount(accessToken: String) async throws -> AccountResponse {
        try await authorizedRequest(URL(string: "https://api.spotify.com/v1/me")!, accessToken: accessToken)
    }

    private func authorizedRequest<T: Decodable>(_ url: URL, accessToken: String) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SpotifyServiceError.malformed }
        if http.statusCode == 401 { throw SpotifyServiceError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw SpotifyServiceError.response(http.statusCode) }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

private struct AccountResponse: Decodable {
    let id: String
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }
}

private struct PlaylistPage: Decodable {
    let items: [SpotifyPlaylist?]?
    let next: String?
}

private struct SpotifyPlaylist: Decodable {
    let id: String
    let name: String
    let description: String?
    let owner: SpotifyOwner
    let images: [SpotifyImage]?
    let externalURLs: SpotifyExternalURLs?
    let tracks: SpotifyTotal?
    let items: SpotifyTotal?

    enum CodingKeys: String, CodingKey {
        case id, name, description, owner, images, tracks, items
        case externalURLs = "external_urls"
    }
}

private struct SpotifyOwner: Decodable {
    let id: String
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }
}

private struct SpotifyImage: Decodable { let url: String }
private struct SpotifyExternalURLs: Decodable { let spotify: String? }
private struct SpotifyTotal: Decodable { let total: Int }

private extension String {
    var strippingHTML: String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}
