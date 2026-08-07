# Changelog

All notable changes to SeekSync are documented here. Versions follow
[Semantic Versioning](https://semver.org/).

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
