# Security Policy

## Reporting a Vulnerability

Please report security issues privately to:

johnstonliu2004@gmail.com

Do not open public GitHub issues for vulnerabilities involving authentication, sync data access, encryption, build signing, or Supabase configuration.

## Secret Handling

The app may include a Supabase URL and publishable key. Those are client-side identifiers and are safe to ship in the app.

Never commit:

- Supabase `service_role` keys
- Database passwords or direct Postgres connection strings
- Apple Developer ID certificates or certificate passwords
- App Store Connect API private keys
- Notarization app-specific passwords
- `.env` files

The Supabase `service_role` key belongs only in Supabase Edge Function secrets.

## Encryption Scope

Capache's current sync encryption is Standard Protection, not end-to-end encryption. Synced note titles, note bodies, rich text data, and note history payloads are encrypted before upload, but the recoverable per-account sync key is stored in Supabase. A backend operator with sufficient access could retrieve the key and decrypt synced note payloads.

Folder names, sync metadata, timestamps, conflict metadata, content hashes, and account identifiers may remain visible to the backend. Do not describe the current sync model as zero-knowledge or end-to-end encrypted.

## Open Source Review

This repository is public source code. Security should not depend on hiding client code, bundle identifiers, Supabase URLs, or publishable keys. Access control must come from Supabase Auth, row-level security policies, server-side secrets staying server-side, and Apple platform signing/notarization for distributed builds.
