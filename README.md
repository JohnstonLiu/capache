# Capache

Capache is a native Swift notes app for iPhone, iPad, widgets, and Mac Catalyst. It works without an account, and optional sync uses Supabase email one-time-password authentication.

Current product surface:

- local-first note editing with rich text storage;
- widgets that show note text without exposing note titles;
- note titles, folders, pinned notes, archive, search, and note history;
- per-note Local Only control so selected notes never upload for sync;
- realtime sync triggers, open-note presence warnings, and last-writer-wins recovery through note history;
- WidgetKit push refresh for iOS widgets when synced notes change on another device;
- recoverable standard sync encryption for synced note title/body/history payloads;
- local JSON export for notes, folders, and note history;
- Mac Catalyst distribution through signed and notarized GitHub Releases.

Standard sync encryption is not end-to-end encryption. Capache encrypts synced note title/body/history payloads before upload, but the recoverable per-account sync key is stored in Supabase so normal account recovery remains possible.

Setup docs:

- [Supabase setup](docs/SUPABASE.md)
- [Mac distribution](docs/MAC_DISTRIBUTION.md)
- [Privacy policy](docs/PRIVACY_POLICY.md)
- [Terms of service](docs/TERMS_OF_SERVICE.md)
- [Data protection model](docs/DATA_PROTECTION.md)
- [Production checklist](docs/PRODUCTION_CHECKLIST.md)
- [Support](docs/SUPPORT.md)
- [Security policy](SECURITY.md)

The code is licensed under the [MIT License](LICENSE). The privacy policy and terms in this repository are product drafts and should be reviewed before public launch.
