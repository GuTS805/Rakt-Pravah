import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_typography.dart';

/// Initials avatar. No photo dependency — a calm, consistent monogram.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.initials, this.size = 40, this.onTap});

  final String initials;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final avatar = Container(
      height: size,
      width: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.surfaceMuted,
        shape: BoxShape.circle,
        border: Border.all(color: c.border),
      ),
      child: Text(
        initials,
        style: AppTypography.mono(
          size: size * 0.34,
          weight: FontWeight.w600,
          color: c.textSecondary,
        ),
      ),
    );
    if (onTap == null) return avatar;
    return InkResponse(onTap: onTap, radius: size * 0.7, child: avatar);
  }
}
