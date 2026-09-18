import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Rakt Pravah's mark: the blood drop with two hands inside it.
///
/// Presented on a white chip rather than free-standing, because the hands are
/// white negative space that opens out to the background — lift the artwork
/// off white and the hands turn into holes. White is a real colour in this
/// mark, so the chip is part of it. The chip also keeps the mark legible on
/// both themes without needing two versions of the file.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        // Without this the chip dissolves into a light background.
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      // A circle inscribed in the square artwork would clip the drop's point
      // and shoulders, so the art is inset to sit inside the circle rather
      // than being cropped by it.
      child: Padding(
        padding: EdgeInsets.all(size * 0.13),
        child: Image.asset(
          'assets/logo_mark.png',
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}
