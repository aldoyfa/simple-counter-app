import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_counter_app/counter_record.dart';
import 'package:simple_counter_app/main.dart';
import 'package:simple_counter_app/photo_service.dart';
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

    expect(uploader.uploadedRecords, hasLength(1));
    expect(find.text('Pending: 0'), findsOneWidget);
    expect(find.text('Uploaded: 1'), findsOneWidget);
  });

  testWidgets('a failed upload keeps the remaining records pending', (
    tester,
  ) async {
    final uploader = _FakeUploader(failOnCall: 2);
    final store = _MemoryStore();
    await tester.pumpWidget(_testApp(store: store, uploader: uploader));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Male Cash'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Male QRIS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Female QRIS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();

    expect(uploader.uploadedRecords, hasLength(1));
    expect(find.text('Uploaded: 1'), findsOneWidget);
    expect(find.text('Pending: 2'), findsOneWidget);
    expect(find.textContaining('1 of 3 records uploaded.'), findsOneWidget);
    expect(
      store.records.where((record) => record.status == RecordStatus.uploaded),
      hasLength(1),
    );
  });

  testWidgets('a photo can be linked right after tapping a counter', (
    tester,
  ) async {
    final store = _MemoryStore();
    final photos = _FakePhotoService();
    final uploader = _FakeUploader();
    await tester.pumpWidget(
      _testApp(store: store, uploader: uploader, photoService: photos),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Female QRIS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take photo'));
    await tester.pumpAndSettle();

    expect(photos.requestedSources, [PhotoSource.camera]);
    expect(store.records.single.photoPath, '/photos/photo-1.jpg');

    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();

    expect(uploader.uploadedRecords.single.photoPath, '/photos/photo-1.jpg');
  });

  testWidgets('photos can be replaced and removed from history', (
    tester,
  ) async {
    final store = _MemoryStore();
    final photos = _FakePhotoService();
    await tester.pumpWidget(_testApp(store: store, photoService: photos));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Male QRIS'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.history));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose from gallery'));
    await tester.pumpAndSettle();
    expect(store.records.single.photoPath, '/photos/photo-1.jpg');

    await tester.tap(find.byTooltip('Photo options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose from gallery'));
    await tester.pumpAndSettle();
    expect(store.records.single.photoPath, '/photos/photo-2.jpg');
    expect(photos.deletedPaths, ['/photos/photo-1.jpg']);

    await tester.tap(find.byTooltip('Photo options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove photo'));
    await tester.pumpAndSettle();
    expect(store.records.single.photoPath, isNull);
    expect(photos.deletedPaths, ['/photos/photo-1.jpg', '/photos/photo-2.jpg']);
    expect(find.byTooltip('Add photo'), findsOneWidget);
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
      photoPath: '/photos/1.jpg',
    );

    final restored = CounterRecord.fromJson(record.toJson());

    expect(restored.id, '1');
    expect(restored.category, CounterCategory.maleCash);
    expect(restored.status, RecordStatus.uploaded);
    expect(restored.uploadedAt, uploadedAt);
    expect(restored.uploadBatchId, 'batch-1');
    expect(restored.photoPath, '/photos/1.jpg');
    expect(restored.copyWith(clearPhoto: true).photoPath, isNull);
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

      await uploader.uploadRecord(
        CounterRecord(
          id: 'pending',
          category: CounterCategory.maleCash,
          createdAt: DateTime.utc(2026, 5, 5),
          status: RecordStatus.pending,
        ),
        staffUsername: 'Ayu',
        uploadBatchId: 'upload-1',
        uploadedAt: DateTime.utc(2026, 5, 5, 1),
      );

      expect(requestedUris, hasLength(2));
      expect(requestedUris.last.host, 'script.googleusercontent.com');
      expect(payload?['staffUsername'], 'Ayu');
      expect(payload?['record']['id'], 'pending');
      expect(payload?['photo'], isNull);
    },
  );

  test('Apps Script uploader sends the photo with the record', () async {
    Map<String, dynamic>? payload;
    final uploader = AppsScriptRecordUploader(
      webAppUrl: 'https://script.google.com/macros/s/test/exec',
      readPhotoBytes: (path) async => [1, 2, 3],
      client: MockClient((request) async {
        payload = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{"success":true}', 200);
      }),
    );

    await uploader.uploadRecord(
      CounterRecord(
        id: '123-female_qris',
        category: CounterCategory.femaleQris,
        createdAt: DateTime.utc(2026, 10, 31, 3, 15),
        status: RecordStatus.pending,
        photoPath: '/photos/123-female_qris-9.jpg',
      ),
      staffUsername: 'Ayu',
      uploadBatchId: 'upload-1',
      uploadedAt: DateTime.utc(2026, 10, 31, 4),
    );

    expect(payload?['uploadId'], 'upload-1');
    expect(payload?['record'], {
      'id': '123-female_qris',
      'category': 'female_qris',
      'categoryLabel': 'Female QRIS',
      'gender': 'Female',
      'payment': 'QRIS',
      'createdAt': '2026-10-31T03:15:00.000Z',
    });
    expect(payload?['photo'], {
      'fileName': '123-female_qris.jpg',
      'mimeType': 'image/jpeg',
      'data': base64Encode([1, 2, 3]),
    });
  });

  test('Apps Script uploader reports a missing photo file', () async {
    final uploader = AppsScriptRecordUploader(
      webAppUrl: 'https://script.google.com/macros/s/test/exec',
      readPhotoBytes: (path) async => throw const FileSystemException('gone'),
      client: MockClient((request) async {
        fail('No request should be sent without the photo.');
      }),
    );

    expect(
      uploader.uploadRecord(
        CounterRecord(
          id: '1',
          category: CounterCategory.maleQris,
          createdAt: DateTime.utc(2026, 10, 31),
          status: RecordStatus.pending,
          photoPath: '/photos/missing.jpg',
        ),
        staffUsername: 'Ayu',
        uploadBatchId: 'upload-1',
        uploadedAt: DateTime.utc(2026, 10, 31),
      ),
      throwsA(isA<UploadException>()),
    );
  });
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

Widget _testApp({
  CounterRecordStore? store,
  RecordUploader? uploader,
  PhotoService? photoService,
}) {
  return MyApp(
    store: store ?? _MemoryStore(),
    uploader: uploader ?? _FakeUploader(),
    photoService: photoService ?? _FakePhotoService(),
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
  _FakeUploader({this.failOnCall});

  final int? failOnCall;
  final uploadedRecords = <CounterRecord>[];
  var _calls = 0;

  @override
  Future<void> uploadRecord(
    CounterRecord record, {
    required String staffUsername,
    required String uploadBatchId,
    required DateTime uploadedAt,
  }) async {
    _calls += 1;
    if (_calls == failOnCall) {
      throw const UploadException('No connection.');
    }
    uploadedRecords.add(record);
  }
}

class _FakePhotoService implements PhotoService {
  final requestedSources = <PhotoSource>[];
  final deletedPaths = <String>[];

  @override
  Future<String?> capturePhoto(
    PhotoSource source, {
    required String recordId,
  }) async {
    requestedSources.add(source);
    return '/photos/photo-${requestedSources.length}.jpg';
  }

  @override
  Future<void> deletePhoto(String path) async {
    deletedPaths.add(path);
  }
}
