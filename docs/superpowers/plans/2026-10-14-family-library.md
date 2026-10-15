# Family Library Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans for continuous inline execution; check each completed step.

**Goal:** Ship Bookreign family sharing of the entire library through private iCloud invitations, with safe offline storage and the approved Regent icon.

**Architecture:** Keep SQLite and the domain snapshot. Add a field-stamped, tombstone-preserving shared envelope, bounded compressed CloudKit assets, and a durable local synchronization state saved in the same SQLite transaction as the visible snapshot. CloudKit private/shared databases enforce membership; every asynchronous result is bound to the original account and library session.

**Tech Stack:** Swift 6 package, SwiftUI/iOS 17, SQLite, CryptoKit, Compression, CloudKit, UICloudSharingController.

**Spec:** docs/superpowers/specs/2026-10-13-family-library-design.md

## Global Constraints

- Share the entire library, including notes, loans and custom cover photos; consent before enabling or merging.
- No Bookreign account/password. Private CKShare only; publicPermission = none.
- Bundle com.bookslibrary.polka; team 97W729H996; container iCloud.com.bookslibrary.polka.
- Ukrainian, Russian, English UI; iPhone and iPad; iOS 17 minimum.
- Deterministic latest field edit wins; permanent deletion tombstones prevent stale resurrection.
- Never replace a good local database with corrupt, unsupported or incomplete cloud data.
- Owner creates a private custom zone; invited users use shared database; database subscriptions are hints.
- Upload is authorized. Do not claim real two-account device testing unless performed.

## Review Focus

1. Account changes and late network completions must never write a former account's data to another account.
2. Concurrent edits, deletions, location references and two loans for one copy must converge or preserve the last valid snapshot, never silently drop pending work.
3. Corrupt/oversized assets and backup imports must be bounded before allocation/decompression and leave SQLite untouched.
4. Revoked/read-only access must block all app write paths, including forms already open, undo and restore.
5. Closing the app during initial activation, invitation acceptance or upload must preserve local books and recover an idempotent pending operation.

## Task 1: Snapshot merge and bounded wire format

**Files:** Sources/LibraryCore/FamilyEnvelope.swift; FamilyAssetCodec.swift; Tests/LibraryCoreTests/FamilyEnvelopeTests.swift.
**Interfaces:** `FamilyEnvelope(snapshot:replicaID:date:)`, `applying(_:replicaID:counter:date:) -> FamilyEnvelope`, `merged(with:) -> FamilyEnvelope`, `snapshot() -> LibrarySnapshot`; `FamilyAssetCodec.encode/decode` uses Data. Edits compare Date, replica UUID, monotonic counter; assets carry version, SHA256 and bounded zlib bytes.

- [x] Write tests for independent field edits, newest edit, tie ordering, permanent deletion, cascade, deleted-but-referenced place, conflicting loans, unchanged IDs, malformed/version/checksum/size failures.
- [x] Run `swift test --filter FamilyEnvelopeTests`; expect missing-API failures before implementation.
- [x] Implement generic typed entity/field values and deterministic materialization with strict schema and domain validation. Reject ambiguous invalid merges rather than mutate local data.
- [x] Run focused tests, then package suite; expect zero failures.

## Task 2: Durable state and synchronization coordinator

**Files:** Sources/LibraryCore/FamilySyncState.swift; FamilySyncEngine.swift; LibraryDatabase.swift; Tests/LibraryCoreTests/FamilySyncTests.swift.
**Interfaces:** SQLite `loadFamilyState()`, `save(_:familyState:)`; `FamilySyncState` binds account ID, zone/owner/root IDs, role, envelope, local generation and acknowledged generation. Injectable `FamilyTransport` fetch/save/account functions; main-actor engine integrates persistence via closures.

- [x] Test state restart, atomic snapshot/state rollback, no clearing newer edits after acknowledgement, account mismatch, stale response, read-only and revoked membership, conflict retry, failed/quota writes retaining outbox.
- [x] Run `swift test --filter FamilySyncTests`; observe expected failure.
- [x] Add compatible SQLite auxiliary state table and transactional save; keep old databases readable and schema version guarded. Implement bounded retries and session/account guards.
- [x] Run tests and full suite; expect zero failures.

## Task 3: CloudKit adapter and invitation lifecycle

**Files:** App/Family/CloudKitFamilyTransport.swift; FamilySharingCoordinator.swift; FamilyAppDelegate.swift; FamilySharingController.swift; App/PolkaApp.swift; App/Family.entitlements; App/Info.plist; Polka.xcodeproj/project.pbxproj.
**Interfaces:** Transport from task 2; CKAsset codec from task 1; owner creates stable record and CKShare atomically; acceptance fetches/validates before switching; system sharing controller handles named members and rights.

- [x] Verify Apple SDK APIs and declare CloudKit, CKSharingSupported, scene share acceptance and background remote notifications.
- [x] Implement stable pending-create ID, account-bound callbacks, ephemeral protected staging files removed after completion, subscription setup for correct database, revoked access handling and cancellation.
- [x] Build simulator and device targets; expect successful compilation and signed entitlement verification. Test injectable transport lifecycle without live user data.

## Task 4: Store integration, safe join UI and localization

**Files:** App/LibraryStore.swift; App/Family/FamilySettingsView.swift; App/LibraryView.swift; App/SettingsView.swift; App/Localization.swift; App/Localization/Family.json; UITests/PolkaUITests.swift.
**Interfaces:** Store gates all mutation entry points; update produces local envelope diff and saves snapshot/state atomically. Family UI displays consent, status, retry, manage and stop. Invite choice offers merge (writer), export-then-switch (export success required), or cancel.

- [x] Verify access policy and nonempty-library joining with core integration tests; inspect central store mutation guards and undo invalidation in the independent code review.
- [x] Integrate owner activation, inviting, joining and foreground refresh. Disable destructive whole-library restore and undo of shared history; explain in UI, retain export. Central guards protect already-presented editors.
- [x] Translate all added UI/error strings into uk/en/ru and verify `python3 Scripts/check-localizations.py`.
- [x] Run simulator UI tests for family entry/consent/cancel, settings languages and existing library behavior; expect pass.

## Task 5: Privacy, icon and release configuration

**Files:** App/PrivacyPolicyView.swift; App/Localization/Privacy.json; docs/app-store/web/privacy-{uk,en,ru}.html; docs/app-store metadata; Scripts/check-release-artifact.py; Scripts/prepare-app-store.sh; approved existing icon/generator.

- [x] Incorporate source-backed data-safety findings before release. Bound backup reads; add regression tests for confirmed gaps.
- [x] Update privacy text with shared types, Apple account, owner quota, participant permissions, retained copies after revocation; no invented encryption claims.
- [x] Verify approved icon visually and dimensions; include existing pending artwork without redesign.
- [x] Inspect live App Store version/build and choose next valid release; update scripts to use actual version. Validate localization, metadata, tests and archive.

## Task 6: Final review, production setup and upload

- [x] Request one independent whole-change review focused on the five safety cases; fix important issues and verify regression tests.
- [x] Configure Apple CloudKit container/capabilities and production schema; verify provisioning includes iCloud and push entitlements.
- [x] Archive signed Release, verify iPhone/iPad, embedded version/icon/entitlements, export and upload to App Store Connect.
- [x] Read back processed build and validation status. Record any remaining physical two-Apple-ID verification honestly; do not release unverified schema/configuration.
- [x] Commit tested implementation/icon/docs on codex/family-library, preserve original local data and unrelated files. Report upload outcome with evidence and any concrete remaining blocker.

## Execution rulings

- The user's explicit instruction to implement and upload authorizes continuous execution; no additional design approval is needed.
- Native worktree was created but is outside writable roots. Continue on a separate branch in the authorized checkout after baseline review; preserve that worktree until no longer needed.
- Shared undo/whole-library restore are disabled to avoid resurrecting permanent tombstones or overwriting other members; export remains available. Restoring a backup belongs to local mode.
- A valid but mutually inconsistent merge pauses sync and retains both envelopes for retry/export; no invented return dates or silently discarded loans.

## Release result

Build 1.1.0 (13) delivered at 22:55 Kyiv time on 14 October 2026 and processed by Apple. Required metadata validation passed; the review draft is Ready for Review. Live two-account device testing remains explicitly outstanding, so final App Review submission was not performed. See docs/app-store/README.md and release-manifest-build13.json for evidence and the remaining test procedure.
