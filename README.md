# SeekSync

SeekSync is a native SwiftUI application for browsing Spotify playlists and driving Sockseek 3 sync jobs on macOS. The installed `sldl` command is supported when it resolves to Sockseek 3; legacy SLDL 2 is intentionally not used.

On first launch, SeekSync uses an existing Sockseek 3 installation when available. If none is found, it downloads the pinned official macOS release (currently 3.0.4), verifies GitHub's published SHA-256 digest, and installs the executable under `~/Library/Application Support/SeekSyncPrototype/Tools/`. Sockseek remains a separate process and is licensed under AGPL-3.0; its license and corresponding source are available from [fiso64/sockseek](https://github.com/fiso64/sockseek/tree/v3.0.4).

## Run it

```sh
make run
```

Build a double-clickable ad-hoc-signed app:

```sh
make app
open "dist/SeekSync.app"
```

Build the versioned ZIP, checksum, and Homebrew cask used by CI:

```sh
make release
```

Run QA:

```sh
make test
```

The real-account acceptance test is deliberately disabled by default. After explicit authorization, `SEEKSYNC_LIVE_ACCEPTANCE_TEST=1 make test` loads the configured Spotify catalog, limits Sockseek to one track, disables YouTube fallback, writes into an isolated temporary folder, and requires a successful audio file plus index.

For Xcode, open `Package.swift`, select the **SeekSyncPrototype** scheme, and use **Product → Test**. Use `make app` for the double-clickable macOS bundle.

## What works

- One responsive Library + Inspector interface for browsing and syncing playlists.
- Demo playlist library plus Spotify playlist-URL import.
- Automatic read-only Spotify Web API loading from credentials already present in the selected Sockseek config, plus a manual refresh action.
- One-shot sync preview and an in-memory/persisted daily sync pool.
- Exact argument-array command construction for Sockseek, including a stable per-playlist index, streamed JSON progress, preferred-quality rechecks, and explicit YouTube fallback override.
- Optional reuse of qualifying tracks from an existing music library via
  Sockseek's tag matcher. Reused files stay in place and generated M3U
  playlists reference their original paths.
- A read-only preflight compares preferred-condition-gated and ungated local
  matches against an empty mock backend. It also carries forward the stable
  playlist index, so it can distinguish references, prior downloads,
  below-target files, and downloads needed without connecting to Soulseek or
  changing music files.
- Real Spotify and pasted-URL playlists start Sockseek only after an explicit sync preview confirmation. Built-in demo playlists remain preview-only, and unattended live scheduling has a second, explicit arm control.
- Real Sockseek config reading and comment/order-preserving updates after an explicit save, with backup and external-change detection.
- Activity history, dependency health, settings, and a menu-bar status surface.
- Live per-track progress from Sockseek, including the current song, playlist
  position, search/download phase, byte progress, completed tracks, failures,
  and already-local tracks.
- Live progress and result counts update the selected playlist's local-coverage state rather than leaving catalog playlists at zero after a run.
- Spotify refreshes retain prior sync coverage, reconcile pasted URLs with catalog metadata, and reject partial or unsafe pagination chains.

## Important prototype boundaries

- The daily scheduler runs while SeekSync is open (closing the window is fine because the menu-bar item remains; quitting stops it). Live scheduling remains disarmed until explicitly confirmed. A production version needs a launch agent or helper.
- “Look for preferred quality” maps to Sockseek's `--skip-check-pref-cond`. It re-searches when the indexed local file misses configured preferred conditions; it is not acoustic-quality analysis or a guarantee of a better mastering.
- Existing-library reuse forces preferred-condition checking and M3U output for
  that run. The preview safely mirrors supported matching conditions from the
  active profile, and the completed run's real index replaces the forecast.
  Per-playlist track inventories retain source paths and technical quality
  metadata when the local files expose them.
- Spotify browsing depends on Spotify developer credentials/token policy. Paste-a-playlist remains available when API access fails.
- Spotify browsing loads every playlist page for the connected account. Sync execution passes the selected playlist URL to Sockseek, which owns track extraction and download behavior.
- Spotify's current Developer Policy creates a distribution risk for products that combine Spotify API metadata with download workflows. This is a local personal-use prototype; review the policy before distributing it.
- Secrets remain masked in the UI and are never added to command previews or activity logs. A production build should move app-owned credentials to Keychain.
- The prototype writes only its own Application Support state unless **Save config** or a confirmed live sync is chosen.

See [PROTOTYPE_NOTES.md](PROTOTYPE_NOTES.md) for remaining production boundaries.

## Releases

`VERSION` is the canonical version. Every pull request to `main` must increase
it and add matching release notes to `CHANGELOG.md`. The required metadata check
is imported from `discolotus/release-workflows`.

After merge, CI tests and packages the application, creates the corresponding
tag as an implementation detail, and publishes the ZIP, SHA-256 checksum, and
generated cask as a GitHub prerelease. The central Homebrew tap imports that
cask automatically on its next scheduled update.
