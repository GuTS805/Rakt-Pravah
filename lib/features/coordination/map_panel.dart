import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/models.dart';

/// A lightweight destination panel. It intentionally does NOT claim to be a
/// live GPS map (no map SDK is wired in this build) — it shows the destination
/// context with a schematic backdrop. When a maps SDK is added, this widget is
/// the single place to swap in a real map tile.
class MapPanel extends StatelessWidget {
  const MapPanel({super.key, required this.destination});
  final Destination destination;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ClipRRect(
      borderRadius: AppRadius.cardLg,
      child: Container(
        height: 150,
        decoration: BoxDecoration(
          color: c.surfaceMuted,
          border: Border.all(color: c.border),
          borderRadius: AppRadius.cardLg,
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(painter: _GridPainter(c.border)),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.location_on_rounded, color: c.brand, size: 34),
                  const SizedBox(height: AppSpacing.xs),
                  Text(destination.name,
                      style: context.text.titleSmall,
                      textAlign: TextAlign.center),
                ],
              ),
            ),
            Positioned(
              left: AppSpacing.md,
              bottom: AppSpacing.md,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: 4),
                decoration: BoxDecoration(
                  color: c.surface.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: c.border),
                ),
                child: Text(destination.address,
                    style: context.text.bodySmall),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter(this.line);
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = line.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    const step = 26.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) => old.line != line;
}
