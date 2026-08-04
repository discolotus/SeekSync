# SeekSync responsive UI audit

## Audit scope

- Surface: playlist library, playlist details, Settings, sync-preview presentation, and app identity surfaces.
- User goal: browse and act on playlists without clipped text, controls, or off-window content at supported macOS window sizes.
- Accessibility target: keyboard-reachable native controls, text alternatives for status, reduced-motion-aware transitions, and layouts that reflow instead of truncating.
- Source evidence: `/var/folders/t7/37h7jgy56sv2zwgf0mbv3wtc0000gn/T/codex-clipboard-67d9eabf-f08f-46a7-8d7f-08ad282039b8.png`.

## Steps and findings

1. Playlist library at the default window size — unhealthy in the source capture.
   - Strength: the library hierarchy, selected-row treatment, semantic status colors, and artwork grid are easy to scan.
   - P1 risk: opening the details inspector compresses persistent regions unpredictably; the daily-sync action and policy values extend past the visible edge.
   - P2 risk: an extra 48-point top inset creates a dead band and reduces usable vertical space.
   - P2 risk: the sidebar footer repeats the toolbar execution mode and is clipped at the bottom.

2. Playlist selection and details opening — unhealthy in the source capture.
   - P1 risk: the details action row assumes both large labels fit horizontally.
   - P1 risk: coverage and effective-policy rows do not reflow when the detail column narrows.
   - Accessibility risk: hidden control text makes task completion and keyboard orientation uncertain; screenshot evidence alone cannot confirm focus order.

3. Compact playlist details — improved in the implementation.
   - The details surface becomes a dismissible overlay below 1,050 points, preserving the sidebar and list widths.
   - Primary actions, coverage metadata, status pills, and policy values use fit-based horizontal or vertical arrangements.
   - The overlay has a visible close control, Escape shortcut, click-outside dismissal, and reduced-motion-aware transition.

4. Settings and sync preview — improved structurally.
   - Settings is bounded to 660 × 560 points and remains scrollable.
   - Sync preview is bounded to 680 × 500 points, scrolls its policy/content region, and keeps Cancel/Run actions fixed in a footer.
   - The app-scoped renderer cannot faithfully rasterize every native sidebar/GroupBox layer, so a final integrated visual claim remains blocked without requesting broad screen access.

5. App icon and frontend identity — healthy after alignment.
   - The packaged app already had a distinctive navy, blue, and purple sync/waveform icon, but the sidebar used an unrelated blue `waveform.badge.magnifyingglass` tile and the menu popover had no product lockup.
   - The frontend now loads the packaged `AppIcon.icns` as its canonical identity asset through `SeekSyncBrandAssets` and uses one reusable `SeekSyncBrandHeader` in the sidebar and menu popover.
   - The macOS menu-bar status item remains a monochrome sync glyph for legibility and platform convention; the opened popover carries the full-color product identity.
   - App-icon versus frontend comparison: `/private/tmp/seeksync-ui-qa-v2/comparison-app-icon-vs-brand-header-640x160@2x.png`.
   - Accessibility: the decorative icon is hidden from assistive technology and the combined lockup announces `SeekSync, playlist sync` once.

## Applied recommendations

- Use an overlay details panel for compact windows and a deterministic inline panel for standard/wide windows.
- Keep the supported minimum at 860 × 520 rather than locking the app to one large size.
- Remove the redundant top inset and duplicate sidebar execution-mode copy.
- Reflow action, coverage, status, and policy rows with `ViewThatFits`.
- Keep sheets bounded and scroll long content instead of growing beyond the display.
- Add app-scoped 2× render smoke tests at 994 × 624 and 1,180 × 720, plus Settings and sync-preview states.
- Use the packaged app icon as the single frontend identity source instead of maintaining a separate approximate symbol.

## Evidence limits

- The source screenshot and focused implementation inspector were compared in one composite at `/private/tmp/seeksync-ui-qa-v2/comparison-focused-inspector-source-vs-compact.png`.
- The canonical app icon and implemented frontend lockup were compared in one composite at `/private/tmp/seeksync-ui-qa-v2/comparison-app-icon-vs-brand-header-640x160@2x.png`.
- The full comparison at `/private/tmp/seeksync-ui-qa-v2/comparison-full-source-vs-standard.png` exposes a renderer limitation: the native sidebar layer is blank in the implementation half even though the previously captured packaged-app state showed it populated.
- No claim of complete VoiceOver, focus-order, light-mode, or full native-window visual compliance is made.
