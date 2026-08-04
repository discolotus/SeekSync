# SeekSync Direction A — QA Record

## Current result

Direction A is the only interface in the app. Directions B and C, their selector, and their keyboard shortcuts have been removed.

The packaged app launches as a responsive Library + Inspector window. At compact widths the inspector stays closed until requested from the toolbar, so playlist selection cannot widen or crop the window. The Simulation/Live safety state remains visible in the toolbar.

## Visual baseline

- Failure baseline: `/var/folders/t7/37h7jgy56sv2zwgf0mbv3wtc0000gn/T/codex-clipboard-2599090e-bc9b-4f54-90d7-a49e33e31c91.png`
- Repaired Direction A capture: `/private/tmp/seeksync-final-a-994x624-postlaunch.png`
- QA size: 994 × 624 points
- Minimum supported content size: 860 × 520 points
- Default content size: 1180 × 720 points

The failure baseline is not a visual target. It demonstrates a window that was larger than the visible display and therefore lost the header, artwork, safety state, and prototype controls outside the frame.

## Direction A checks

- Native `WindowGroup` launches a standard restorable window.
- Sidebar width is 170–220 points; playlist content has a 380-point minimum.
- The optional native inspector is 300–400 points and does not force open at compact widths.
- Search, playlist selection, primary sync action, explicit status text, and toolbar safety state remain available.
- Selection uses a leading accent and restrained tint rather than a heavy full-row block.
- Demo playlists are labeled as demo data.
- Command preview is disclosed on demand and remains selectable without dominating the inspector.
- Progress views have descriptive accessibility labels and values.
- Color is accompanied by status text or symbols.

## Backend behavior checks

- Spotify responses tolerate nullable artwork and null playlist records.
- Every `next` page is followed and repeated playlist IDs are removed while preserving order.
- An expired access token triggers one refresh and retries the catalog with the new token.
- Imported and catalog playlists use the same Sockseek sync path.
- Command construction includes a stable index, JSON progress, preferred-condition rechecks, playlist writing, and an explicit YouTube fallback policy.
- The installed Sockseek 3 binary completed a local mock run and emitted terminal JSON that SeekSync parsed into result counts.
- Sockseek output is streamed into the active run so progress and terminal counts update before the process exits.
- Completed and partial results update playlist track counts and local coverage.
- Spotify refreshes preserve local coverage and sync status, while catalog metadata replaces matching pasted-URL placeholders.
- Both terminal `track_state` events and already-indexed outcomes embedded in the initial `track_list` are counted; a real two-pass Sockseek run covers the repeat-sync path.
- Cancellation terminates the child process owned by SeekSync.
- Live scheduling remains separately armed and fixture playlists cannot start a live download.

## Automated verification

- 39 tests pass with zero failures; the explicitly gated live Spotify and bounded live-sync tests are skipped during isolated runs.
- The production app bundle builds successfully.
- The packaged app passes strict deep code-signature verification.
- The app can be launched directly with isolated config and state paths; Finder and global screen/audio access are not required.

## Live acceptance proof

After explicit authorization on 2026-08-03:

- The real-account catalog test passed in 4.94 seconds after consuming every Spotify page and rejecting duplicate IDs.
- The final app persisted 575 Spotify playlists with 575 unique IDs and zero fixture playlists.
- The bounded live-sync test passed in 55.76 seconds with `--number 1` and YouTube fallback disabled.
- Sockseek produced exactly one audio file and the stable playlist index inside a unique temporary QA folder; the test removed that folder afterward.
- The configured music library was not used by the acceptance test.
- The packaged real-account app relaunched in Simulation mode with unattended scheduling disarmed.

Global appearance switching and an interactive VoiceOver session are also outside this app-only QA pass. The implementation uses semantic colors, native typography, accessibility labels and values, keyboard-accessible controls, and textual status so those safeguards do not depend on global screen control.
