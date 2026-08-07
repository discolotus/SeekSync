# SeekSync Settings redesign QA

## Evidence

- Source visual truth:
  - `/var/folders/t7/37h7jgy56sv2zwgf0mbv3wtc0000gn/T/codex-clipboard-8e4953d5-3674-450e-81b1-0dd1c002a805.png`
  - `/var/folders/t7/37h7jgy56sv2zwgf0mbv3wtc0000gn/T/codex-clipboard-688c99c3-4251-487d-8e72-fdc453917545.png`
- Source pixels: 1234 x 584 and 1242 x 862. The captures show the original light-appearance Settings screen, including the dependency paths, download fields, and account fields.
- Rendered implementation: `/private/tmp/seeksync-settings-qa/implementation-settings-660x560@2x.png`
- Implementation pixels and viewport: 1320 x 1120 at 2x; 660 x 560 points.
- State: light appearance, isolated fixture config, FLAC preference, credentials locked, Advanced collapsed, Sockseek fixture binary ready.
- Full comparison: `/private/tmp/seeksync-settings-qa/comparison-settings-source-vs-implementation.png`
- Density normalization: both source captures were scaled to approximately half-size and stacked in a 660-point-wide source panel. The 2x implementation was normalized to 660 x 560 points and placed in the adjacent panel.
- Focused comparison: the full comparison keeps the form controls and explanatory copy legible, so a separate crop was not required.

## Findings

No actionable P0, P1, or P2 visual differences remain. The information hierarchy intentionally differs from the source: Downloads and Accounts are now primary, Sockseek health is user-facing, and executable/config locations are moved into Advanced.

- Fonts and typography: the existing macOS system hierarchy, label weights, caption sizing, and eyebrow treatment are preserved. Long help text wraps without clipping.
- Spacing and layout rhythm: the original GroupBox language and section rhythm remain, with dividers separating destination, quality, and fallback controls. The compact 660 x 560 viewport scrolls rather than clipping later sections.
- Colors and visual tokens: native window, GroupBox, secondary-label, control-fill, and semantic status colors are preserved from the source.
- Image quality and assets: Settings contains no custom raster imagery. Native SF Symbols are used for the folder, Advanced, and reveal controls.
- Copy and content: implementation details were replaced with task-focused language. Lossless formats explain why bitrate is not shown; lossy formats use Sockseek's actual preferred-minimum-bitrate setting.
- Affordances: Downloads uses a conventional folder button; Accounts has an explicit Edit state; dependency paths are no longer editable text fields; Advanced remains discoverable without dominating the page.

## Interaction and regression checks

- `make test`: 48 tests executed, 2 explicitly gated live tests skipped, 0 failures.
- The isolated render confirms the default locked-credentials and collapsed-Advanced states.
- Library moves preflight destination conflicts and refuse to overwrite existing files; covered by unit tests.
- Config parsing and saving round-trip `pref-min-bitrate`; legacy saved settings without the new field still decode; covered by unit tests.
- Native click-through inspection was attempted with the isolated fixture app, but the Mac was locked. The file picker, credential reveal, and confirmation dialog could not be clicked in that pass; this is a runtime interaction verification gap, not a visible design mismatch.
- Browser console: not applicable to this native SwiftUI app.

## Comparison history

### Iteration 0 - source review

- P1: raw executable and config paths read as required setup rather than automatically managed infrastructure.
- P1: output directory and preferred formats were free-form text fields, making common choices error-prone.
- P1: credential fields were always editable and password contents could not be intentionally revealed.
- P2: dependency/config details appeared before the user-facing download and account choices.

### Iteration 1 - post-fix comparison

- Dependency health is summarized with automatic management and repair/check controls; raw paths moved to Advanced native choosers.
- Download location uses a folder picker and a move/use-without-moving decision.
- Format and contextual quality controls use menus backed by real Sockseek config values.
- Credentials are locked by default and expose Cancel, Done, and reveal controls only in Edit mode.
- Post-fix evidence: `/private/tmp/seeksync-settings-qa/comparison-settings-source-vs-implementation.png`.
- No new P0/P1/P2 issue is visible at the compact Settings viewport.

## Implementation checklist

- [x] Preserve the native SeekSync visual language.
- [x] Reorder sections around user tasks.
- [x] Hide automatically managed paths behind Advanced controls.
- [x] Use a standard downloads-folder chooser.
- [x] Offer move, use without moving, and cancel decisions without overwriting conflicts.
- [x] Add format and bitrate menus backed by Sockseek config.
- [x] Lock credentials behind Edit and provide explicit reveal controls.
- [x] Add config, migration, and library-move regression coverage.

## Follow-up polish

- [P3] Repeat keyboard, VoiceOver, and native click-through QA after the Mac is unlocked.

final result: passed
