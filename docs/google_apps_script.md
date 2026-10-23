# Google Apps Script endpoint

The app uploads to an Apps Script web app that:

- appends one row per entry to the `Entries` sheet of
  [Rekap Ruang Ganti CF23](https://docs.google.com/spreadsheets/d/1GXISV6kogO5hJm1lne-jBm-JW_bfZbBt4TwGpXGMWGo/edit),
- saves the entry's photo (if any) to the Drive folder for the day the entry
  was created, and
- links that photo in the `Attachment` column.

| Entry created (Asia/Jakarta) | Drive folder |
|---|---|
| Saturday 31 October 2026 or earlier | [QRIS Day 1](https://drive.google.com/drive/folders/16Lp2yXwuLFYHrQMlR4cL8HXMYJOySmUg) |
| Sunday 1 November 2026 or later | [QRIS Day 2](https://drive.google.com/drive/folders/1nltsXHVfp7hCJ9zugswdHsu_dTlWi4bj) |

The `Entries` sheet must keep this header row:

| No | Entry-ID | Upload-ID | Uploader | Gender | Payment | Created at | Uploaded at | Attachment |
|---|---|---|---|---|---|---|---|---|

## Request format

The app sends one POST per entry:

```json
{
  "uploadId": "upload-20261031143000123456",
  "uploadedAt": "2026-10-31T07:30:00.123456Z",
  "staffUsername": "Ayu",
  "record": {
    "id": "1793431795123456-female_qris",
    "category": "female_qris",
    "categoryLabel": "Female QRIS",
    "gender": "Female",
    "payment": "QRIS",
    "createdAt": "2026-10-31T07:29:55.123456Z"
  },
  "photo": {
    "fileName": "1793431795123456-female_qris.jpg",
    "mimeType": "image/jpeg",
    "data": "<base64 image bytes>"
  }
}
```

`photo` is `null` when the entry has no photo. Timestamps are UTC; the script
converts them to the spreadsheet's Asia/Jakarta time.

Sending the same `record.id` again returns success without adding a second row
or a second photo, so the app can safely retry after a dropped connection.

## Script

Paste this into the Apps Script project (Extensions > Apps Script from the
spreadsheet), replacing the previous handler:

```javascript
const SPREADSHEET_ID = '1GXISV6kogO5hJm1lne-jBm-JW_bfZbBt4TwGpXGMWGo';
const SHEET_NAME = 'Entries';
const TIME_ZONE = 'Asia/Jakarta';
const DAY_1_FOLDER_ID = '16Lp2yXwuLFYHrQMlR4cL8HXMYJOySmUg'; // QRIS Day 1
const DAY_2_FOLDER_ID = '1nltsXHVfp7hCJ9zugswdHsu_dTlWi4bj'; // QRIS Day 2
const DAY_1_LAST_DATE = '2026-10-31'; // Entries after this date go to Day 2.

function doPost(e) {
  const lock = LockService.getScriptLock();
  try {
    lock.waitLock(30000);

    const payload = JSON.parse(e.postData.contents);
    const record = payload.record;
    if (!record || !record.id) {
      throw new Error('The upload has no record.');
    }

    const sheet = SpreadsheetApp.openById(SPREADSHEET_ID)
      .getSheetByName(SHEET_NAME);
    if (!sheet) {
      throw new Error(`Sheet "${SHEET_NAME}" not found.`);
    }

    const existingRow = findEntryRow_(sheet, record.id);
    if (existingRow) {
      return json_({ success: true, duplicate: true, row: existingRow });
    }

    const createdAt = new Date(record.createdAt);
    const uploadedAt = new Date(payload.uploadedAt);
    const photoFile = savePhoto_(payload.photo, record, createdAt);

    const row = sheet.getLastRow() + 1;
    sheet.getRange(row, 1, 1, 8).setValues([[
      row - 1,
      record.id,
      payload.uploadId || '',
      payload.staffUsername || '',
      record.gender || '',
      record.payment || '',
      createdAt,
      uploadedAt,
    ]]);
    sheet.getRange(row, 7, 1, 2).setNumberFormat('yyyy-mm-dd hh:mm:ss');

    if (photoFile) {
      sheet.getRange(row, 9).setRichTextValue(
        SpreadsheetApp.newRichTextValue()
          .setText(photoFile.getName())
          .setLinkUrl(photoFile.getUrl())
          .build()
      );
    }
    SpreadsheetApp.flush();

    return json_({
      success: true,
      row: row,
      photoUrl: photoFile ? photoFile.getUrl() : null,
    });
  } catch (error) {
    return json_({ success: false, error: String(error) });
  } finally {
    lock.releaseLock();
  }
}

function findEntryRow_(sheet, entryId) {
  const lastRow = sheet.getLastRow();
  if (lastRow < 2) {
    return null;
  }
  const match = sheet.getRange(2, 2, lastRow - 1, 1)
    .createTextFinder(entryId)
    .matchEntireCell(true)
    .findNext();
  return match ? match.getRow() : null;
}

function savePhoto_(photo, record, createdAt) {
  if (!photo || !photo.data) {
    return null;
  }

  const day = Utilities.formatDate(createdAt, TIME_ZONE, 'yyyy-MM-dd');
  const folderId = day <= DAY_1_LAST_DATE ? DAY_1_FOLDER_ID : DAY_2_FOLDER_ID;
  const extensionMatch = String(photo.fileName || '').match(/\.[a-z0-9]+$/i);
  const extension = extensionMatch ? extensionMatch[0] : '.jpg';
  const time = Utilities.formatDate(createdAt, TIME_ZONE, 'yyyy-MM-dd HH-mm-ss');
  const fileName = `${time} ${record.categoryLabel || record.category} ${record.id}${extension}`;

  const blob = Utilities.newBlob(
    Utilities.base64Decode(photo.data),
    photo.mimeType || 'image/jpeg',
    fileName
  );
  return DriveApp.getFolderById(folderId).createFile(blob);
}

function json_(value) {
  return ContentService
    .createTextOutput(JSON.stringify(value))
    .setMimeType(ContentService.MimeType.JSON);
}
```

## Deployment

1. Save the script, then run `doPost` once from the editor so Google asks you
   to grant the new Drive permission. The run itself does nothing useful
   without a request body; that is expected.
2. To keep the URL already in `.env`, choose **Deploy > Manage deployments**,
   edit the existing web app deployment and pick **Version: New version**.
   For a first deployment use **Deploy > New deployment > Web app** instead.
3. Execute as: **Me** (the owner of the spreadsheet and the QRIS folders).
4. Who has access: **Anyone**, so the event phones can post without signing in.
5. Put the web app URL in `.env` as `GOOGLE_APPS_SCRIPT_WEB_APP_URL` and
   rebuild the app.

Anyone who opens the Attachment links needs view access to the QRIS folders
(the files inherit the folder's sharing).
