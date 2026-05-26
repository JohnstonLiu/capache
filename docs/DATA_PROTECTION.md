# Data Protection Model

Capache uses a standard recoverable sync protection model today, with room for an Advanced Protection mode later.

## Current State

- Local use does not require login.
- Sync is opt-in.
- Supabase email OTP is used for authentication.
- Supabase row-level security restricts each signed-in user to their own synced rows.
- Local notes are stored in a file-backed shared store, with app-group `UserDefaults` retained as a widget and migration cache.
- Standard Protection is implemented for synced notes and note history. The app encrypts note titles, rich text data, plain text, and history snapshots before upload using AES-GCM.
- Standard Protection uses a recoverable per-account sync key stored in Supabase. This means synced payloads are not stored as plaintext note rows, but the mode is not zero-knowledge because an operator with sufficient backend access can retrieve the key and decrypt synced note payloads.
- Some sync metadata remains unencrypted, including timestamps, pin/archive/conflict status, folder IDs, content hashes, and folder names.
- iOS widget background refresh uses Apple WidgetKit push tokens and a random widget refresh token. Supabase stores only the refresh token hash. The widget snapshot endpoint returns encrypted note rows; note content is decrypted in the widget extension on the device.
- Users can export local notes, folders, and note history as JSON.
- Signed-in users can delete their synced Supabase notes, folders, note history, sync key, and related metadata without deleting local device data.

## Target Model

### Standard Protection

Standard Protection is the current and default sync mode.

- Notes are encrypted in transit.
- Note title/body/history payloads are encrypted by the app before upload.
- Data is also protected by backend database controls, Supabase Auth, and row-level security.
- Capache can recover/decrypt synced data for the user after normal account login.
- This mode supports account recovery and simpler multi-device setup.
- This mode is not zero-knowledge because the backend stores the recoverable sync key.

### Advanced Protection

Advanced Protection is the optional stronger mode.

- Note content is encrypted on the user's trusted device before upload.
- Decryption keys stay on trusted user devices or in user-controlled recovery material.
- The backend stores encrypted blobs and metadata needed for sync.
- Capache cannot recover note content if the user loses all trusted devices and recovery material.
- Users must see a clear warning before enabling this mode.

## Implementation Requirements

- Add a per-account protection mode setting before enabling Advanced Protection.
- Encrypted payload columns exist for Standard Protection.
- Keep the Standard Protection migration backward-compatible with existing plaintext remote rows.
- Decide which metadata remains visible in Advanced Protection. Prefer encrypting note title, note body, note history, and folder names.
- Use platform key storage for local keys: Keychain on iOS and macOS.
- Add a richer recovery/admin flow for Standard Protection if needed; current recovery comes from the server-stored per-account sync key.
- Add trusted-device or recovery-key flow for Advanced Protection.
- Add migration from Standard Protection to Advanced Protection.
- Keep tests that verify synced note body/title data is not stored as plaintext in Standard Protection payloads.
- Keep local storage migrations backward-compatible so updates never require app reinstall.

## Operational Requirements

- The app must ship only the Supabase URL and publishable key.
- Service-role keys, database passwords, Apple certificates, and notarization credentials must stay out of the app and repository.
- The `delete-user` Edge Function must be deployed before exposing full account deletion in production.
- Supabase migrations must be applied in filename order before shipping a sync-enabled build.
- Widget background refresh requires the widget refresh migration, the widget Edge Functions, APNs secrets, and the Push Notifications capability on the widget extension target.
- If migrations are applied manually through the SQL editor, the CLI migration history may not reflect production state. Repair migration history only after verifying the live schema.

## User-Facing Copy Requirements

Standard Protection:

> Your notes are protected in transit and on our servers. Account recovery is available.

Advanced Protection:

> Your notes are encrypted before they leave your device. Capache cannot recover your notes if you lose your trusted devices or recovery key.

## Not Yet Done

- End-to-end encryption is not implemented.
- Recovery-key UX is not implemented.
- Advanced Protection tests are not implemented.
- Folder-name encryption is not implemented.
