# Capache Privacy Policy

Effective date: 2026-05-25

This privacy policy applies to Capache, a notes app created by Johnston Liu.

## Summary

Capache can be used without an account. Notes stay on your device unless you choose to sign in and enable sync. Sync uses Supabase so your notes can be available on your devices. Capache does not sell personal information and does not use note content for advertising.

## Information Capache Handles

When you use Capache without signing in, your notes, note titles, folder names, note history, and app settings are stored locally on your device.

When you sign in and enable sync, Capache uses your email address for authentication. Supabase also creates an account identifier used for authorization and row-level security.

Synced note titles, note text, rich text data, and note history snapshots are encrypted by the app before upload and stored in Supabase so they can sync across devices. Capache also stores a recoverable per-account sync key in Supabase so synced notes can be decrypted after normal login.

Some sync data is not encrypted as note payload content. Folder names, folder IDs, pinned/archive status, conflict status, content hashes, timestamps, account identifiers, widget push tokens, widget refresh token hashes, widget push and snapshot diagnostics, and other sync metadata are stored in Supabase to provide organization, syncing, widgets, conflict handling, and account deletion.

Capache does not collect precise location, contacts, photos, camera data, microphone data, health data, payment information, advertising identifiers, or browsing history.

Capache does not include first-party analytics or advertising tracking code.

## Sources of Information

Capache receives information directly from you when you create notes, folders, account sign-in requests, exports, support emails, or deletion requests.

Capache also receives technical account and sync information from Supabase when sync is enabled, such as authentication identifiers, session state, database records, and realtime change notifications needed to provide sync.

## How Information Is Used

Capache uses local note data to provide note editing, organization, search, widgets, export, and history.

If sync is enabled, Capache uses your email address to authenticate your account and uses synced note data to keep your devices up to date. Supabase Realtime may be used as a change notification trigger so the app knows when to refresh synced data. Realtime Presence may also be used to show when the same note is open in another app session; the presence payload uses a random session device ID, platform label, note ID, and open timestamp. If you use iOS widgets, Capache may use Apple Push Notification service widget push tokens so WidgetKit can refresh the widget after synced changes. Widget refresh requests return encrypted note data, and the widget decrypts it on the device using the sync key already available to the app group.

If simultaneous edits happen on multiple devices, Capache uses last-writer-wins sync and may preserve overwritten note bodies in note history so older content can be recovered.

Capache may use account and support information to respond to support requests, process deletion requests, prevent abuse, maintain security, debug sync problems, and comply with legal obligations.

## Sync Is Optional

Signing in is not required to use Capache. Sync is an opt-in feature. Notes created while sync is off remain local unless you later enable sync, at which point local notes may be uploaded to Supabase so they can sync. You can also mark individual notes as Local Only so they are not uploaded for sync.

You can turn sync off. Turning sync off stops future sync activity on that device but does not automatically delete synced data already stored in Supabase. If you mark a previously synced note as Local Only, Capache deletes that note's synced cloud copy and keeps the local copy on that device. If you are signed in, you can also delete synced cloud data from the app while keeping local notes on the device.

## Sharing and Disclosure

Capache does not sell personal information. Capache does not share personal information for cross-context behavioral advertising.

Capache shares information with service providers only as needed to operate the app:

- Supabase provides optional authentication, database storage, Edge Functions, and sync infrastructure.
- GitHub may host source code, release downloads, and project materials.
- Apple may process information related to app installation, platform services, crash reports, App Store distribution, TestFlight, or Developer Program services according to Apple's own terms and privacy policies.

Capache may disclose information if required by law, legal process, security investigation, abuse prevention, or to protect the rights and safety of users or the service.

## Third-Party Service Providers

Capache currently uses Supabase for optional authentication, database storage, Edge Functions, and sync. Supabase stores synced account and note data on Capache's behalf. If Capache changes service providers in the future, this policy will be updated before the change affects synced user data.

Mac builds may be distributed through GitHub Releases. GitHub is used for software distribution and project hosting, not for note sync storage.

Capache does not embed database passwords, service-role keys, or backend-only secrets in the app.

## Retention

Local notes remain on your device until you delete them, remove local app data, or uninstall the app. Local notes may remain in device backups depending on your device backup settings.

Synced notes, folders, note history, sync keys, widget push tokens, widget refresh token hashes, widget push and snapshot diagnostics, and sync metadata are retained in Supabase while sync is enabled or while your synced account exists. Deleting synced cloud data or deleting your account removes active synced records from Capache's Supabase tables, subject to provider backups, logs, legal obligations, and operational retention.

Support emails and privacy requests may be retained as needed to respond to you, maintain records of the request, prevent abuse, and comply with legal obligations.

## Security

Capache uses transport encryption when communicating with Supabase. Supabase Auth and Postgres row-level security are used so signed-in users can access only their own synced records.

Capache supports standard recoverable sync. Note titles, note bodies, rich text data, and note history snapshots are encrypted before upload using AES-GCM and a per-account sync key stored with the account so data can be recovered after normal login. This is not end-to-end encryption because Capache's backend can technically recover the key and decrypt synced note data. End-to-end encrypted sync is planned as a possible future Advanced Protection mode.

Local notes are stored in the app's local storage and may be included in device backups depending on your device backup settings.

No system can guarantee absolute security. You should keep device passcodes, Apple ID access, email account access, and Capache sign-in codes secure.

## Data Deletion

You can export local notes, folders, and note history from the app.

You can delete local notes in the app or uninstall the app to remove local app data from a device.

If you are signed in, you can delete synced cloud notes, folders, note history, sync keys, and related sync metadata from the app. If the account deletion server function is deployed, you can also request deletion of your synced account from the app after verifying a fresh email code. To request deletion of your authentication account record or any remaining account data manually, contact Johnston Liu at johnstonliu2004@gmail.com.

Deleted synced data may remain temporarily in provider backups, logs, or security records where required for operations, legal compliance, or abuse prevention.

## Privacy Rights

Depending on where you live, you may have rights to request access, deletion, correction, portability, restriction, or objection related to personal information. You may also have a right to withdraw consent where processing is based on consent.

To make a privacy request, contact Johnston Liu at johnstonliu2004@gmail.com and include the email address used for Capache sync. Capache may need to verify your request before acting on account data.

California residents may have rights to know, delete, correct, limit certain uses of sensitive personal information, opt out of sale or sharing, and not be discriminated against for exercising privacy rights. Capache does not sell personal information or share personal information for cross-context behavioral advertising.

Users in the European Economic Area, United Kingdom, or similar jurisdictions may have data protection rights under applicable law. Where applicable, Capache processes personal information to provide requested app functionality and sync, comply with legal obligations, protect legitimate security and operational interests, and honor consent where consent is required.

## International Processing

Capache is operated from the United States. Supabase, GitHub, Apple, and other infrastructure providers may process information in the United States and other countries. Privacy laws in those places may differ from the laws where you live.

## Children

Capache is not intended for children under 13. If you believe a child provided personal information through Capache, contact Johnston Liu at johnstonliu2004@gmail.com.

## Changes

This policy may be updated as Capache changes. The effective date will be updated when the policy changes.

## Contact

Johnston Liu
johnstonliu2004@gmail.com
