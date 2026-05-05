# Google Apps Script endpoint

Set `googleAppsScriptWebAppUrl` in `lib/app_config.dart` to the deployed web app
URL before building the app.

Create a Google Apps Script attached to the target spreadsheet and deploy it as
a web app. The app uploads JSON with:

```json
{
  "sheetName": "Event Upload 2026-05-05 14-30",
  "uploadId": "upload-20260505143000123456",
  "uploadedAt": "2026-05-05T14:30:00.123456",
  "staffUsername": "Ayu",
  "records": [
    {
      "id": "1777980600123456-male_cash",
      "category": "male_cash",
      "categoryLabel": "Male Cash",
      "createdAt": "2026-05-05T14:29:55.123456"
    }
  ]
}
```

Use this Apps Script as the web app handler:

```javascript
function doPost(e) {
  try {
    const payload = JSON.parse(e.postData.contents);
    const spreadsheet = SpreadsheetApp.getActiveSpreadsheet();
    const sheetName = uniqueSheetName_(spreadsheet, payload.sheetName);
    const sheet = spreadsheet.insertSheet(sheetName);
    const records = payload.records || [];
    const summary = {};

    records.forEach((record) => {
      const label = record.categoryLabel || record.category;
      summary[label] = (summary[label] || 0) + 1;
    });

    sheet.getRange(1, 1, 1, 2).setValues([['Upload ID', payload.uploadId]]);
    sheet.getRange(2, 1, 1, 2).setValues([['Uploaded at', payload.uploadedAt]]);
    sheet.getRange(3, 1, 1, 2).setValues([['Staff username', payload.staffUsername || '']]);
    sheet.getRange(4, 1, 1, 2).setValues([['Category', 'Total']]);

    const summaryRows = Object.keys(summary).map((label) => [label, summary[label]]);
    if (summaryRows.length > 0) {
      sheet.getRange(5, 1, summaryRows.length, 2).setValues(summaryRows);
    }

    const recordsStartRow = 7 + summaryRows.length;
    sheet.getRange(recordsStartRow, 1, 1, 5).setValues([
      ['ID', 'Staff Username', 'Category', 'Category Label', 'Created At']
    ]);

    if (records.length > 0) {
      const recordRows = records.map((record) => [
        record.id,
        payload.staffUsername || '',
        record.category,
        record.categoryLabel,
        record.createdAt
      ]);
      sheet.getRange(recordsStartRow + 1, 1, recordRows.length, 5)
        .setValues(recordRows);
    }

    return json_({ success: true, sheetName: sheetName });
  } catch (error) {
    return json_({ success: false, error: String(error) });
  }
}

function uniqueSheetName_(spreadsheet, baseName) {
  let name = baseName || 'Event Upload';
  let suffix = 2;

  while (spreadsheet.getSheetByName(name)) {
    name = `${baseName} (${suffix})`;
    suffix += 1;
  }

  return name;
}

function json_(value) {
  return ContentService
    .createTextOutput(JSON.stringify(value))
    .setMimeType(ContentService.MimeType.JSON);
}
```

Deployment notes:

1. In Apps Script, choose **Deploy > New deployment > Web app**.
2. Execute as the spreadsheet owner.
3. Set access to the operators that will upload, or "Anyone" for a private
   event device flow.
4. Copy the web app URL into `lib/app_config.dart`.
