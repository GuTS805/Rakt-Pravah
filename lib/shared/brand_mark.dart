import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// BloodLink's mark: a blood drop with a coordination "link" node inside it.
/// Drawn (not an asset) so it scales crisply and picks up theme colors.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: size,
      width: size,
      child: CustomPaint(painter: _DropPainter(c.brand, c.onBrand)),
    );
  }
}

class _DropPainter extends CustomPainter {
  _DropPainter(this.fill, this.node);
  final Color fill;
  final Color node;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path();
    // Teardrop: pointed top, round bottom.
    path.moveTo(w * 0.5, 0);
    path.cubicTo(w * 0.5, h * 0.28, w, h * 0.42, w, h * 0.62);
    path.arcToPoint(
      Offset(w * 0.5, h),
      radius: Radius.circular(w * 0.5),
      clockwise: true,
    );
    path.arcToPoint(
      Offset(0, h * 0.62),
      radius: Radius.circular(w * 0.5),
      clockwise: true,
    );
    path.cubicTo(0, h * 0.42, w * 0.5, h * 0.28, w * 0.5, 0);
    path.close();

    canvas.drawPath(path, Paint()..color = fill);

    // A small "link" node: two joined dots signifying donor <-> requester.
    final cy = h * 0.62;
    final r = w * 0.09;
    final p = Paint()..color = node;
    canvas.drawCircle(Offset(w * 0.38, cy), r, p);
    canvas.drawCircle(Offset(w * 0.62, cy), r, p);
    canvas.drawRect(
      Rect.fromLTWH(w * 0.38, cy - r * 0.45, w * 0.24, r * 0.9),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant _DropPainter old) =>
      old.fill != fill || old.node != node;
}
