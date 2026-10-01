import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_typography.dart';

/// A stored profile photo (base64 JPEG) filling whatever space it is given.
/// Shows nothing when the text can't be decoded, so callers put their own
/// fallback underneath.
class MemoryPhoto extends StatefulWidget {
  const MemoryPhoto({super.key, required this.photo, this.fit = BoxFit.cover});

  final String photo;
  final BoxFit fit;

  @override
  State<MemoryPhoto> createState() => _MemoryPhotoState();
}

class _MemoryPhotoState extends State<MemoryPhoto> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = _decode(widget.photo);
  }

  @override
  void didUpdateWidget(MemoryPhoto old) {
    super.didUpdateWidget(old);
    if (old.photo != widget.photo) _bytes = _decode(widget.photo);
  }

  // Decoded once per photo, not per build: a new list each time would make
  // the image reload and flicker.
  static Uint8List? _decode(String photo) {
    try {
      return base64Decode(photo);
    } on FormatException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes == null) return const SizedBox.shrink();
    return Image.memory(
      bytes,
      fit: widget.fit,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
  }
}

/// Round profile picture: a stored [photo] (base64), else the image at
/// [photoUrl], else the person's initials.
class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    required this.initials,
    this.photo,
    this.photoUrl,
    this.size = 40,
    this.onTap,
  });

  final String initials;
  final String? photo;
  final String? photoUrl;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final url = photoUrl?.trim();
    final avatar = Container(
      height: size,
      width: size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.surfaceMuted,
        shape: BoxShape.circle,
        border: Border.all(color: c.border),
      ),
      child: Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [
          Center(
            child: Text(
              initials,
              style: AppTypography.mono(
                size: size * 0.34,
                weight: FontWeight.w600,
                color: c.textSecondary,
              ),
            ),
          ),
          if (photo != null)
            MemoryPhoto(photo: photo!)
          else if (url != null && url.isNotEmpty)
            Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
        ],
      ),
    );
    if (onTap == null) return avatar;
    return InkResponse(onTap: onTap, radius: size * 0.7, child: avatar);
  }
}
