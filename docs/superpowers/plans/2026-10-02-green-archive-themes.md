# Green Binding / Night Archive implementation

Approved by the user on 2026-10-02: use `docs/design/2026-10-02-green-archive/02-green-binding.png` for light appearance and `03-night-archive.png` for dark appearance.

- Light: paper #F1EBDD, green chrome/actions #1C4036, dark text #201F1A.
- Dark: background #102C25, panels #1C4036, ivory text/actions #F1EBDD, sage secondary text #BCCAC0.
- Serif headings, restrained borders, 6–8 pt corners, native accessible navigation, original cover colors.
- Preserve localization, existing preference keys, all data and ISBN/cover/loan workflows. Keep current app name until a replacement is approved.

## Work

1. Introduce semantic colors, primary/secondary button styles, screen chrome, and form row styling.
2. Apply green header, paper/deep-green content, serif titles, search and layout controls, ruled grid/list, and full-width scan action to Library.
3. Apply the same system to scanner, confirmation, editors, settings, places, topics and loans.
4. Update meaningful UI checks for live light/dark/system switching and capture actual iPhone/iPad screenshots. Run the localization audit and regression suite.
5. Review changes and record validation. Existing build-8 App Store artifacts remain historical and must not be represented as containing this redesign.

Shared view API: `Color.paper`, `forest`, `forestFill`, `archiveText`, `archiveSecondary`, `archiveSurface`, `archiveRule`, `archiveHeader`, `archiveOnHeader`, `archiveActionText`; `.archiveScreen()`; `.archiveRow()`; `ArchivePrimaryButtonStyle()`; `ArchiveSecondaryButtonStyle()`; `ArchivePageHeader(title:subtitle:)`.

Default preference labels and keys remain compatible: Light selects Green Binding, Dark selects Night Archive, System follows the device. No network or data model changes are required.

## Completion — 2026-10-02

All five implementation steps are complete in 1.0.0 (9). The final design uses opaque archive navigation and a persistent custom tab strip because the native floating bar obscured the intended palette. Existing theme/language preferences and data formats are retained.

Validation: 15 iPhone scenarios have successful results across the full run (13/15) and targeted follow-ups after correcting stale/offscreen test interactions. Both iPad theme/accessibility scenarios passed. The localization audit reports 345 keys and zero errors. Actual captures and detailed results are recorded in `docs/design/2026-10-02-green-archive/implementation.json`.

The signed build was installed over 0.4.0 (7) on the connected iPhone. Version 1.0.0 (9) was read back successfully. A pre-install backup and post-install read-only copy have identical database bytes and payload; all 4 editions, 4 copies and 2 locations remain. Automatic launch was blocked because the phone was locked, so physical launch/camera behavior is not claimed as verified.

The App Store build-8 archive and IPA were not replaced or uploaded.
