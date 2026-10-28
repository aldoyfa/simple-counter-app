# Changing Room Counter

Offline-first Flutter app for counting changing room customers at an event.

The app tracks four categories:

- Male Cash
- Male QRIS
- Female Cash
- Female QRIS

Each tap creates an individual timestamped record saved on the device. A photo
can be linked to each record, either by taking one with the camera or choosing
one from the gallery: use **Add photo** on the message shown after a tap, or the
thumbnail next to the record in history. Photos are
compressed on the phone when attached (about 1080px, roughly 150-250 KB) so
uploads stay quick. Everything works offline; internet is
only needed when uploading.

Uploading sends each pending record, with its photo, to a Google Apps Script
web app. The script appends a row to the `Entries` sheet and saves the photo to
the "QRIS Day 1" (31 October) or "QRIS Day 2" (1 November) Drive folder, with a
link in the row's Attachment column. Records are uploaded one at a time, so if
the connection drops, the ones already sent stay uploaded and the rest can be
retried.

## Google Sheets upload setup

1. Create and deploy the Apps Script endpoint from
   `docs/google_apps_script.md`.
2. Copy `.env.example` to `.env` and put the deployed web app URL there.
3. Build the Android APK with the URL injected at compile time:

   ```powershell
   flutter build apk --release --dart-define-from-file=.env
   ```

`lib/app_config.dart` reads the URL from `GOOGLE_APPS_SCRIPT_WEB_APP_URL`, so
the private Apps Script URL does not need to be committed to Git.

Successful uploads are marked locally and will not be uploaded again; the
script also ignores an entry ID that is already in the sheet. Voided
records remain visible in history but are excluded from totals and upload
payloads.
