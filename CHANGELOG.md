# Changelog

All notable changes to SeekSync are documented here. Versions follow
[Semantic Versioning](https://semver.org/).

## [0.6.0] - 2026-10-02

- Save waiting syncs, their order, and confirmed commands across app restarts;
  restore paused and add pause/resume controls for queue and scheduled starts.
- Keep valid local audio visible after unsuccessful upgrade attempts and count
  below-target files as locally available without clearing their upgrade status.
- Keep playable fallback files in reconciled M3U and rekordbox exports without
  marking failed downloads successful in the backend index.
- Open saved track details directly from a playlist context menu, with search,
  status filters, file paths, and measured audio quality.

## [0.5.2] - 2026-10-02

- Preserve full playlist inventories when backend progress includes only a sample
  of tracks, and reconcile completed syncs against current playlist metadata.
- Validate local library previews larger than 20 pending tracks without rejecting
  valid sampled progress; retain complete terminal and index checks.
- Canonicalize duplicate historical rows in temporary preview indexes.
- Count existing tracks from backend totals when their detail rows are sampled.
- Keep partial inventories from shrinking playlist totals or claiming full coverage.
- Avoid live-network rate-limit delays in read-only, empty-mock library previews.
- Attribute concurrent fallback failures to the correct track.
- Expose playlist rows as accessible buttons with local coverage values.

## [0.5.1] - 2026-09-27

- Explain Spotify playlist HTTP 404 failures with account, URL, and personalized
  playlist recovery guidance instead of exposing only backend diagnostics.
- Keep single-playlist sync confirmation blocked after a failed metadata read
  or while analysis is running; clear the access error when a retry reads tracks.

## [0.5.0] - 2026-09-26

- Add a global Reindex Library action in Settings with sequential playlist
  analysis, progress, cancellation, and forced refresh of cached local matches.
- Add a dedicated Sync Queue screen with the active run, all waiting playlists
  in execution order, and controls to reorder or remove waiting jobs.
- Distinguish queued jobs from daily schedules and explain queue lifetime.

## [0.4.2] - 2026-09-26

- Document Homebrew installation and updates, macOS first-launch trust
  approval, manual download verification, and initial SeekSync setup.
- Clarify that release bundles are already ad-hoc signed and do not require
  users to sign the app manually.

## [0.4.1] - 2026-08-07

- Add a Track Inventory section that gathers every previewed track across all
  playlists into one searchable, filterable list, so a song shared by three
  playlists is one row. Each row states whether the file already exists on this
  Mac and whether a playlist can link to it as it stands, with its path,
  quality, and the playlists that want it. Read-only.
- Cache the Sockseek index produced by a library-reuse preview so a repeated
  preview of an unchanged library skips rebuilding the music-directory tag
  index on both passes. The cache is keyed to the library folder, preferred
  conditions, and a file-count/size/modification stamp of the library, so an
  added, removed, or replaced file still forces a full pass.
- Report library-preview progress, failures, and cancellations on the playlist
  detail screen. Previously a preview that failed left no analysis behind and
  its message was never rendered, so pressing "Preview Library Reuse" appeared
  to do nothing.

## [0.4.0] - 2026-08-07

- Write a combined rekordbox library, `SeekSync.rekordbox.xml`, beside the
  downloads folder after each sync, so File → Import Library brings every
  synced playlist into rekordbox at once instead of one M3U at a time.
- Describe each downloaded or referenced track once in the collection, even
  when several playlists share it, and keep each playlist's track order.
- Add a settings toggle for the export. It is a SeekSync preference and is
  never written into Sockseek's config.
- Keep app-local preferences in one merge point so reloading Sockseek's config
  cannot silently drop one.

## [0.3.5] - 2026-08-06

- Add an opt-in existing-music-library folder whose qualifying tracks are
  referenced in generated M3U playlists instead of downloaded or copied.
- Preview library reuse without contacting Soulseek by comparing
  preferred-condition-gated and ungated tag matches against an isolated empty
  mock backend, while carrying forward the playlist's stable output index.
- Keep a per-playlist track inventory with library references, below-target
  local matches, prior downloads, download needs, file paths, and available
  audio-quality data; reconcile it with the real index after each sync.

## [0.3.4] - 2026-08-06

- Let individually confirmed playlists join the active sequential sync queue,
  with visible ordering, duplicate prevention, and per-item removal.
- Preserve the exact settings snapshot confirmed for each queued sync and
  advance to the next playlist after completion or cancellation.
- Display the packaged SeekSync version beside the detected Sockseek version
  in the sidebar status area.

## [0.3.3] - 2026-08-06

- Add a searchable playlist grid for selecting and confirming one-time batch
  sync queues that run sequentially.
- Exercise the signed ARM64 release archive in pull-request CI by installing it
  into an isolated Applications-style directory and launching its root window
  on the macOS 15 publishing runner.

## [0.3.2] - 2026-08-06

- Preserve the playlist position, song, artist, album, and reason for each
  track that fails or needs review during a sync.
- Identify whether a missing track came from Soulseek, the YouTube/yt-dlp
  fallback, both search paths, or a cached previous result.
- Show per-track failure details in Activity, run details, and Needs Attention.

## [0.3.1] - 2026-08-06

- Refine the playlist sync confirmation dialog with a clearer summary of the
  destination, audio target, quality policy, and YouTube fallback behavior.
- Keep the sanitized command available as optional detail while making live
  downloads, demo previews, and start blockers visually distinct.
- Add app-scoped render coverage for both live and preview-only sync states.

## [0.3.0] - 2026-08-06

- Reorganize Settings around downloads, accounts, automation, and Sockseek
  health while moving detected executable and config locations into Advanced.
- Add a native downloads-folder picker with explicit options to move the
  existing library or leave it in place, refusing destination conflicts before
  any files are moved.
- Replace free-form audio preferences with format and contextual bitrate menus
  backed by Sockseek's `pref-format` and `pref-min-bitrate` settings while
  preserving custom existing values.
- Keep account credentials locked until Edit is chosen, add intentional secret
  reveal controls, and retain compatibility with previously saved app state.
- Make save and reload behavior explicit, showing the Sockseek config and local
  app-data locations while clarifying that credentials are excluded from app state.
- Store application state under `Application Support/SeekSync` and import the
  previous `SeekSyncPrototype` state non-destructively on first launch.

## [0.2.1] - 2026-08-04

- Polish the responsive library and inspector layouts across compact and wide
  windows while keeping sync mode and design controls accessible.
- Restore reliable fresh-launch window creation and align the packaged app's
  visible identity.
- Add render coverage for supported layouts and sheets, plus updated visual QA
  guidance and audit notes.

## [0.2.0] - 2026-08-04

- Make confirmed manual syncs real for Spotify and pasted-URL playlists while
  keeping bundled demo playlists preview-only.
- Show the active track number, artist, title, search/download phase,
  byte-level download progress, completed count, synced count, already-local
  count, failures, and review count while Sockseek is running.
- Preserve the separate explicit arm control for unattended daily downloads.

## [0.1.3] - 2026-08-03

- Emit a portable release checksum that verifies after the ZIP and checksum
  are downloaded together, without referencing a CI runner path.

## [0.1.2] - 2026-08-03

- Generate the supported Homebrew macOS dependency declaration and validate
  cask syntax and style during pull-request CI.

## [0.1.1] - 2026-08-03

- Update CI to the current GitHub Actions runtime while preserving the verified
  application package and icon pipeline.

## [0.1.0] - 2026-08-03

- Add a responsive native macOS library and inspector interface.
- Load complete Spotify playlist catalogs while retaining a paste-by-URL path.
- Preview or run Sockseek syncs with simulation enabled by default.
- Add isolated live acceptance coverage, dependency health, activity history,
  daily sync controls, and safe configuration persistence.
- Add a native multi-resolution macOS application icon from the approved,
  name-neutral blue-and-violet sync mark.
- Package an ad-hoc-signed Apple-silicon application and Homebrew cask.
