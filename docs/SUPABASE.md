# Supabase Setup

Capache currently uses Supabase for optional authentication, database storage, Edge Functions, and sync. The user-facing privacy policy should name Supabase directly while preserving the option to update service providers later.

1. Create a Supabase project.
2. Run every SQL file in `supabase/migrations/` in filename order in the SQL editor or with the Supabase CLI.
3. In Supabase Auth, enable email sign-ins.
4. For the simplest passwordless flow, open Authentication > Providers > Email and turn off Confirm email. Capache verifies ownership through the one-time code, so a separate signup-confirmation link is not needed.
5. For code-based login, open Authentication > Emails and replace link-based bodies with code bodies that include `{{ .Token }}`. Update both Magic Link and Confirm signup. If a template uses `{{ .ConfirmationURL }}`, Supabase sends a link and may redirect to the project's Site URL, such as localhost.

```html
<div style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#111827;line-height:1.5;">
  <h2 style="margin:0 0 12px;font-size:22px;">Your Capache code</h2>
  <p style="margin:0 0 16px;color:#4b5563;">Enter this code in Capache to continue.</p>
  <p style="margin:0;font-size:32px;font-weight:700;letter-spacing:6px;font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,monospace;">{{ .Token }}</p>
  <p style="margin:20px 0 0;color:#6b7280;font-size:14px;">If you did not request this code, you can ignore this email.</p>
</div>
```

6. Optional but recommended: set the email OTP expiry to 10-15 minutes in Authentication settings.
7. In Xcode, set these build settings on the `cache` app target:

```text
SUPABASE_URL = https://YOUR_PROJECT_REF.supabase.co
SUPABASE_PUBLISHABLE_KEY = sb_publishable_...
```

Only the publishable key belongs in the app. Do not put the database password, direct Postgres URL, `service_role`, or `sb_secret_...` key in Xcode, GitHub Actions app builds, or client-side code.

## Email Rate Limits

Supabase's built-in email sender is only for development. It can hit low project-wide limits quickly while testing signup and OTP flows. For production, configure a custom SMTP provider in Authentication > SMTP Settings, then adjust Authentication > Rate Limits for OTP email volume.

The app disables resend actions for 30 seconds after requesting a code. That prevents accidental retry loops, but it does not raise the Supabase project quota. If Supabase's per-user resend window is higher than 30 seconds, Supabase can still reject early retries until the server-side window expires.

The app stores local notes in a file-backed shared store and keeps app-group `UserDefaults` as a compatibility cache for widgets and older builds. Sign-in is optional. Supabase is used only when the user turns on sync. When sync is enabled, newer local notes and folders are merged into Supabase before remote data is cached locally.

Individual notes can be marked Local Only. Local-only notes stay in local storage, are kept out of Supabase uploads, and are preserved when the remote cache is refreshed. If a previously synced note is changed to Local Only, the app deletes that note's remote row and keeps the local copy on that device.

## Sync Conflict Model

The current sync model uses per-note local sync baselines and last-writer-wins conflict handling.

- Every synced note stores a local `lastSyncedContentHash`.
- If only the local note changed since the last synced hash, the app uploads it.
- If only the remote note changed since the last synced hash, the app downloads it.
- If both local and remote changed, the newest `updated_at` version stays canonical. The app no longer creates automatic conflict-copy notes for simultaneous edits.
- Before a local save overwrites a different remote version, the remote note body is saved into note history so users still have a recovery path.
- If a synced note was deleted remotely while a device had unsynced local edits, the local edit is uploaded on the next sync pass instead of being dropped.
- Writes are local-first. If Supabase is temporarily unavailable during an edit, the local note is still saved and the next sync pass retries from the local baseline.
- This is not field-level or paragraph-level merge. Users recover older bodies from note history when needed.

The organization migration adds note titles, folders, pinned notes, and archived notes. The conflict migration adds `content_hash`, `is_conflict`, `conflict_parent_id`, and `conflict_created_at`. The standard encryption migration adds encrypted payload columns and the recoverable `sync_keys` table. The grant hardening migration removes unnecessary anonymous and non-CRUD privileges from app tables. If the app shows a sync error mentioning missing columns, `folders`, or `sync_keys`, run every SQL file in `supabase/migrations/` in filename order.

If migrations were pasted into the SQL editor, `supabase migration list` may still show blank remote versions because the CLI migration history table was not updated. Do not run `supabase db push` against production just to fix history unless you have verified the migrations are safe to reapply. Use `supabase migration repair --status applied <version>` only after confirming the live schema contains the expected tables, columns, policies, and publication changes.

## Standard Sync Encryption

New synced note uploads store note title, rich text data, plain text, and history snapshots in `encrypted_payload` using AES-GCM. The legacy `title`, `rtf_data`, and `plain_text` columns are kept as compatibility placeholders for the current schema, but new app versions do not store the real note content there.

The per-account sync key is stored in `sync_keys` under row-level security. This is recoverable standard protection, not end-to-end encryption: a backend operator with sufficient database access can retrieve the key and decrypt note payloads. Existing plaintext remote rows are upgraded opportunistically when the new app lists notes or history.

## Realtime Sync

The app uses Supabase Realtime as a change notification trigger. Realtime events do not directly mutate local notes; they debounce and call the normal pull sync path so last-writer-wins handling, delete propagation, and legacy duplicate conflict cleanup still run in one place.

The editor also uses Realtime Presence to show a soft "open on another device" warning when the same synced note is open in another app session. Presence payloads contain only a random per-session device ID, platform label, note ID, and open timestamp.

Run the realtime migration so `notes`, `folders`, and `note_history` are added to the `supabase_realtime` publication. The migration also sets replica identity to `full` for these tables so delete events are reliable.

## Widget Background Refresh

Capache uses WidgetKit push notifications for the best available iOS widget refresh path when another synced device changes a note.

The flow is:

- The iOS widget receives a WidgetKit push token from Apple and stores it in the App Group.
- The signed-in app registers a random widget refresh token with Supabase. Supabase stores only its SHA-256 hash.
- The widget registers its Apple push token with the `widget-register-push-token` Edge Function.
- When a synced note changes, the app calls `send-widget-refresh`.
- `send-widget-refresh` sends an APNs WidgetKit push to the user's registered widget tokens. Each token is sent to its own stored APNs environment, so sandbox/dev and production devices can coexist.
- `send-widget-refresh` records non-content APNs diagnostics in `widget_push_receipts` and the latest status on `widget_push_tokens`, so delivery issues can be separated from WidgetKit throttling or stale app builds.
- When WidgetKit reloads the timeline, the widget calls `widget-note-snapshot` with the refresh token and selected note ID. The function returns the encrypted note row; decryption still happens in the widget on the device.
- `widget-note-snapshot` records non-content snapshot diagnostics in `widget_snapshot_receipts` and the latest status on `widget_refresh_tokens`, so we can tell whether WidgetKit woke up after APNs accepted a push.

Deploy the widget functions after running the widget refresh migration:

```sh
supabase functions deploy send-widget-refresh
supabase functions deploy widget-register-push-token
supabase functions deploy widget-note-snapshot
```

`supabase/config.toml` keeps JWT verification on for signed-in functions and disables it for the two widget-token functions, which implement their own refresh-token authentication.

Configure APNs secrets for `send-widget-refresh`:

```sh
supabase secrets set APNS_KEY_ID=YOUR_KEY_ID
supabase secrets set APNS_TEAM_ID=YOUR_TEAM_ID
supabase secrets set APNS_PRIVATE_KEY="$(cat AuthKey_YOUR_KEY_ID.p8)"
supabase secrets set APNS_WIDGET_TOPIC=me.johnstonliu.cache.push-type.widgets
```

The APNs auth key can be used for both sandbox and production pushes. The app records the environment when the widget token is registered, and the Edge Function sends each token to the matching Apple host. WidgetKit pushes require a real device and Apple's APNs service; they are not a reliable simulator-only test. Apple also budgets WidgetKit pushes, so this improves background freshness but does not promise instant delivery for every edit. The widget also keeps a short timeline refresh fallback so delayed pushes do not leave the selected note stale indefinitely.

To inspect the latest APNs attempts:

```sh
supabase db query --linked "select sent_at, environment, apns_status, apns_reason, apns_error, removed from public.widget_push_receipts order by sent_at desc limit 20;"
supabase db query --linked "select requested_at, status, error from public.widget_snapshot_receipts order by requested_at desc limit 20;"
```

## Account Deletion Function

Deploy the full account deletion function before enabling the in-app Delete Account action in production:

```sh
supabase functions deploy delete-user
```

Do not manually set secrets whose names start with `SUPABASE_`. Supabase reserves that prefix and provides `SUPABASE_URL` and secret keys to hosted Edge Functions automatically. The function reads `SUPABASE_SECRET_KEYS` first and falls back to the legacy `SUPABASE_SERVICE_ROLE_KEY` if Supabase exposes it.

The function deletes synced notes, folders, note history, sync keys, and the Supabase Auth user for the signed-in account. Before deletion, it verifies the bearer token and requires Supabase Auth to report a recent sign-in. The app creates that fresh sign-in by sending a one-time code to the signed-in email before calling the function.
