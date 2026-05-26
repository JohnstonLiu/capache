# Mac Distribution

Capache is configured for Mac Catalyst so it can be distributed outside the Mac App Store as a signed and notarized app.

Required Apple setup:

1. Apple Developer Program membership.
2. Developer ID Application certificate exported as a `.p12`.
3. App-specific password for notarization.
4. App ID/capabilities that cover the bundle ID and app group.

GitHub release secrets used by `.github/workflows/mac-release.yml`:

```text
MACOS_CERTIFICATE_BASE64
MACOS_CERTIFICATE_PASSWORD
KEYCHAIN_PASSWORD
APPLE_ID
APPLE_APP_SPECIFIC_PASSWORD
SUPABASE_URL
SUPABASE_PUBLISHABLE_KEY
```

Create `MACOS_CERTIFICATE_BASE64` with:

```sh
base64 -i DeveloperIDApplication.p12 | pbcopy
```

To release:

1. Push a tag like `v1.0.2`.
2. Run the `Mac Release` workflow, or let it run from the tag push.
3. The workflow archives the Mac Catalyst app, exports it with Developer ID signing, submits it to Apple notarization, staples the notarization ticket, zips the app, and uploads the zip to the GitHub release.
