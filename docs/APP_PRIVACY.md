# App Privacy Details

Use this as the working source for App Store Connect privacy answers and privacy manifest review. Legal review is still required before publishing.

## Tracking

- Tracking: No.
- Third-party advertising: No.
- Data broker sharing: No.

## Data Not Collected Unless Sync Is Enabled

Capache can be used fully offline without an account. Local-only notes are stored on the user's device and are not collected by Capache.

## Data Collected When Sync Is Enabled

Email address:

- Purpose: App functionality, account authentication, sync.
- Linked to user: Yes.
- Tracking: No.

User content, including notes, note titles, folder names, rich text data, note history, pinned/archive status, and timestamps:

- Purpose: App functionality, sync across devices.
- Linked to user: Yes.
- Tracking: No.
- Notes, note titles, rich text data, and note history payloads are encrypted by the app before upload in Standard Protection. Folder names and sync metadata are not fully encrypted payload content.

User ID/auth identifier:

- Purpose: App functionality, authorization, row-level security.
- Linked to user: Yes.
- Tracking: No.

Device/widget tokens:

- Purpose: App functionality, background widget refresh for synced notes.
- Linked to user: Yes.
- Tracking: No.
- Apple WidgetKit push tokens and widget refresh token hashes are used only to refresh widgets after synced note changes.

## Data Not Collected

Capache does not collect precise location, contacts, photos, camera data, microphone data, health data, payment information, advertising identifiers, browsing history, or diagnostics/analytics data through first-party code.

## Required Reason APIs

The main app and widget extension use `UserDefaults` for local app settings, app-group widget compatibility, and migration/cache storage. The privacy manifests declare `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1`.

Apple documentation says apps and third-party SDKs that use required reason APIs should declare those categories and reasons in `PrivacyInfo.xcprivacy`.

Reference: https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api
