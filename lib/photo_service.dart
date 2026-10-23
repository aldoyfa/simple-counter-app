import 'dart:io';

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
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 75,
    );
    if (picked == null) {
      return null;
    }

    // Picker results can live in a temporary cache, so keep our own copy that
    // survives until the record is uploaded.
    final documents = await getApplicationDocumentsDirectory();
    final photosDirectory = Directory('${documents.path}/photos');
    await photosDirectory.create(recursive: true);
    final extension = _extensionOf(picked.path);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final storedPath = '${photosDirectory.path}/$recordId-$timestamp$extension';
    await File(picked.path).copy(storedPath);
    return storedPath;
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
