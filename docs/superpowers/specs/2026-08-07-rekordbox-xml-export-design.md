# Rekordbox XML Export — Design

Date: 2026-08-07
Branch: `claude/rekordbox-xml-playlists-0234bb`

## Problem

Importing SeekSync's output into rekordbox is clunky. SeekSync asks Sockseek to
write one M3U per playlist. M3U is a bare list of file paths, so rekordbox
imports one playlist at a time, carries no playlist tree, and holds no track
metadata beyond what it re-reads from each file.

## Goal

Write one combined rekordbox XML library describing every synced playlist, so a
single **File → Import Library → rekordbox xml** brings the whole downloads
library in at once, with its playlist structure intact.

## Scope

In scope:

- One combined `DJ_PLAYLISTS Version="1.0.0"` XML covering all synced playlists.
- Automatic regeneration after every sync run.
- A settings toggle, on by default.

Out of scope:

- **BPM and musical-key analysis.** SeekSync exports only metadata it already
  holds. Rekordbox analyses tracks itself on import, as it does for any newly
  added file. Rekordbox does not write back into a third-party XML file; its
  analysis lands in its own database, and re-exporting it is a manual
  **File → Export Collection in xml format** action inside rekordbox with no
  API for SeekSync to hook. Adding analysis to SeekSync would mean a new audio
  DSP dependency, which this project does not need to solve the import problem.
- Reading, modifying, or importing any existing rekordbox library or XML.
  SeekSync only writes its own new file.
- Replacing M3U output. M3U stays: the existing library-reuse feature depends
  on it, and the XML is purely additive.

## Data flow

1. Sockseek already writes a stable index CSV per playlist into the downloads
   folder (`.seeksync-index-<slug>.csv`, see
   `SockseekCommandBuilder.indexPath`). Each row carries path, artist, album,
   title, length, and state.
2. After a sync finishes, the exporter walks every known playlist, resolves its
   index path, and parses it with the existing `SockseekIndexParser`.
3. Rows are kept only when `isAvailable` holds — downloaded or already-present
   files that resolved to a real path. Everything else is dropped.
4. Tracks are deduplicated by resolved file path and assigned a stable
   `TrackID`, so a file appearing in three playlists yields one `COLLECTION`
   entry referenced three times.
5. A `PLAYLISTS` tree is built: one folder node named `SeekSync` holding one
   playlist node per synced playlist, each listing its track IDs in index order.
6. The document is written to `<outputDirectory>/SeekSync.rekordbox.xml`, one
   stable path, rebuilt in full each time rather than patched incrementally.

Playlists with no index file on disk are skipped. Demo fixture playlists never
sync, so they fall out of the export without a special case.

## Components

All new code lives in `Sources/SeekSyncPrototype/RekordboxExport.swift`.

- `RekordboxTrack` / `RekordboxPlaylistNode` — value types. A track holds id,
  path, title, artist, album, seconds, and kind; a node holds a playlist name
  and its ordered track ids.
- `RekordboxCollectionBuilder` — pure, no file I/O. Maps
  `[(Playlist, [SockseekIndexEntry])]` to tracks and nodes. Owns availability
  filtering, path deduplication, and track-id assignment.
- `RekordboxXMLWriter` — pure. Renders builder output to an XML string. Owns
  attribute escaping and `file://` URI encoding.
- `RekordboxXMLExporter` — the only type that touches the filesystem. Resolves
  index paths, parses them, calls the builder and writer, and writes the result
  atomically.

Both pure types are unit-testable without a disk.

### Track fields

Each `COLLECTION` entry carries `TrackID`, `Name` (title), `Artist`, `Album`,
`TotalTime` (seconds), `Kind` (derived from the file extension), and `Location`
(a percent-encoded `file://localhost` URI, the form rekordbox writes). Fields
the index leaves empty are omitted rather than written blank.

## Wiring

- `ClientSettings` gains `rekordboxXMLEnabled: Bool?`, following the existing
  app-local preference pattern used by `libraryReuseEnabled`. It is **not** a
  Sockseek config key: Sockseek has no rekordbox support, and this setting must
  never be written into the user's `sockseek.conf`. Like its siblings, it is
  preserved across config reloads by `mergingPrototypePreferences` and the
  equivalent inline merges in `AppModel`. A nil value reads as enabled, so
  existing installs get the export without touching their saved state.
- `AppModel.finishRun` calls one new private `regenerateRekordboxXML()` after
  `persist()`.
- Settings gains a toggle beside the existing "Write an M3U playlist" control.

## Error handling

Export is a side effect of syncing and must never break a sync.

- The whole regeneration is wrapped; no failure propagates into `finishRun`.
- A missing or unreadable index file skips that playlist and exports the rest.
  A partial library beats no library.
- Zero exportable tracks skips the write entirely, leaving any previous XML
  intact. A good file is never truncated to an empty one.
- Write failures surface through the existing `toastMessage` path as one
  non-blocking line.
- The write is atomic, so an interrupted export cannot leave rekordbox reading
  half a document.

## Testing

Tests go in `Tests/SeekSyncPrototypeTests/SeekSyncPrototypeTests.swift`,
XCTest, matching the existing style.

Builder, no disk:

- A file in two playlists produces one collection entry and two nodes sharing
  its track id.
- Entries without a path, or not available, are excluded.
- Track order within a node follows index order.

Writer, no disk:

- `&`, `<`, and quotes in artist and title are escaped.
- Spaces and non-ASCII characters in paths produce a valid `file://` URI.
- Output parses through `XMLDocument` with the expected node counts.

Exporter, temporary directory:

- Real index CSVs plus one playlist missing its index: the missing playlist is
  skipped and the rest export.
- A zero-track export leaves an existing file untouched.

Settings:

- `rekordboxXMLEnabled` survives a config reload, and is absent from the
  rendered Sockseek config.
