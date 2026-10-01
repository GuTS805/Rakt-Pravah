import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

enum PhotoSource { camera, gallery }

class PhotoValidationException implements Exception {
  const PhotoValidationException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Profile photos live in Firestore rather than Firebase Storage, which needs
/// a paid plan. That only works while they stay tiny, because the photo is
/// copied onto every request and every open request list downloads it. So
/// every photo is cropped square, scaled down and saved as a JPEG: about 5-15
/// KB whatever was picked, PNG screenshots and WebP included.
class Photos {
  const Photos._();

  /// Side of the square, in pixels.
  static const side = 180;

  /// Maximum allowed upload file size: 5 MB.
  static const maxFileSizeBytes = 5 * 1024 * 1024;

  /// Tried in turn until the result fits: an ordinary photo is about 8 KB at
  /// the first, a very detailed one needs the lower settings.
  static const qualities = [80, 65, 50, 35];

  /// What the security rules accept is 60000; staying well under keeps every
  /// request small.
  static const maxEncodedLength = 30000;

  /// Checks if binary header matches supported image types (JPEG, PNG, WEBP).
  static bool isSupportedBytes(List<int> bytes) {
    if (bytes.length < 4) return false;
    // JPEG magic bytes: FF D8
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) return true;
    // PNG magic bytes: 89 50 4E 47
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return true;
    }
    // WEBP magic bytes: RIFF....WEBP
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return true;
    }
    return false;
  }

  /// Checks if file path / name ends with supported image extensions.
  static bool isSupportedExtension(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp');
  }

  /// [bytes] (any picture format) as a small square JPEG, or null when they
  /// aren't a picture, exceed size, or can't be made small enough.
  static Uint8List? prepare(List<int> bytes) {
    if (bytes.length > maxFileSizeBytes) return null;
    final img.Image? decoded;
    try {
      decoded = img.decodeImage(Uint8List.fromList(bytes));
    } catch (_) {
      // The decoders throw on files that only look like pictures.
      return null;
    }
    if (decoded == null) return null;
    final square = img.copyResizeCropSquare(decoded, size: side);
    for (final quality in qualities) {
      final jpeg = Uint8List.fromList(img.encodeJpg(square, quality: quality));
      if (base64Encode(jpeg).length <= maxEncodedLength) return jpeg;
    }
    return null;
  }

  /// Base64 of [bytes], or null when it is too big to keep.
  static String? encode(List<int> bytes) {
    final encoded = base64Encode(bytes);
    return encoded.length <= maxEncodedLength ? encoded : null;
  }
}

/// Takes or chooses a picture and returns it ready to store, or null when the
/// person backs out or the file isn't a usable picture. A seam, so tests don't
/// need a camera.
class PhotoPicker {
  const PhotoPicker();

  Future<String?> pick(PhotoSource source) async {
    final file = await ImagePicker().pickImage(
      source: source == PhotoSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      preferredCameraDevice: CameraDevice.front,
    );
    if (file == null) return null;

    final bytes = await file.readAsBytes();
    if (bytes.length > Photos.maxFileSizeBytes) {
      throw const PhotoValidationException(
        'Maximum file size is 5 MB. Please select a smaller photo.',
      );
    }

    if (!Photos.isSupportedExtension(file.name) &&
        !Photos.isSupportedBytes(bytes)) {
      throw const PhotoValidationException(
        'Only JPG, JPEG, PNG, or WEBP images are supported.',
      );
    }

    // Off the UI thread: decoding and encoding take a moment on a phone.
    final small = await compute(Photos.prepare, bytes);
    if (small == null) {
      throw const PhotoValidationException(
        'Could not process that image. Please select a valid JPG, PNG, or WEBP photo.',
      );
    }
    return Photos.encode(small);
  }
}
