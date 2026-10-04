# Scan confirmation and cover selection implementation plan

> **For agentic workers:** Use the existing flow and the assigned file boundaries; verify behavior before claiming completion.

**Goal:** Add opens the scanner; a valid ISBN immediately searches and presents a cover with explicit confirmation. Missing covers can be supplied from internet search, an image URL, camera or Photos.

**Architecture:** Keep the existing catalog lookup, Ukrainian preference and SQLite model. Add a single-book scanner entry and compact confirmation within AddBookView. Reuse a cover-only picker for draft and saved editions; imported image bytes remain local in existing coverData.

**Tech Stack:** SwiftUI, AVFoundation, PhotosUI, Foundation, existing LibraryCore/BookCatalog. iOS 17 minimum; no new dependencies.

**Spec:** User request in this conversation on 2026-10-01 and the in-chat flow description.

## Constraints and review focus
- Preserve ru/uk/en localization, theme, existing genres and signing settings.
- No automatic save on scan; cancellation never inserts an edition/copy.
- Pause camera when looking up/reviewing; ignore duplicate callbacks while transitioning.
- Failed/not-found/offline lookup permits retry/manual entry and retains queued ISBN.
- Single-book confirmation must not unexpectedly process an older batch queue.
- Alternative covers change only cover fields; invalid images/cancel/failure keep existing cover.
- Async results cannot update another edition after navigation or language variant changes.
- Simulator tests only; never reset a physical phone's library.

## Tasks
- [x] UI regression tests: default scanner, explicit confirmation, cancellation, Ukrainian variants, retained batch/manual flows; cover import persistence and failure preservation.
- [x] AddBookView: scanner first, large cover confirmation, visible fixed Confirm button, editable details and location, alternate add methods and batch entry.
- [x] CoverEditor: reusable cover picker with online catalog choices, preview before apply, HTTPS URL import, camera, photo library, cancellation and localized errors; pure URL/filter tests.
- [x] Integrate reusable cover picker in saved-book details, localize new flows, bump to 0.4.0 (7) preserving team.
- [x] Run pure suite and relevant simulator UI suite, inspect rendered screens, review async/state handling, update verification notes.
- [ ] If user's previously connected iPhone remains available, install and launch verified build without reset arguments.

## Progress
- Existing app inspected. Normal scheme contains no reset launch arguments. App target signing team already configured; do not regenerate project.
- Implementation and test work split by files between root and two agents.

- Pure verification: 88 tests passed (38 LibraryCore + 50 BookCatalog). Localization: 325 keys, 7 resources, 0 errors.
- First scanner regression failed on old menu as expected. Full UI run passed 9/12; targeted reruns passed the other three after fixing cover sheet height, batch scanner keyboard layout, form offset on editing transition, and test field/scroll/accessibility assumptions. All 12 unique scenarios now have passing results; final fallback rerun: 1/1, no failures or runtime warnings. Manual loan/relaunch and scanner Enter repeated on final app code and passed.
- Read-only review identified retained OCR photo when switching to another ISBN. Scanner entry now resets abandoned photo/OCR state. Cover ownership/cancellation/HTTPS review found no additional blocker.
- 0.4.0 (7) installed successfully on the physical iPhone without uninstall/reset; installed version verified. Launch was blocked by the locked screen. Phone then became unavailable before the final manual-form scroll fix could be installed. Latest generic iOS signed build succeeded and is ready at `/private/tmp/polka-phone-install/Build/Products/Debug-iphoneos/Polka.app`; pending reconnect/unlock requested from user.
- Visual evidence saved in `docs/screenshots/scan-confirmation.png` and `docs/screenshots/alternative-cover-saved.png`; full verification notes in `docs/verification.md`.
