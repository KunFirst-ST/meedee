# Verification report — Laravel + MySQL

Verified 13 October 2026 (Asia/Bangkok). The user explicitly chose a fresh MySQL database and canceled migration of old Firebase data. Firebase was not deleted or modified. Flutter no longer uses Firebase runtime SDKs.

| Check | Result |
|---|---|
| Flutter tests | 78 passed, 24 seconds |
| Flutter analyzer | No issues, 10.0 seconds |
| Web release | Built with API_BASE_URL=https://103.114.201.109/api/v1, 91.5 seconds; deployed to VPS |
| Android debug | Built version 1.1.0+2 with same HTTPS API, 534.4 seconds, 158,196,082 bytes |
| Android installation | APK installed on Pixel_8_Pro; actual login UI and the backend Google-unconfigured response verified in app-android-mysql-current.png. Initial emulator launcher ANR/cold-start timeout recovered before screenshot verification |
| Laravel local | 41 tests / 372 assertions passed, PHP 8.3.35 + GD, SQLite in-memory |
| MySQL integration | Final release 20261013-02: 41 tests / 372 assertions passed on dedicated MySQL test DB, 5.232 seconds |
| Read-only export tool | 6 isolated Node tests passed; not used on real data |
| Public HTTPS | Windows client and VPS curl validate Let's Encrypt IP certificate without bypass; app HTTP 200 |
| Provider readiness (13 Oct, before OAuth install) | /api/v1/capabilities returned googleConfigured=false and emailConfigured=false |
| Browser UI (13 Oct, before OAuth install) | Signed-out login loaded from public VPS; Google click displayed missing-OAuth 503, no fake session |
| Certificate renewal | certbot dry-run renewal and nginx deploy hook succeeded; dedicated systemd timer enabled twice daily |
| Existing services | kudee returns 302 and protected n8n returns 401 after deployment |

## Deployed layout

MySQL 8.4.11 container msu-food-mysql binds only 127.0.0.1:3307, has a dedicated volume and a 512 MB limit. Existing MariaDB on 3306 and other containers remain in place. The app uses its own database/account, PHP-FPM pool and Linux user. Code is read-only for the app user; storage/cache are private and writable. Secrets are generated/stored on VPS, not inside source ZIP or Flutter builds.

Production counts verified as zero users, shops, menus and orders. Nginx serves a tested CSP compatible with Flutter/CanvasKit and adds an explicit IP host. IP TLS clients omit SNI, so the previous default TLS handshake rejection was replaced with the IP certificate and HTTP 444 for unknown hosts. Named hosts retain their own certificates/configuration. A private backup of the former default configuration is on VPS. MSU Food access logs omit URLs/query strings to avoid OAuth/reset-code logging.

Laravel production rejects plaintext API transport. Authentication/authorization, server canonical prices, integer satang, order transaction locking, idempotency, state transitions, receipt retention and import integrity are covered by backend tests. MySQL tests use a separate test database and account; the runner aborts if production config cache exists. Fixtures never go into the production database.

## Status at 13 October 2026 (before OAuth install)

No real SMTP service or Google OAuth client secret had been provided at that point. Email registration/reset/verification and Google sign-in therefore could not complete on production. The app does not auto-verify email, create replacement users, log pretend mail delivery, or bypass roles/ownership. The OAuth update below records the later installation; actual provider sign-in and email delivery still need their respective end-to-end tests.

Google web-server OAuth does not accept a public raw IP as redirect host. A DNS hostname accepted by Google is needed for the OAuth callback, even though IP HTTPS works for the app/API. Reference: https://developers.google.com/identity/protocols/oauth2/web-server#uri-validation

The Imdee Figma file remains inaccessible to the connected account/team; no implementation of that new design is claimed. Firebase emulator scripts and prior native-certificate diagnostics are historical evidence only, unrelated to current MySQL validation.

## OAuth update — 14 October 2026

Google OAuth Web client JSON for `msu-foodnaja` was validated against the project number and exact callback, then installed on the VPS without placing its secret in the app source. The installer completed successfully and the public capability response now reports `googleConfigured=true` and `emailConfigured=false`. Google start/callback validation, the app and web callback allowlists, and the web callback route were checked. Flutter auth tests passed (20 tests).

The earlier 13 October entries above record the pre-OAuth state and are historical. An actual sign-in with a Google account has not yet been performed, so production account consent and end-to-end token exchange remain to be tested by the user. SMTP is still not configured; email verification and password reset are unavailable.
