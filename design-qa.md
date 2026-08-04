# SeekSync responsive design QA

## Artifacts

- Source visual truth: `/var/folders/t7/37h7jgy56sv2zwgf0mbv3wtc0000gn/T/codex-clipboard-67d9eabf-f08f-46a7-8d7f-08ad282039b8.png`
- Source pixels: 2370 × 1472, macOS Retina capture at approximately 2× density.
- Source state: dark appearance, playlist library, playlist selected, details open, real Spotify catalog content.
- Standard implementation: `/private/tmp/seeksync-ui-qa-v2/implementation-standard-1180x720@2x.png`
- Standard implementation pixels/CSS/density: 2360 × 1440; 1180 × 720 points; 2×.
- Compact implementation: `/private/tmp/seeksync-ui-qa-v2/implementation-compact-994x624@2x.png`
- Compact implementation pixels/CSS/density: 1988 × 1248; 994 × 624 points; 2×.
- Settings implementation: `/private/tmp/seeksync-ui-qa-v2/implementation-settings-660x560@2x.png`
- Sync-preview implementation: `/private/tmp/seeksync-ui-qa-v2/implementation-sync-preview-680x500@2x.png`
- Canonical icon source: `Resources/AppIconSource.png`, 1254 × 1254 pixels.
- Frontend identity implementation: `/private/tmp/seeksync-ui-qa-v2/implementation-brand-header-320x80@2x.png`, 640 × 160 pixels at 2×.
- Icon/identity comparison: `/private/tmp/seeksync-ui-qa-v2/comparison-app-icon-vs-brand-header-640x160@2x.png`, 1280 × 320 pixels at 2×.
- Theme/state: dark appearance, Simulation mode, isolated fixture config/state, `Midnight Drive` selected, details presented.

## Normalization

- Full-view comparison: `/private/tmp/seeksync-ui-qa-v2/comparison-full-source-vs-standard.png`.
- Focused inspector comparison: `/private/tmp/seeksync-ui-qa-v2/comparison-focused-inspector-source-vs-compact.png`.
- The full comparison normalizes both images to a 2360 × 1440 panel and places source left, implementation right.
- The focused comparison crops the source and implementation detail regions, normalizes both to 840 × 1248, and places source left, implementation right.
- The source includes native window chrome and live Spotify artwork; the app-scoped implementation render excludes window chrome and uses deterministic fixture artwork. Those state differences are not treated as fidelity defects.

## Findings

- [P2] Full integrated native-window evidence is incomplete.
  - Location: full-view implementation, native `NavigationSplitView` sidebar layer and sync-preview native GroupBox layer.
  - Evidence: the app-scoped renderer captures the primary library, inline/overlay details, Settings, and sheet frame, but rasterizes the native sidebar/GroupBox layers as blank. The full comparison therefore cannot prove the final sidebar/footer fix and every sync-preview row in one integrated frame.
  - Impact: the code, tests, and focused visual evidence are strong, but a complete visual handoff would overstate what was actually captured.
  - Fix: obtain a user-supplied app-window screenshot or another narrow app-window capture mechanism. Do not request broad screen/audio permission.

## Required fidelity surfaces

- Fonts and typography: system font family and rounded display treatment are preserved. Title, metadata, status, and policy hierarchies remain consistent. Focused captures show no action-label, percentage, or policy-value truncation. Long policy values reflow vertically.
- Spacing and layout rhythm: the unnecessary 48-point top inset is removed. Sidebar/list widths no longer depend on inspector compression. Compact details use a 360–420-point overlay; standard/wide details use a 340/380-point inline panel. Settings and sync preview use bounded, scrollable frames.
- Colors and tokens: semantic system/accent colors, secondary text, materials, status orange/blue/green/red, dividers, and selection tint remain mapped to the existing design language. Contrast appears consistent in dark mode; light mode remains unverified.
- Image quality and asset fidelity: production continues to use Spotify `AsyncImage` artwork when available. The visual QA fixture intentionally uses the existing generated fallback because no live artwork is loaded; it is not a production replacement for the source artwork.
- Copy and content: app-specific copy is preserved except for the removal of redundant sidebar execution-mode text and the addition of `Playlist details` / `Compact view` to orient the overlay. Simulation safety copy remains visible in the toolbar and preview.
- Icons and interactions: existing SF Symbols are preserved. Compact details add a real SF Symbol close control, Escape shortcut, click-outside dismissal, automatic opening after playlist selection, and reduced-motion-aware animation.
- Product identity: the packaged `AppIcon.icns` is now the canonical frontend mark. A shared lockup presents that exact icon in the sidebar and menu popover; the menu-bar status glyph stays monochrome for macOS legibility. The icon is decorative in the lockup, with one combined accessibility label.

## Comparison history

### Iteration 0 — source failure

- Earlier P1: details actions and policy content clip beyond the right edge.
- Earlier P2: top dead band wastes 48 points of vertical space.
- Earlier P2: fixed Settings/sync-preview sizing can exceed the practical display height.
- Fixes: adaptive overlay/inline details modes, `ViewThatFits` action/metric/policy layouts, removed top inset, bounded scrollable Settings and sync preview.

### Iteration 1 — packaged app state

- Earlier P2: redundant sidebar execution-mode copy was clipped at the bottom.
- Fix: removed duplicate footer copy; execution mode remains in the toolbar.
- Post-fix evidence: component and focused-region app-scoped renders under `/private/tmp/seeksync-ui-qa-v2/`.

### Iteration 2 — focused post-fix comparison

- The source detail action row is visibly cut off; the compact implementation keeps both actions fully visible.
- Source coverage/policy content reaches or crosses the visible edge; implementation values and status pills fit and retain hierarchy.
- No new actionable P0/P1/P2 mismatch is visible in the captured library/detail regions.
- Remaining blocker: complete integrated native sidebar and sync-preview layer capture.

### Iteration 3 — app identity alignment

- Earlier P2: the Dock/Finder icon and sidebar identity used visibly different artwork; the menu popover had no product lockup.
- Fix: introduced `SeekSyncBrandAssets`, `SeekSyncAppIcon`, and `SeekSyncBrandHeader`, using the packaged icon rather than an approximate redraw.
- Post-fix evidence: `/private/tmp/seeksync-ui-qa-v2/comparison-app-icon-vs-brand-header-640x160@2x.png` shows the canonical icon and frontend lockup together.
- No clipping, interpolation artifact, duplicate accessibility announcement, or visual identity mismatch is visible in the accepted component render.

## Primary interactions and verification

- Compact and standard details-presented states rendered at supported sizes.
- Playlist selection is wired to present details automatically.
- Compact close button, Escape shortcut, click-outside dismissal, and reduced-motion behavior are implemented.
- Settings and sync preview render inside bounded scrollable frames.
- `make test`: 40 tests executed, 2 explicitly gated live tests skipped, 0 failures.
- Packaged app: `dist/SeekSync.app`; `codesign --verify --deep --strict --verbose=2` passed after the final rebuild.
- Browser console: not applicable to this native SwiftUI app. Build/test logs are the relevant error surface.

## Implementation checklist

- [x] Preserve the existing visual language and native typography.
- [x] Remove the extra top inset.
- [x] Prevent the inspector from squeezing the compact layout.
- [x] Reflow inspector actions, metrics, pills, and policy values.
- [x] Remove clipped redundant sidebar copy.
- [x] Bound and scroll Settings and sync-preview windows.
- [x] Add compact/standard app-scoped render smoke coverage.
- [x] Align the sidebar and menu popover identity with the packaged app icon.
- [ ] Capture one final integrated app window without broad screen/audio access.

## Follow-up polish

- [P3] Verify light appearance, keyboard focus traversal, and VoiceOver announcements in a user-driven pass.
- [P3] Consider replacing the `Compact view` subtitle with the selected playlist owner when the layout is stable.

final result: blocked

Blocker: the narrow app-scoped renderer cannot faithfully capture the native sidebar and every sync-preview GroupBox layer in one integrated window, and broad screen/audio access is intentionally not requested.
