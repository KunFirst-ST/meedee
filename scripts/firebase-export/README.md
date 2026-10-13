# Read-only Firebase export for the MySQL migration

This exports the existing `msu-foodnaja` project. It never changes Firebase users,
documents, indexes, rules, provider settings or stored files. No credentials are
included in source. A successful Firebase Console login alone does not authorize
the terminal: the owner must supply authorized Application Default Credentials.

Use Node.js 22 or later. From `scripts/firebase-export`, run `npm ci --ignore-scripts`.
Keep owner credentials and export files outside this application's source directory.
Use a service-account JSON file with **Firebase Authentication Viewer** and
**Cloud Datastore Viewer** permissions, or equivalent already-authorized ADC.
Do not send private keys, exported user data, tokens or passwords in chat.

PowerShell, from the application directory:

```powershell
$env:GOOGLE_APPLICATION_CREDENTIALS = 'C:/private-credentials/owner-firebase-reader.json'
node scripts/export-firebase.mjs --project msu-foodnaja --out 'C:/private-backups/msu-foodnaja-before-mysql.json'
```

The output parent directory must already exist. Existing files are never
overwritten. Credentials are read from `GOOGLE_APPLICATION_CREDENTIALS` or ADC;
the script does not create credentials, change IAM or bypass permission errors.
It refuses to run with Firebase emulator environment variables set.

All Auth users are paginated. Every root Firestore collection and subcollection
is traversed, including children of missing parent documents. Known application
collections appear in normalized arrays for the importer. `documents` also keeps
every Firestore document, including unknown collections, in a typed `rawData`
archive with creation/update metadata. Timestamp nanoseconds, references,
GeoPoints, bytes and 64-bit integers are preserved. Auth custom claims, disabled
status and linked-provider metadata are included; password hashes, salts and
refresh/access tokens are excluded. Password accounts need a real reset email
after migration because Firebase scrypt hashes cannot be used by Laravel.
Firebase remains the original rollback source.

The terminal prints only the output path, SHA-256 and counts. Check total Auth
users, Firestore documents and per-collection counts against the owner's source.
This is a sequential read, not an atomic cross-service snapshot: pause source
writes during the final migration window, then export and reconcile again before
cutover. This tool does not pause or disable the source application itself.
It does not export Firebase Storage object bytes, Realtime Database, IAM/settings
or indexes; the app's menu images already stored in Firestore `imageBase64` are
included. If the source uses another data service, preserve/export that service
separately before cutover.

Validate without writing SQL data, then review the reported SHA and counts:

```powershell
Set-Location backend
php artisan firebase:import 'C:/private-backups/msu-foodnaja-before-mysql.json'
php artisan firebase:import 'C:/private-backups/msu-foodnaja-before-mysql.json' --commit --expect-sha256=SHA_FROM_DRY_RUN
```

Commit requires an empty dedicated SQL database. The importer rejects inconsistent
ownership, missing Auth identities, historical totals, unsupported identities or
invalid images instead of inventing/replacing data. A failure rolls back the whole
SQL transaction. Repeating the identical file is harmless and cannot overwrite
later live edits. Keep the private source backup and original Firebase project
until row counts, identities, receipts and owner access have been checked.

Limits default to 50,000 documents/users and a 128 MB output matching the importer.
An explicit `--max-documents` can raise the count cap; a larger byte export needs a
reviewed chunked-import plan. Tests run locally with `npm test`; they use isolated
read-only mocks and never contact the real Firebase project.

References: [Admin Auth list users](https://firebase.google.com/docs/auth/admin/manage-users#list_all_users),
[Firestore collection enumeration](https://googleapis.dev/nodejs/firestore/latest/CollectionReference.html#listDocuments),
[server credentials](https://firebase.google.com/docs/firestore/quickstart-server).
