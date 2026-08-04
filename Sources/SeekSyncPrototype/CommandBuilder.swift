import Foundation

struct SockseekCommandBuilder {
    func command(
        for playlist: Playlist,
        settings: ClientSettings,
        youtubePolicy: YouTubePolicy = .inherit,
        maximumTracks: Int? = nil
    ) -> SLDLCommand {
        var arguments = [playlist.spotifyURL]
        if let maximumTracks, maximumTracks > 0 {
            arguments += ["--number", String(maximumTracks)]
        }
        arguments += ["--config", settings.configPath]
        if !settings.profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments += ["--profile", settings.profileName]
        }
        arguments += ["--output-dir", settings.outputDirectory]
        arguments += ["--pref-format", settings.preferredFormatValue]
        arguments += ["--index-path", indexPath(for: playlist, outputDirectory: settings.outputDirectory)]
        arguments += ["--progress-json", "--no-progress"]
        arguments += ["--write-playlist", settings.writeM3UPlaylist ? "true" : "false"]
        arguments += ["--skip-check-pref-cond", settings.lookForPreferredQuality ? "true" : "false"]

        let allowYouTube: Bool
        switch youtubePolicy {
        case .inherit: allowYouTube = settings.allowYouTubeFallback
        case .allow: allowYouTube = true
        case .never: allowYouTube = false
        }
        arguments += ["--yt-dlp", allowYouTube ? "true" : "false"]

        return SLDLCommand(
            executable: NSString(string: settings.binaryPath).expandingTildeInPath,
            arguments: arguments
        )
    }

    func indexPath(for playlist: Playlist, outputDirectory: String) -> String {
        let slug = playlist.id
            .lowercased()
            .map { character -> Character in
                if character.isLetter || character.isNumber || character == "-" || character == "_" {
                    return character
                }
                return "-"
            }
        let base = outputDirectory.hasSuffix("/") ? String(outputDirectory.dropLast()) : outputDirectory
        return base + "/.seeksync-index-\(String(slug)).csv"
    }
}

enum SpotifyURLParser {
    static func playlistID(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("spotify:playlist:") {
            let id = String(trimmed.dropFirst("spotify:playlist:".count))
            return isValid(id) ? id : nil
        }
        guard let components = URLComponents(string: trimmed),
              components.host?.lowercased() == "open.spotify.com" else { return nil }
        let pieces = components.path.split(separator: "/").map(String.init)
        guard pieces.count >= 2, pieces[0] == "playlist", isValid(pieces[1]) else { return nil }
        return pieces[1]
    }

    static func canonicalURL(from input: String) -> String? {
        guard let id = playlistID(from: input) else { return nil }
        return "https://open.spotify.com/playlist/\(id)"
    }

    private static func isValid(_ id: String) -> Bool {
        !id.isEmpty && id.allSatisfy { $0.isLetter || $0.isNumber }
    }
}
