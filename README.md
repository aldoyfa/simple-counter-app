# Changing Room Counter

Offline-first Flutter app for counting changing room customers at an event.

The app tracks four categories:

- Male Cash
- Male QRIS
- Female Cash
- Female QRIS

Each tap creates an individual timestamped record saved on the device. Pending
records can be uploaded later to Google Sheets through a preconfigured Google
Apps Script web app URL.

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

Successful uploads are marked locally and will not be uploaded again. Voided
records remain visible in history but are excluded from totals and upload
payloads.
