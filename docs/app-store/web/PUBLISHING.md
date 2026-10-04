# Local support and privacy page drafts

These are static, responsive HTML files for a future public Support URL and Privacy Policy URL. They have not been hosted or submitted. No domain, email address, developer identity or policy effective date has been invented. The visible draft/contact notices and `noindex` make their current status explicit.

## Files

- `index.html` — language chooser.
- `support-uk.html`, `support-en.html`, `support-ru.html` — localized support and FAQs.
- `privacy-uk.html`, `privacy-en.html`, `privacy-ru.html` — localized privacy notices.
- `styles.css` — shared responsive light/dark stylesheet, system fonts, no external assets or script.
- `publication-inputs.json` — unresolved publication inputs; null means not supplied, not an empty approved value.

Preview locally from the repository root:

```sh
python3 -m http.server 8788 --directory docs/app-store/web
```

Then open the local server's `/index.html`. A local preview is not a Support URL suitable for App Store Connect.

## Complete before hosting

1. Confirm the developer/publisher's legal identity and copyright holder. Add the identity to all six content pages and any legal details that apply to that publisher.
2. Supply a real public support email or other working contact and a privacy contact (they may be the same). Replace every `data-contact-pending` block with that contact, retaining useful support instructions. Confirm how voluntarily submitted support messages are used, who receives them, and their retention period; add that practice to every privacy page. Do not claim support messages are never collected.
3. Supply the actual HTTPS host/domain and verify its logging, analytics and retention settings. Update the website-processing section in every privacy page with the confirmed provider/practices. The current local files have no analytics/cookies/scripts, but hosting itself can create request logs.
4. Confirm an effective date, complete the privacy assessment for the release and remove `data-publication-pending` banners when the text is accurate. Remove `noindex` if indexing is desired. `Prepared 2 October 2026` is a preparation date, not a legal effective date.
5. Upload the HTML and stylesheet together, preserving relative filenames. Confirm all six pages work over public HTTPS without authentication and at a narrow mobile viewport. Check language links and actual contact links. Paste the chosen locale-specific URLs into App Store Connect only after they exist.
6. Keep `App/PrivacyPolicyView.swift` and `App/Localization/Privacy.json` consistent with policy changes. The native notice currently opens offline; it does not pretend that a hosted URL or contact exists.

## Facts and remaining assessment

App behavior was checked against `README.md`, `App/SettingsView.swift`, `App/AddBookView.swift`, `App/CoverEditor.swift`, `App/Design.swift`, `Sources/BookCatalog/BookCatalog.swift`, `Sources/BookCatalog/MBooksCatalog.swift`, `Sources/BookCatalog/CoverSearch.swift` and the library models.

The app stores the library in local SQLite, uses local preferences/scan queue, has no account system or built-in advertising/usage analytics, processes photo OCR with Apple Vision on the device, and has no developer-operated library-upload endpoint in the reviewed code. This does not mean no data leaves the device. ISBN/text search, cover display/import and browser search send requests to external services. User-selected file providers and system backups can also receive copies.

The privacy notices explicitly cover ISBN/query requests to Open Library and `api.mbooks.com.ua`, automatic remote cover loading (including `covers.openlibrary.org` and catalog-provided hosts), Google image search opened by the user, direct user-specified HTTPS image imports and redirects, local borrowers/photos/notes, exports, retention/deletion and offline use. Image hosts are data-dependent and are not an exhaustive fixed allowlist.

**App Privacy is not finalized.** Before choosing its labels, determine the relevant third parties' collection and retention for the actual API/cover requests. Apple's [App Privacy guidance](https://developer.apple.com/app-store/app-privacy-details/) bases collection on access beyond the time needed to serve a request, including relevant partners. No SDK analytics does not by itself establish “Data Not Collected.” MEGOGO BOOKS' [published privacy policy](https://mbooks.com.ua/about/polityka-obrobky-personalnykh-danykh/) discusses search history and variable retention but does not establish anonymous API-request retention for this app. The pages do not certify a retention duration or completed questionnaire.

The [Apple Support URL requirement](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/) calls for actual contact details; the unresolved contact notices are release blockers, not publishable substitutes. Apple also requires a [privacy-policy URL](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/). Sources checked 2 October 2026.

No screenshots, book covers or other third-party creative assets are included in these web pages. Screenshots for the listing still require rights-cleared content and release-build verification in the wider submission workflow.
