# App Store Submission Brief

## Build

- Version: 2.0.0
- Build: 2
- Bundle ID: `me.johnstonliu.cache`
- SKU suggestion: `capache-ios`
- Primary category suggestion: Productivity
- Age rating baseline: 4+, assuming no user-generated public sharing, web access, gambling, medical, or commerce features are added.

## What to Test Before Submission

- Fresh install opens to the notes list without requiring login.
- Local note creation, editing, deletion, history, folders, subfolders, pinning, archive, search, and export.
- Optional email-code login for sync.
- Per-note Local Only behavior.
- Multi-device sync on a real iPhone and Mac.
- Widget note selection and WidgetKit background refresh after a remote synced edit.
- Delete synced cloud data keeps local notes.
- Full account deletion requires fresh email-code verification and signs the user out.
- App update from the last public build preserves local notes.

## App Review Notes

Capache is a local-first notes app. Login is optional and is used only for syncing notes across devices. The app can be fully tested without creating an account by launching it, creating notes, creating folders, using note history, and adding the widget.

If the reviewer wants to test sync, tap the sync/account control, enter an email address, and use the one-time code sent by Supabase. No password is required. Account deletion is available in the signed-in account settings and requires a fresh email-code verification before deleting the hosted Supabase account and synced cloud data.

The app does not include ads, tracking, public sharing, payments, or first-party analytics. Synced note title/body/history payloads use recoverable standard encryption before upload. This is not end-to-end encryption because the recoverable per-account sync key is stored with the account to support normal account recovery.

## Promotional Text

Local-first notes with optional sync, folders, widgets, note history, and per-note Local Only controls.

## Description

Capache is a native notes app for iPhone, iPad, widgets, and Mac. It works without an account, keeps local notes on your device, and offers optional email-code sync when you want notes available across devices.

Use Capache to quickly write notes, organize them into folders and subfolders, pin important notes, archive older notes, recover previous versions from note history, and show selected note text in an iOS widget.

Sync is opt-in. Individual notes can be marked Local Only so they stay off cloud sync. Synced note title, body, rich text, and history payloads are encrypted before upload using recoverable standard protection.

## What's New in Version 2.0.0

- Optional Supabase sync with email-code login.
- Local-first use still works without an account.
- Folders, subfolders, pinned notes, archive, and search.
- Editable note titles while widgets continue showing note text only.
- Per-note Local Only controls.
- Note history and recovery for overwritten edits.
- Widget background refresh after synced note changes.
- Recoverable standard encryption for synced note title, body, and history payloads.
- Synced cloud-data deletion and full account deletion.
- Mac Catalyst support for outside-App-Store distribution.

## Keywords

notes, widget, folders, local, sync, markdown, productivity, writing, memo

## Support URL

https://gist.github.com/JohnstonLiu/82f1b56905b39dd01e966ab554f31a6e

## Privacy Policy URL

https://gist.github.com/JohnstonLiu/40defa3411dd1844e9ed86c7a0221677

## Terms URL

https://gist.github.com/JohnstonLiu/d7b2692140bb605d23ae87a6259f98b9

## App Privacy Answers

- Tracking: No.
- Data used to track users: None.
- Data linked to the user when sync is enabled: email address, user ID/account identifier, user content, widget push tokens, widget refresh token hashes, and sync metadata.
- Data not collected when sync is disabled: account email, hosted sync records, and hosted note content.
- User content purpose: App Functionality.
- Email purpose: App Functionality.
- User ID purpose: App Functionality.
- Diagnostics/analytics: No first-party analytics or diagnostics collection in the app code.

Use `docs/APP_PRIVACY.md` as the detailed source when filling App Store Connect's privacy questionnaire.

## Export Compliance Notes

Capache uses standard Apple platform cryptography, TLS, Supabase Auth transport security, CryptoKit AES-GCM for app-encrypted synced note payloads, and WidgetKit/APNs platform security.

Expected App Store Connect posture: declare that the app uses encryption, then answer under Apple's exempt/common-use path if available for standard encryption used for authentication, secure communications, and user-data protection. Final answers must be entered in App Store Connect by the account holder.

## Manual App Store Connect Actions

- In Apple Developer, verify both app identifiers are configured for production signing:
  - `me.johnstonliu.cache`
  - `me.johnstonliu.cache.cacheWidgetExtension`
- Enable Push Notifications on the widget extension identifier so its App Store provisioning profile includes the `aps-environment` entitlement.
- Install or create an iOS Distribution certificate on the release machine, or configure an App Store Connect API key for CI signing.
- Create or update the App Store Connect app record.
- Upload screenshots for iPhone and iPad.
- Enter description, keywords, support URL, privacy policy URL, copyright, category, and review notes.
- Complete App Privacy based on `docs/APP_PRIVACY.md`.
- Complete export compliance.
- Archive and upload the signed iOS build to TestFlight.
- Install the TestFlight build on a physical iPhone and run the smoke test above.
- Submit for App Review after TestFlight smoke passes.

## Local Release Verification

The repo includes `ci/ExportOptions-AppStore.plist` for App Store/TestFlight exports. A local Release archive can be created with:

```sh
xcodebuild archive \
  -project cache.xcodeproj \
  -scheme cache \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$PWD/build/Capache-2.0.0.xcarchive" \
  -allowProvisioningUpdates
```

Export for App Store Connect with:

```sh
xcodebuild -exportArchive \
  -archivePath "$PWD/build/Capache-2.0.0.xcarchive" \
  -exportOptionsPlist ci/ExportOptions-AppStore.plist \
  -exportPath "$PWD/build/AppStoreExport" \
  -allowProvisioningUpdates
```
