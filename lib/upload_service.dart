import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'app_config.dart';
import 'counter_record.dart';

typedef PhotoBytesReader = Future<List<int>> Function(String path);

abstract class RecordUploader {
  /// Uploads a single record, including its photo when it has one.
  ///
  /// Uploading the same record twice must not create a duplicate row, so a
  /// retry after a lost response is safe.
  Future<void> uploadRecord(
    CounterRecord record, {
    required String staffUsername,
    required String uploadBatchId,
    required DateTime uploadedAt,
  });
}

class AppsScriptRecordUploader implements RecordUploader {
  AppsScriptRecordUploader({
    http.Client? client,
    String webAppUrl = googleAppsScriptWebAppUrl,
    PhotoBytesReader? readPhotoBytes,
  }) : _client = client ?? http.Client(),
       _webAppUrl = webAppUrl,
       _readPhotoBytes = readPhotoBytes ?? _readFileBytes;

  static const _requestTimeout = Duration(seconds: 90);

  final http.Client _client;
  final String _webAppUrl;
  final PhotoBytesReader _readPhotoBytes;

  @override
  Future<void> uploadRecord(
    CounterRecord record, {
    required String staffUsername,
    required String uploadBatchId,
    required DateTime uploadedAt,
  }) async {
    if (_webAppUrl.isEmpty) {
      throw const UploadException(
        'The upload URL is missing. Build the app with '
        '--dart-define-from-file=.env.',
      );
    }
    if (staffUsername.trim().isEmpty) {
      throw const UploadException('Enter the staff username before uploading.');
    }

    final body = jsonEncode({
      'uploadId': uploadBatchId,
      'uploadedAt': uploadedAt.toUtc().toIso8601String(),
      'staffUsername': staffUsername.trim(),
      'record': record.toUploadJson(),
      'photo': await _photoPayload(record),
    });

    final http.Response response;
    try {
      response = await _postFollowingRedirects(
        Uri.parse(_webAppUrl),
        body,
      ).timeout(_requestTimeout);
    } on UploadException {
      rethrow;
    } catch (error) {
      throw UploadException('Upload failed, check the connection: $error');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw UploadException(
        'Upload failed with HTTP ${response.statusCode}: ${response.body}',
      );
    }

    final responseBody = response.body.trim();
    if (responseBody.isNotEmpty) {
      final Object? decoded;
      try {
        decoded = jsonDecode(responseBody);
      } on FormatException {
        throw const UploadException(
          'The spreadsheet returned an unexpected response.',
        );
      }
      if (decoded is Map<dynamic, dynamic> && decoded['success'] == false) {
        throw UploadException(
          (decoded['error'] as String?) ??
              'The spreadsheet rejected the upload.',
        );
      }
    }
  }

  Future<Map<String, String>?> _photoPayload(CounterRecord record) async {
    final photoPath = record.photoPath;
    if (photoPath == null) {
      return null;
    }

    final List<int> bytes;
    try {
      bytes = await _readPhotoBytes(photoPath);
    } catch (_) {
      throw UploadException(
        'The photo for ${record.category.label} at '
        '${record.createdAt.toLocal()} is missing. Replace or remove it in '
        'history.',
      );
    }

    final extension = _photoExtension(photoPath);
    return {
      'fileName': '${record.id}$extension',
      'mimeType': _mimeTypes[extension] ?? 'image/jpeg',
      'data': base64Encode(bytes),
    };
  }

  Future<http.Response> _postFollowingRedirects(Uri uri, String body) async {
    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: body,
    );

    if (!_isRedirect(response.statusCode)) {
      return response;
    }

    var redirectUri = _redirectUri(response);
    if (redirectUri == null) {
      return response;
    }

    var currentUri = uri.resolveUri(redirectUri);
    for (var attempt = 0; attempt < 4; attempt += 1) {
      final redirectResponse = await _client.get(currentUri);
      if (!_isRedirect(redirectResponse.statusCode)) {
        return redirectResponse;
      }

      redirectUri = _redirectUri(redirectResponse);
      if (redirectUri == null) {
        return redirectResponse;
      }
      currentUri = currentUri.resolveUri(redirectUri);
    }

    throw const UploadException('Upload failed after too many redirects.');
  }
}

class UploadException implements Exception {
  const UploadException(this.message);

  final String message;

  @override
  String toString() => message;
}

String buildUploadBatchId(DateTime dateTime) {
  return 'upload-${dateTime.toIso8601String().replaceAll(RegExp(r'[^0-9]'), '')}';
}

const _mimeTypes = {
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.webp': 'image/webp',
  '.heic': 'image/heic',
  '.gif': 'image/gif',
};

String _photoExtension(String path) {
  final dotIndex = path.lastIndexOf('.');
  if (dotIndex == -1 || dotIndex < path.lastIndexOf('/')) {
    return '.jpg';
  }
  return path.substring(dotIndex).toLowerCase();
}

Future<List<int>> _readFileBytes(String path) => File(path).readAsBytes();

bool _isRedirect(int statusCode) {
  return statusCode == 301 ||
      statusCode == 302 ||
      statusCode == 303 ||
      statusCode == 307 ||
      statusCode == 308;
}

Uri? _redirectUri(http.Response response) {
  final location = response.headers['location'];
  if (location != null && location.isNotEmpty) {
    return Uri.parse(location);
  }

  final hrefMatch = RegExp(
    r'''href=["']([^"']+)["']''',
    caseSensitive: false,
  ).firstMatch(response.body);
  final href = hrefMatch?.group(1)?.replaceAll('&amp;', '&');
  if (href == null || href.isEmpty) {
    return null;
  }

  return Uri.parse(href);
}
