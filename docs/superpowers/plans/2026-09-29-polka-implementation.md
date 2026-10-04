# План реализации Полки

**Goal:** runnable native iPhone/iPad MVP for multilingual physical book inventory.
**Architecture:** SwiftUI app + Foundation LibraryCore (SQLite, models, backup/search) + BookCatalog (HTTP providers, ISBN validation). AVFoundation/Vision isolate camera and recognition from inventory persistence.
**Tech stack:** Swift 6, SwiftUI, SQLite3, AVFoundation, Vision, PhotosUI; no external packages or API secrets.
**Spec:** ../specs/2026-09-29-polka-design.md

**Global constraints:** preserve original Unicode; separate edition and copy; loans retain home location; commit persistence before publishing UI changes; backup restore validates all references before overwriting; offline manual entry always available. No silent data reset on database failure.
**Review focus:** matching exact editions, duplicate handling, restore safety, camera permission/fallback, cancellation and stale catalog results, persistence failures.

## Tasks

1. LibraryCore: Codable models and normalized search, snapshot invariants, SQLite transactions, versioned backup and CSV. Write meaningful tests first, run RED then GREEN. Owned by core agent.
2. BookCatalog: valid ISBN10/13 parsing; Open Library exact ISBN and text search; distinguish errors from no results; original metadata and optional fields. Network parsing fixture tests first. Owned by catalog agent.
3. Camera/OCR: barcode capture view and photo recognition; permissions, visible errors, editable recognition; serial queue and duplicate throttle. Owned by scanning agent.
4. App shell and flows: root store, library/search/filters/grid/list, detail/copies/edit, locations and batch move, loans/returns, scanner queue/add, settings backup/import/export/undo. Owned by root.
5. Xcode project: iOS17+, camera usage declaration, local package, shared scheme, no third party runtime dependencies. Owned by root.
6. Verify: swift test, unsigned simulator build, launch and review on iPhone/iPad; exercise add/loan/return/persistence and record remaining hardware-only checks. Independent code review and fixes before handoff.

## Progress

- [x] Specification and implementation boundaries recorded after user approval.
- [x] Core and catalog tests pass (21 total).
- [x] All MVP flows implemented.
- [x] Simulator build and UI verification (2 end-to-end tests passed; iPhone/iPad screenshots inspected).
- [x] Review completed, five findings fixed and re-reviewed, README and verification report written.
