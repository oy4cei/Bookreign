# Published support and privacy pages

The Bookreign website is public at [oy4cei.github.io/Bookreign](https://oy4cei.github.io/Bookreign/), hosted on GitHub Pages with HTTPS enforced. Deployment was verified on 4 October 2026: all seven HTML pages and the stylesheet returned HTTP 200 and matched the local files byte for byte. The deployed commit is `b02b5311435bcdba0113f7e3695813a05492e232` on `gh-pages`, publishing from `/`.

The developer and public support/privacy contact, confirmed by the user, are **Ievgen Tsvietkov** and **oy4cei@gmail.com**. The privacy policy is effective 4 October 2026. Website publication does not mean the application has been released in the App Store.

## Public URLs

| Language | Support | Privacy policy |
| --- | --- | --- |
| Ukrainian | [Support](https://oy4cei.github.io/Bookreign/support-uk.html) | [Privacy](https://oy4cei.github.io/Bookreign/privacy-uk.html) |
| English | [Support](https://oy4cei.github.io/Bookreign/support-en.html) | [Privacy](https://oy4cei.github.io/Bookreign/privacy-en.html) |
| Russian | [Support](https://oy4cei.github.io/Bookreign/support-ru.html) | [Privacy](https://oy4cei.github.io/Bookreign/privacy-ru.html) |

The privacy-policy URLs were saved in App Store Connect for Ukrainian, English and Russian on 4 October 2026. Reloading confirmed that the Ukrainian URL persisted and all missing-URL banners disappeared. The localized Support URL fields were also saved for Ukrainian, English and Russian on 4 October 2026, with save success confirmed. The primary App Store category was saved as Books (Книги). The user-confirmed App Review contact details and English review notes were saved successfully on 4 October 2026; contact validation errors cleared. The phone number is stored only in App Store Connect and is not recorded in project files.

## Update and publish

Edit the seven HTML files or `styles.css` in `docs/app-store/web`. Keep contact details, language links and privacy disclosures consistent across locales. Preview from the repository root:

```sh
python3 -m http.server 8788 --directory docs/app-store/web
```

Check the updated pages, including a narrow mobile viewport, and publish from the repository root:

```sh
python3 Scripts/publish-website.py
```

The script uses the configured Git credentials and publishes only the seven HTML files, `styles.css` and `.nojekyll` to `origin/gh-pages`. It leaves `main`, the working tree and the normal staging area unchanged. It preserves the existing publishing history and never force-pushes; a concurrent update can reject the push and must be inspected before retrying. It exits without another commit when the website content is unchanged.

GitHub Pages must continue to use branch `gh-pages` and folder `/`. Wait for the Pages deployment to complete, then verify the public HTTPS pages and stylesheet against the local files. `PUBLISHING.md` and `publication-inputs.json` are project records and are not deployed by this script.

## Data handling and review status

The app stores the library in local SQLite and keeps preferences and the scanning queue on the device. OCR uses Apple Vision on the device. The reviewed code has no account system, built-in advertising or usage analytics, or developer-operated library-upload endpoint. Catalog searches, remote covers and browser searches send requests to external services; user-selected file providers and system backups can also receive copies.

The public notices describe the additional catalog through its actual privacy-policy link without adding its brand to the user-facing text. They also cover local borrowers/photos/notes, exports, deletion, direct HTTPS image imports and redirects. Image hosts depend on catalog results and user choices.

Support emails, including voluntarily attached files, are received by Ievgen Tsvietkov through Gmail to answer requests and provide support. They remain in the developer mailbox until deleted; deletion may be requested by email. Google’s own handling and retention follow its privacy policy. No fixed retention duration or automatic deletion deadline is asserted.

GitHub Pages records visitor IP addresses for security, as explained in [GitHub Pages documentation](https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages#data-collection). Hosting logs are governed by the [GitHub Privacy Statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement). The page files contain no analytics, scripts, advertising, remote images or third-party fonts.

The user completed App Privacy in App Store Connect; the observed interface shows the published “Data Not Collected” label. This records the user’s submitted choice, not an independent verification of all third-party collection or retention practices. The public pages do not certify external providers’ retention periods. Adding version 1.0.0 (12) for review passed validation and created a review draft with status Ready for Review (Готово к проверке). The final Submit for Review button remains unclicked: the app has not been submitted to App Review or publicly released.

`App/PrivacyPolicyView.swift` and `App/Localization/Privacy.json` provide the native offline notice. Future policy changes should keep its description of app behavior consistent with the website. No screenshots, book covers or other third-party creative assets are included in these web pages.
