import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_config.dart';
import 'counter_record.dart';

class UploadResult {
  const UploadResult({required this.uploadBatchId, required this.uploadedAt});

  final String uploadBatchId;
  final DateTime uploadedAt;
}

abstract class RecordUploader {
  Future<UploadResult> upload(
    List<CounterRecord> records, {
    required String staffUsername,
  });
}

class AppsScriptRecordUploader implements RecordUploader {
  AppsScriptRecordUploader({
    http.Client? client,
    String webAppUrl = googleAppsScriptWebAppUrl,
  }) : _client = client ?? http.Client(),
       _webAppUrl = webAppUrl;

  final http.Client _client;
  final String _webAppUrl;

  @override
  Future<UploadResult> upload(
    List<CounterRecord> records, {
    required String staffUsername,
  }) async {
    if (_webAppUrl.isEmpty) {
      throw const UploadException(
        'Set googleAppsScriptWebAppUrl in lib/app_config.dart before uploading.',
      );
    }
    if (staffUsername.trim().isEmpty) {
      throw const UploadException('Enter the staff username before uploading.');
    }
    if (records.isEmpty) {
      throw const UploadException('There are no pending records to upload.');
    }

    final uploadedAt = DateTime.now();
    final uploadBatchId = _buildUploadBatchId(uploadedAt);
    final body = jsonEncode({
      'sheetName': _buildSheetName(uploadedAt),
      'uploadId': uploadBatchId,
      'uploadedAt': uploadedAt.toIso8601String(),
      'staffUsername': staffUsername.trim(),
      'records': records.map((record) => record.toUploadJson()).toList(),
    });
    final response = await _postFollowingRedirects(Uri.parse(_webAppUrl), body);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw UploadException(
        'Upload failed with HTTP ${response.statusCode}: ${response.body}',
      );
    }

    final responseBody = response.body.trim();
    if (responseBody.isNotEmpty) {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map<dynamic, dynamic> && decoded['success'] == false) {
        throw UploadException(
          (decoded['error'] as String?) ??
              'The spreadsheet rejected the upload.',
        );
      }
    }

    return UploadResult(uploadBatchId: uploadBatchId, uploadedAt: uploadedAt);
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

String _buildUploadBatchId(DateTime dateTime) {
  return 'upload-${_compactDateTime(dateTime)}';
}

String _buildSheetName(DateTime dateTime) {
  return 'Event Upload ${_displayDateTime(dateTime)}';
}

String _compactDateTime(DateTime dateTime) {
  return dateTime.toIso8601String().replaceAll(RegExp(r'[^0-9]'), '');
}

String _displayDateTime(DateTime dateTime) {
  final local = dateTime.toLocal();
  return '${_twoDigits(local.year ~/ 100)}${_twoDigits(local.year % 100)}-'
      '${_twoDigits(local.month)}-${_twoDigits(local.day)} '
      '${_twoDigits(local.hour)}-${_twoDigits(local.minute)}';
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');

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
