# Production Checklist

## Privacy and Compliance

- [x] Draft privacy policy exists in `docs/PRIVACY_POLICY.md`.
- [x] Founder/operator legal-readiness review of privacy policy.
- [ ] Licensed attorney review of privacy policy.
- [x] Draft terms of service exists in `docs/TERMS_OF_SERVICE.md`.
- [x] Founder/operator legal-readiness review of terms of service.
- [ ] Licensed attorney review of terms of service.
- [x] Privacy policy URL published: https://gist.github.com/JohnstonLiu/40defa3411dd1844e9ed86c7a0221677
- [x] Terms of service URL published: https://gist.github.com/JohnstonLiu/d7b2692140bb605d23ae87a6259f98b9
- [x] Support URL published: https://gist.github.com/JohnstonLiu/82f1b56905b39dd01e966ab554f31a6e
- [x] Open-source license exists.
- [x] Self-service account deletion code path exists.
- [x] Synced data deletion flow.
- [x] Account deletion requires fresh email-code verification.
- [x] Apple App Privacy details prepared in `docs/APP_PRIVACY.md`.
- [x] Apple privacy manifest added for required-reason APIs.
- [ ] Verify archived privacy report in Xcode Organizer/App Store Connect.
- [x] Support/contact path documented.
- [x] Security disclosure policy exists in `SECURITY.md`.

## Data Protection

- [x] Sync is optional and the app works signed out.
- [x] Per-note Local Only sync control.
- [x] Local-first writes preserve edits when sync is unavailable.
- [x] Supabase publishable key is the only client key.
- [x] Supabase row-level security migrations exist.
- [x] Supabase app table grants hardened to authenticated CRUD only.
- [x] Local upgrade test passed for legacy local note migration.
- [x] Move primary local notes off pure `UserDefaults`.
- [x] Keep app-group `UserDefaults` as widget/cache/migration storage only.
- [x] Standard Protection recovery model implemented.
- [ ] Advanced Protection end-to-end encryption implemented.
- [x] Recoverable server-stored sync key implemented for Standard Protection.
- [ ] Trusted-device key storage and recovery flow implemented for Advanced Protection.
- [x] Standard recoverable encrypted sync implemented for note title/body/history payloads.
- [x] Standard encrypted sync migration applied and schema-verified against the live Supabase project.
- [x] Export/backup flow.

## Supabase

- [x] Initial notes migration exists.
- [x] Organization migration exists for titles, folders, pinning, and archive.
- [x] Conflict detection migration exists.
- [x] Realtime publication migration exists.
- [x] Least-privilege grant hardening migration exists.
- [x] Apply and record all migrations in production Supabase.
- [x] Verify email OTP template sends a code with `{{ .Token }}`.
- [x] Verify OTP expiry.
- [x] Configure custom SMTP for production auth emails.
- [x] Set production Auth rate limits after custom SMTP is configured.
- [ ] Verify RLS with at least two test users.
- [x] Add synced data deletion path.
- [x] Add full account deletion server function.
- [x] Deploy `delete-user` Supabase Edge Function.
- [x] `delete-user` requires recent Supabase sign-in before deleting account data.
- [x] Verify deployed `delete-user` deletes `sync_keys`.
- [x] Deploy widget background refresh Edge Functions.
- [x] Configure APNs WidgetKit push secrets in Supabase.
- [x] Add widget APNs/snapshot diagnostics for production refresh debugging.
- [x] Verify APNs accepts WidgetKit pushes for registered development tokens.
- [x] Verify WidgetKit push refresh on a physical iPhone.
- [ ] Add production backup/restore procedure.

## App Testing

- [x] Version bumped for major App Store release: 2.0.0 build 2.
- [x] App Store submission copy prepared in `docs/APP_STORE_SUBMISSION.md`.
- [x] App Store export options added in `ci/ExportOptions-AppStore.plist`.
- [x] Local Release iOS archive succeeds.
- [ ] Install iOS Distribution certificate or configure App Store Connect API-key signing.
- [ ] Enable Push Notifications on the widget extension App ID for App Store provisioning.
- [ ] App Store/TestFlight export succeeds.
- [ ] TestFlight upload succeeds.
- [x] Add unit and UI test targets so `xcodebuild test` can run in CI.
- [x] Add GitHub Actions iOS test workflow.
- [x] GitHub Actions iOS test workflow is green on `main`.
- [x] iOS Simulator build passes.
- [x] Mac Catalyst build passes.
- [x] UI launch smoke test passes.
- [x] Simulator upgrade test passed.
- [x] Account deletion manually verified.
- [ ] Physical iPhone upgrade test.
- [ ] Mac app replacement upgrade test.
- [ ] Offline create/edit/reconnect test.
- [ ] Multi-device last-writer-wins sync test.
- [x] Note-history recovery path for overwritten simultaneous edits.
- [x] Remote-delete/local-edit conflict preserves local edits.
- [ ] Sign out/sign in data preservation test.
- [ ] Widget after-upgrade test.
- [ ] Widget remote-change background refresh test on physical iPhone.
- [x] Widget stale-open overwrite protection test path.
- [ ] Folder/archive/pin/history sync regression test.

## Mac Distribution

- [x] GitHub Actions release workflow exists.
- [x] Developer ID export options exist.
- [ ] Apple Developer ID certificate configured in GitHub secrets.
- [ ] Notarization credentials configured in GitHub secrets.
- [ ] First notarized GitHub Release tested.
- [ ] Decide whether to add Sparkle auto-update later.
