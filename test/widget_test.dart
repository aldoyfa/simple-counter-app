import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_counter_app/counter_record.dart';
import 'package:simple_counter_app/main.dart';
import 'package:simple_counter_app/record_store.dart';
import 'package:simple_counter_app/upload_service.dart';

void main() {
  testWidgets('renders all category counters', (tester) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    expect(find.text('Male Cash'), findsOneWidget);
    expect(find.text('Male QRIS'), findsOneWidget);
    expect(find.text('Female Cash'), findsOneWidget);
    expect(find.text('Female QRIS'), findsOneWidget);
  });

  testWidgets('tapping categories increments the matching totals', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Male Cash'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Female QRIS'));
    await tester.pumpAndSettle();

    expect(_counterTileText('Male Cash', '1'), findsOneWidget);
    expect(_counterTileText('Female QRIS', '1'), findsOneWidget);
    expect(find.text('Pending: 2'), findsOneWidget);
  });

  testWidgets('undo voids the latest pending tap', (tester) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Male Cash'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo last tap'));
    await tester.pumpAndSettle();

    expect(_counterTileText('Male Cash', '0'), findsOneWidget);
    expect(find.text('Pending: 0'), findsOneWidget);
    expect(find.text('Voided: 1'), findsOneWidget);
  });

  testWidgets('history shows timestamped pending records', (tester) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Female Cash'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.history));
    await tester.pumpAndSettle();

    expect(find.text('Records History'), findsOneWidget);
    expect(find.text('Female Cash'), findsWidgets);
    expect(find.text('Pending'), findsWidgets);
  });

  testWidgets('voiding a pending record from history updates totals', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Male QRIS'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.history));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Void'));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('Records History'))).pop();
    await tester.pumpAndSettle();

    expect(_counterTileText('Male QRIS', '0'), findsOneWidget);
    expect(find.text('Voided: 1'), findsOneWidget);
  });

  testWidgets('restoring a voided record from history makes it pending again', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Male QRIS'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.history));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Void'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('Records History'))).pop();
    await tester.pumpAndSettle();

    expect(_counterTileText('Male QRIS', '1'), findsOneWidget);
    expect(find.text('Pending: 1'), findsOneWidget);
    expect(find.text('Voided: 0'), findsOneWidget);
  });

  testWidgets('upload marks pending records as uploaded', (tester) async {
    final uploader = _FakeUploader();
    await tester.pumpWidget(_testApp(uploader: uploader));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Female QRIS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();

    expect(uploader.uploadedRecordCount, 1);
    expect(find.text('Pending: 0'), findsOneWidget);
    expect(find.text('Uploaded: 1'), findsOneWidget);
  });

  testWidgets('staff username can be changed in the app', (tester) async {
    final store = _MemoryStore(staffUsername: 'Ayu');
    await tester.pumpWidget(_testApp(store: store));
    await tester.pumpAndSettle();

    expect(find.text('Ayu'), findsOneWidget);

    await tester.tap(find.byTooltip('Edit staff username'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('staffUsernameField')), 'Budi');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(store.staffUsername, 'Budi');
    expect(find.text('Budi'), findsOneWidget);
  });

  test('record serialization preserves upload fields', () {
    final uploadedAt = DateTime.utc(2026, 5, 5, 7, 30);
    final record = CounterRecord(
      id: '1',
      category: CounterCategory.maleCash,
      createdAt: DateTime.utc(2026, 5, 5, 7, 29),
      status: RecordStatus.uploaded,
      uploadedAt: uploadedAt,
      uploadBatchId: 'batch-1',
    );

    final restored = CounterRecord.fromJson(record.toJson());

    expect(restored.id, '1');
    expect(restored.category, CounterCategory.maleCash);
    expect(restored.status, RecordStatus.uploaded);
    expect(restored.uploadedAt, uploadedAt);
    expect(restored.uploadBatchId, 'batch-1');
  });

  test('pending upload records excludes uploaded and voided rows', () {
    final createdAt = DateTime.utc(2026, 5, 5);
    final records = [
      CounterRecord(
        id: 'pending',
        category: CounterCategory.maleCash,
        createdAt: createdAt,
        status: RecordStatus.pending,
      ),
      CounterRecord(
        id: 'uploaded',
        category: CounterCategory.maleCash,
        createdAt: createdAt,
        status: RecordStatus.uploaded,
      ),
      CounterRecord(
        id: 'voided',
        category: CounterCategory.maleCash,
        createdAt: createdAt,
        status: RecordStatus.voided,
      ),
    ];

    expect(pendingUploadRecords(records).map((record) => record.id), [
      'pending',
    ]);
  });

  test(
    'Apps Script uploader follows Google redirect response with GET',
    () async {
      final requestedUris = <Uri>[];
      Map<String, dynamic>? payload;
      final uploader = AppsScriptRecordUploader(
        webAppUrl: 'https://script.google.com/macros/s/test/exec',
        client: MockClient((request) async {
          requestedUris.add(request.url);
          if (requestedUris.length == 1) {
            payload = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(
              '<HTML><BODY>The document has moved '
              '<A HREF="https://script.googleusercontent.com/macros/echo?x=1">'
              'here</A>.</BODY></HTML>',
              302,
            );
          }

          expect(request.method, 'GET');
          return http.Response('{"success":true}', 200);
        }),
      );

      await uploader.upload([
        CounterRecord(
          id: 'pending',
          category: CounterCategory.maleCash,
          createdAt: DateTime.utc(2026, 5, 5),
          status: RecordStatus.pending,
        ),
      ], staffUsername: 'Ayu');

      expect(requestedUris, hasLength(2));
      expect(requestedUris.last.host, 'script.googleusercontent.com');
      expect(payload?['staffUsername'], 'Ayu');
      expect(payload?['records'], isNotEmpty);
    },
  );
}

Finder _counterTileText(String category, String count) {
  final value = CounterCategory.values
      .firstWhere((counterCategory) => counterCategory.label == category)
      .value;
  return find.byWidgetPredicate(
    (widget) =>
        widget.key == Key('count-$value') &&
        widget is Text &&
        widget.data == count,
  );
}

Widget _testApp({CounterRecordStore? store, RecordUploader? uploader}) {
  return MyApp(
    store: store ?? _MemoryStore(),
    uploader: uploader ?? _FakeUploader(),
  );
}

class _MemoryStore implements CounterRecordStore {
  _MemoryStore({this.staffUsername = 'test-staff'});

  var records = <CounterRecord>[];
  String staffUsername;

  @override
  Future<List<CounterRecord>> loadRecords() async => records;

  @override
  Future<void> saveRecords(List<CounterRecord> records) async {
    this.records = records;
  }

  @override
  Future<String> loadStaffUsername() async => staffUsername;

  @override
  Future<void> saveStaffUsername(String username) async {
    staffUsername = username;
  }
}

class _FakeUploader implements RecordUploader {
  int uploadedRecordCount = 0;

  @override
  Future<UploadResult> upload(
    List<CounterRecord> records, {
    required String staffUsername,
  }) async {
    uploadedRecordCount += records.length;
    return UploadResult(
      uploadBatchId: 'test-upload',
      uploadedAt: DateTime.utc(2026, 5, 5),
    );
  }
}
