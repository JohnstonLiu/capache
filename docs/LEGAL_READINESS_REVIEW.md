# Legal Readiness Review

Date: 2026-05-25

This is a founder/operator legal-readiness review for Capache's public docs and app behavior. It is not attorney-client privileged legal advice and does not replace review by a licensed attorney.

## Sources Checked

- Apple App Review Guidelines, especially privacy policy, consent, data minimization, login, and account deletion requirements: https://developer.apple.com/app-store/review/guidelines/
- Apple App Privacy Details guidance for declaring data collected by the app and third-party partners: https://developer.apple.com/app-store/app-privacy-details/
- FTC COPPA guidance for apps and online services that collect personal information from children under 13: https://www.ftc.gov/business-guidance/resources/complying-coppa-frequently-asked-questions
- California Privacy Protection Agency summary of CCPA/CPRA consumer rights: https://privacy.ca.gov/california-privacy-rights/rights-under-the-california-consumer-privacy-act/
- European Data Protection Board small business guidance on individual privacy rights: https://www.edpb.europa.eu/sme-data-protection-guide/respect-individuals-rights_en

## Product Facts Reflected

- Capache works without login.
- Sync is optional and uses Supabase email OTP auth.
- Per-note Local Only controls exist.
- Synced note title/body/history payloads use recoverable Standard Protection encryption.
- Current sync is not end-to-end encrypted or zero-knowledge.
- Folder names, timestamps, conflict metadata, content hashes, account identifiers, and sync metadata may be visible to the backend.
- The app does not include first-party analytics or advertising tracking code.
- The app includes local export and synced data deletion flows.
- The `delete-user` Supabase Edge Function is deployed and is intended to delete synced rows, sync keys, and the Supabase Auth user.
- Mac distribution is outside the Mac App Store through signed and notarized GitHub Releases.
- The repository is open source under MIT.

## Changes Made

- Strengthened privacy policy sections for data categories, sources, use, sharing, retention, security, deletion, privacy rights, international processing, and children.
- Strengthened terms for eligibility, accounts, sync conflicts, backups, third-party services, Apple distribution, open-source/self-hosting responsibility, warranty, liability, indemnity, and governing law.
- Updated security docs to avoid overclaiming encryption.
- Updated App Privacy notes to align with Apple privacy label expectations.
- Updated production checklist to distinguish completed founder/operator review from optional licensed-attorney review.

## Residual Risks

- Governing law should be finalized to the operator's actual state or business jurisdiction.
- Privacy and terms should be reviewed again before adding payments, analytics, subscriptions, AI features, collaboration, public sharing, attachments, or end-to-end encryption.
- If the app targets or knowingly collects from children under 13, COPPA obligations would need a separate parental consent flow and child-specific policy language.
- If the app is marketed in the EEA/UK or heavily used there, GDPR/UK GDPR details may need a fuller controller/processor, lawful basis, transfer, and complaint-rights section.
- If the app reaches CCPA/CPRA thresholds or handles California requests at scale, add a more formal California notice and request workflow.
- App Store Connect privacy answers must be kept consistent with actual runtime behavior and third-party SDK behavior.

## Review Outcome

The current documents are reasonable for a small, local-first notes app with optional Supabase sync, no ads, no first-party analytics, and recoverable Standard Protection encryption. The biggest legal/consumer-trust requirement is to keep the encryption wording precise: Capache is encrypted in transit and uses encrypted synced payloads, but it is not end-to-end encrypted today.
