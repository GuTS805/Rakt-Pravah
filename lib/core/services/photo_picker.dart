import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

enum PhotoSource { camera, gallery }

/// Profile photos live in Firestore rather than Firebase Storage, which needs
/// a paid plan. That only works while they stay tiny, because the photo is
/// copied onto every request and every open request list downloads it. So
/// every photo is cropped square, scaled down and saved as a JPEG: about 5-10
/// KB whatever was picked, PNG screenshots included.
class Photos {
  const Photos._();

  /// Side of the square, in pixels. The biggest place a photo is shown is the
  /// left 30% of a card, roughly 110 logical pixels wide.
  static const side = 160;

  /// Tried in turn until the result fits: an ordinary photo is about 8 KB at
  /// the first, a very detailed one needs the lower settings.
  static const qualities = [75, 55, 35];

  /// What the security rules accept is 60000; staying well under keeps every
  /// request small.
  static const maxEncodedLength = 30000;

  /// [bytes] (any picture format) as a small square JPEG, or null when they
  /// aren't a picture or can't be made small enough.
  static Uint8List? prepare(List<int> bytes) {
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
      // Decoding a full-size camera picture is wasteful; let the platform
      // shrink it first, then [Photos.prepare] makes it square and small.
      maxWidth: 512,
      maxHeight: 512,
      preferredCameraDevice: CameraDevice.front,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    // Off the UI thread: decoding and encoding take a moment on a phone.
    final small = await compute(Photos.prepare, bytes);
    return small == null ? null : Photos.encode(small);
  }
}
