# Capache Terms of Service

Effective date: 2026-05-25

These terms apply to Capache, a notes app created by Johnston Liu. They cover use of the released app and the optional hosted sync service. The source code license controls your rights to copy, modify, and distribute the source code.

## Acceptance

By using Capache, you agree to these terms. If you do not agree, do not use the app.

## Eligibility

Capache is not intended for children under 13. Do not use sync or create an account if you are under 13. If you use Capache on behalf of another person or organization, you represent that you have authority to do so.

## The Service

Capache lets you create, edit, organize, export, and optionally sync notes across supported Apple devices. You can use Capache without an account. Sync requires signing in and uses Supabase to store synced notes, folders, note history, account identifiers, sync keys, and related metadata.

Mac builds may be distributed outside the Mac App Store through GitHub Releases. You are responsible for installing releases only from trusted project links.

Capache may change, suspend, or discontinue features over time. If a change materially affects sync, privacy, or account deletion, the policy documents should be updated before public release of that change.

## Your Content

You keep ownership of notes and other content you create in Capache. You give Capache permission to store, process, transmit, and display your content only as needed to provide app functionality, including optional sync.

You are responsible for your content and for keeping your devices and account access secure.

Capache includes export features to help you keep your own backups. Capache is not a guaranteed backup or archival service.

Do not rely on Capache as the only copy of important information. Device loss, app bugs, accidental deletion, account deletion, provider outages, or sync conflicts may affect access to notes.

## Sync, Local Only Notes, and Encryption

Sync is optional. Notes stay local unless sync is enabled, except that notes already synced from another device may be cached locally after sign-in. Individual notes can be marked Local Only. Local Only notes are kept out of future sync uploads on that device, and switching a previously synced note to Local Only deletes that note's cloud copy while keeping the local copy.

Capache uses recoverable standard sync encryption for synced note titles, note bodies, rich text data, and note history snapshots. This protects synced note payloads from being stored as plaintext note rows, but it is not end-to-end encryption because the sync key is stored with the account in Supabase for recovery. Folder names and sync metadata may remain visible to the backend.

If sync conflicts occur, Capache generally uses last-writer-wins behavior and may preserve overwritten note bodies in note history. You are responsible for reviewing history and restoring earlier content if needed.

## Accounts

Sync accounts use email one-time-password authentication through Supabase. You are responsible for keeping access to your email account secure and for not sharing sign-in codes. Capache may disable or delete synced account data if required for security, abuse prevention, legal compliance, or service operation.

## Acceptable Use

Do not use Capache to:

- violate laws or regulations;
- infringe someone else's rights;
- attempt to access another user's account or data;
- disrupt, abuse, bypass authentication for, or overload Capache, Supabase, GitHub release distribution, or related infrastructure;
- upload malicious code or content intended to harm other systems.

These acceptable-use rules do not limit rights granted by the open-source license for the source code.

## Third-Party Services

Capache uses third-party cloud service providers for optional sync, authentication, project hosting, and Mac app distribution, including Supabase and GitHub. Third-party services may have their own terms and policies. Capache is not responsible for third-party outages, account actions, or infrastructure changes outside Capache's control.

## Sync and Availability

Sync is optional. Capache may be unavailable, delayed, or interrupted due to network conditions, Supabase availability, maintenance, app bugs, or platform changes.

Capache is provided as-is. You are responsible for maintaining your own backups. The app includes a local export feature to help with backups.

## Data Deletion

You can delete local notes in the app or remove local app data by uninstalling the app. If you are signed in, Capache can delete synced notes, folders, note history, sync keys, and related sync metadata from Supabase. A full account deletion flow requires the deployed server-side account deletion function described in the project documentation and a fresh email-code verification.

Deleted synced data may remain temporarily in provider backups, logs, or security records where required for operations, legal compliance, or abuse prevention.

## Open Source and Self-Hosting

The Capache source code is licensed under the repository license. If you modify the app, self-host Supabase, or distribute your own build, you are responsible for your own infrastructure, secrets, security configuration, privacy disclosures, and legal compliance.

## Privacy

Capache's handling of data is described in `docs/PRIVACY_POLICY.md`.

## Apple Terms

If you download Capache through Apple software distribution channels, Apple's applicable terms may also apply. Apple is not responsible for Capache's optional Supabase sync service.

## No Warranty

Capache is provided without warranties of any kind, express or implied, including warranties of merchantability, fitness for a particular purpose, availability, or non-infringement.

## Limitation of Liability

To the maximum extent permitted by law, Johnston Liu is not liable for indirect, incidental, special, consequential, exemplary, or punitive damages, or for loss of data, profits, business, goodwill, or device access arising from use of Capache.

## Indemnity

To the maximum extent permitted by law, you agree to be responsible for claims, losses, liabilities, damages, costs, and expenses arising from your misuse of Capache, your content, your violation of these terms, or your violation of another person's rights.

## Governing Law

These terms are governed by the laws of the United States and the laws of the state where Capache is operated, without regard to conflict-of-law rules, except where your local law gives you mandatory consumer rights that cannot be waived.

## Changes

These terms may be updated as Capache changes. The effective date will be updated when the terms change.

## Contact

Johnston Liu
johnstonliu2004@gmail.com
