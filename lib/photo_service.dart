import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

enum PhotoSource { camera, gallery }

abstract class PhotoService {
  /// Lets the user take or choose a photo and stores a copy on the device.
  ///
  /// Returns the stored file path, or null when the user cancels.
  Future<String?> capturePhoto(PhotoSource source, {required String recordId});

  Future<void> deletePhoto(String path);
}

class DevicePhotoService implements PhotoService {
  DevicePhotoService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  // Photos are compressed once when attached, so uploads stay small. The
  // shorter side is scaled down to about 1080px, which keeps a QRIS payment
  // screen readable at roughly 150-250 KB per photo.
  static const _compressedShortSide = 1080;
  static const _compressedQuality = 60;

  final ImagePicker _picker;

  @override
  Future<String?> capturePhoto(
    PhotoSource source, {
    required String recordId,
  }) async {
    final picked = await _picker.pickImage(
      source: source == PhotoSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      requestFullMetadata: false,
    );
    if (picked == null) {
      return null;
    }

    // Picker results can live in a temporary cache, so keep our own copy that
    // survives until the record is uploaded.
    final documents = await getApplicationDocumentsDirectory();
    final photosDirectory = Directory('${documents.path}/photos');
    await photosDirectory.create(recursive: true);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final storedBasePath = '${photosDirectory.path}/$recordId-$timestamp';

    final compressedPath = await _compress(picked.path, '$storedBasePath.jpg');
    if (compressedPath != null) {
      await _deletePickerCache(picked.path);
      return compressedPath;
    }

    // Formats the compressor cannot read are kept as they are.
    final storedPath = '$storedBasePath${_extensionOf(picked.path)}';
    await File(picked.path).copy(storedPath);
    await _deletePickerCache(picked.path);
    return storedPath;
  }

  Future<String?> _compress(String sourcePath, String targetPath) async {
    try {
      final compressed = await FlutterImageCompress.compressAndGetFile(
        sourcePath,
        targetPath,
        minWidth: _compressedShortSide,
        minHeight: _compressedShortSide,
        quality: _compressedQuality,
        format: CompressFormat.jpeg,
      );
      return compressed?.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> _deletePickerCache(String path) async {
    try {
      await File(path).delete();
    } catch (_) {
      // The picker may hand back a file we are not allowed to delete.
    }
  }

  @override
  Future<void> deletePhoto(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}

String _extensionOf(String path) {
  final dotIndex = path.lastIndexOf('.');
  if (dotIndex == -1 || dotIndex < path.lastIndexOf('/')) {
    return '.jpg';
  }
  return path.substring(dotIndex).toLowerCase();
}
