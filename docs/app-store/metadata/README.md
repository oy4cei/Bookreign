# Bookreign App Store metadata — first release 1.0.0

Prepared 2 October 2026 from the current app and renamed to Bookreign on 4 October 2026, for entry in App Store Connect. These local files do not establish upload or submission status; see `../README.md` for release status. `ru`, `uk` and `en` contain plain UTF-8 text; select Russian, Ukrainian and the intended English localization in App Store Connect. Choose the primary language when creating the app record.

Each locale contains:

- `name.txt` — Bookreign in every locale, matching the interface. App Store Connect must confirm that the name can be registered.
- `subtitle.txt` — subtitle.
- `keywords.txt` — comma-separated search terms, no invented brand or competitor terms.
- `promo.txt` — promotional text.
- `description.txt` — product description.
- `reviewnotes.txt` — suggested reviewer instructions. App Review notes are one field, not three simultaneous localizations; use English by default. Fill the separate reviewer contact fields with real details.
- `versionnotes.txt` — prepared first-release copy for announcement/reference. **Do not paste into What's New for the initial 1.0.0 submission:** Apple does not expose that field for the first version. Rewrite it to describe actual changes for a subsequent release.

Text files end with one newline for editing; trim that final newline when pasting. All other spaces and newlines count toward limits. `validate.py` checks Unicode code-point counts and UTF-8 bytes (the current text uses no emoji or combining sequences). App Store Connect remains the final validator.

| Field | Apple limit | en | ru | uk |
| --- | --- | ---: | ---: | ---: |
| Name | 30 characters | 9 | 9 | 9 |
| Subtitle | 30 characters | 29 | 24 | 23 |
| Keywords | 100 bytes | 76 | 76 | 82 |
| Promotional text | 170 characters | 141 | 153 | 146 |
| Description | 4,000 characters | 2,118 | 2,191 | 2,255 |
| Review notes | 4,000 bytes | 1,849 | 2,879 | 2,956 |
| Release copy | 4,000 characters when What's New applies | 299 | 320 | 334 |

Run from the repository root:

```sh
python3 docs/app-store/metadata/validate.py
```

Apple's current [platform-version reference](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/) specifies text/byte limits, reviewer fields, contact requirements and the initial-version exception. Its [app-information reference](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/) specifies name/subtitle limits and the privacy-policy URL requirement. Checked 2 October 2026.

The metadata describes the catalog as dependent on external providers and does not promise full coverage, photo-based visual identification, cloud synchronization, reminders, ebook reading or CSV import. No App Privacy questionnaire answer is certified by this text; see the release privacy assessment and the unconfirmed inputs in `../web/PUBLISHING.md`.
