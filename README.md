# SeekSync

SeekSync is a native SwiftUI application for browsing Spotify playlists and driving Sockseek 3 sync jobs on macOS. The installed `sldl` command is supported when it resolves to Sockseek 3; legacy SLDL 2 is intentionally not used.

On first launch, SeekSync uses an existing Sockseek 3 installation when available. If none is found, it downloads the pinned official macOS release (currently 3.0.4), verifies GitHub's published SHA-256 digest, and installs the executable under `~/Library/Application Support/SeekSyncPrototype/Tools/`. Sockseek remains a separate process and is licensed under AGPL-3.0; its license and corresponding source are available from [fiso64/sockseek](https://github.com/fiso64/sockseek/tree/v3.0.4).

## Install with Homebrew (recommended)

The published app requires an **Apple silicon Mac (M1 or later)** and
**macOS 14 Sonoma or later**. Install [Homebrew](https://brew.sh/) first if
you do not already have it, then run:

```sh
brew tap discolotus/tap
brew install --cask discolotus/tap/seeksync
open -a SeekSync
```

Homebrew installs `SeekSync.app` in `/Applications` and verifies the release
archive against the cask's SHA-256 checksum. Xcode is not required to run the
packaged app.

### First launch: approve the app in macOS

SeekSync releases are **ad-hoc signed but not Apple-notarized**. macOS may
block the first launch because it cannot verify the developer. For a copy
installed from the tap above or the official GitHub releases:

1. Try opening SeekSync from Applications once, then dismiss the blocked-launch alert.
2. Open **System Settings → Privacy & Security**.
3. Scroll to the security section and click **Open Anyway** beside the SeekSync message.
4. Authenticate if prompted, then confirm **Open**.

See [Apple's instructions for opening an app from an unknown developer](https://support.apple.com/guide/mac-help/mh40616/mac).
This approves this app for subsequent launches. **Manual `codesign` commands
are not part of installation**: the release packaging already signs the app.
Re-signing it yourself does not provide Apple notarization. There is no need
to disable Gatekeeper globally.

If macOS reports that the app is damaged, reinstall the official package:

```sh
brew reinstall --cask discolotus/tap/seeksync
```

### Updates

Quit SeekSync after any active sync finishes, then run:

```sh
brew update
brew upgrade --cask discolotus/tap/seeksync
open -a SeekSync
```

The tap imports releases on a schedule, so a newly published GitHub release
may take time to appear in Homebrew.

## Install manually

1. Open the [official releases page](https://github.com/discolotus/SeekSync/releases).
   Releases may be marked as prereleases.
2. Download the desired release's `SeekSync-<version>-arm64.zip` and matching
   `.zip.sha256` file into the same folder.
3. In Terminal, change to that folder and verify the archive (replace
   `<version>` with the downloaded version):

   ```sh
   shasum -a 256 -c "SeekSync-<version>-arm64.zip.sha256"
   ```

4. Confirm the result says `OK`, unzip the archive, and drag `SeekSync.app`
   into Applications. Quit an existing copy before replacing it.
5. Open SeekSync and follow the first-launch approval steps above if needed.

## First-run setup

- Allow the automatic Sockseek dependency check to finish. SeekSync reuses a
  compatible installation or installs its pinned version automatically.
- In **Settings**, select your Sockseek config and music output folder.
  SeekSync detects `~/.config/sockseek/sockseek.conf`, with
  `~/.config/sldl/sldl.conf` as a legacy fallback. Configure your Soulseek
  credentials for live syncs; Spotify library browsing also needs the Spotify
  credentials supported by Sockseek. See the
  [Sockseek configuration documentation](https://github.com/fiso64/sockseek#readme).
  Use **Save config** to explicitly save settings changes.
- Confirm the sidebar reports Sockseek ready. Load your Spotify library or
  paste a playlist URL, then review and confirm the sync preview to start a run.
- Daily syncs require explicitly arming live scheduling and keeping SeekSync
  running. Quitting the app stops scheduling.

## Refresh library matches and manage the queue

In **Settings → Existing music library**, enable reuse and choose your music
folder, then click **Reindex Library**. SeekSync refreshes matches for every
loaded real playlist, one at a time, bypassing cached preview matches. Progress
shows the current playlist; **Cancel** stops the batch and keeps completed
inventories. This reads playlist metadata and local files without downloading
music. Large playlist collections can take time. Files still need matching tags
and must meet the preferred quality conditions to qualify for reuse.

Open **Sync Queue** in the sidebar to see the current run and every waiting
playlist in execution order. Use the arrows to reorder waiting jobs or remove
an individual job. Cancelling the active sync starts the next queued job unless the queue is paused.
Pause lets the current job finish and holds waiting jobs and daily schedules.
Waiting jobs retain their order and confirmed commands across restarts. A restored
queue starts paused; choose Resume queue when ready.
**Sync Pool** manages daily schedules separately; they also appear under
Scheduled playlists in Sync Queue. Due jobs start when the queue is idle,
while scheduling is armed and the app is running.

## Spotify playlist access errors

A playlist that opens in Spotify may still be unavailable through its Web API.
Spotify restricts some algorithmic and Spotify-owned playlists for development
apps ([Spotify's API announcement](https://developer.spotify.com/blog/2024-11-27-changes-to-the-web-api)).
An HTTP 404 can also mean the URL is unavailable or the connected account lacks
access; it does not by itself prove the playlist was deleted.

Check the URL and account in Spotify. For a personalized playlist such as a
Top Songs collection, try copying its tracks into a regular playlist you own,
then import the new playlist URL. Use **Analyze Library** again. A failed
playlist read blocks that preview's **Start Sync** until metadata can be read;
changing YouTube fallback or rebuilding the local index cannot fix API access.

## Build and run from source

Source builds require Apple's Swift development tools (Xcode or Command Line
Tools), with Swift 5.10 or later. From the repository folder:

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
- A combined rekordbox library written beside the downloads folder after each
  sync. `SeekSync.rekordbox.xml` describes every synced playlist in one file, so
  **File → Import Library → rekordbox xml** brings them all in at once. SeekSync
  only writes this file; it never reads or changes a rekordbox library, and
  rekordbox still analyses BPM and key itself.
- A read-only preflight compares preferred-condition-gated and ungated local
  matches against an empty mock backend. It also carries forward the stable
  playlist index, so it can distinguish references, prior downloads,
  below-target files, and downloads needed without connecting to Soulseek or
  changing music files.
- A read-only Track Inventory section gathers every previewed track across all
  playlists into one searchable list, stating whether each song already exists
  on this Mac and whether a playlist can link to it as it stands.
- Repeat previews of an unchanged library reuse the cached Sockseek index
  instead of rebuilding the music-directory tag index on both passes. A
  file-count, size, and modification stamp of the library invalidates it.
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

### Playable files and track details

Right-click a playlist with a saved inventory and choose **View Tracks and Quality…**
to search its titles, artists, albums, and paths or filter by status. Local coverage
includes playable below-target files; they remain upgrade candidates.

Syncs write `SeekSync-<playlist-id>.m3u8` in the configured output directory. Once
full metadata reconciliation finishes, this playlist and the rekordbox XML retain
existing playable copies when an upgrade fails. A later successful upgrade updates
the reference. Original audio is left in place, and fallback export never changes
the backend's retry index. Older backend-named M3U files are not migrated.
