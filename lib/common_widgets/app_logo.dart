import 'package:flutter/material.dart';
import '../app/theme.dart';

/// The AVEC mark: "A" (apex up) stacked over "V" (apex down) with a thin
/// gap, tracing an implied diamond from the brand's first two letters.
class AvecMark extends StatelessWidget {
  const AvecMark({
    super.key,
    this.size = 44,
    this.markColor,
    this.backgroundColor,
  });

  final double size;
  final Color? markColor;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.orange,
        borderRadius: BorderRadius.circular(size * 0.2),
      ),
      child: CustomPaint(
        size: Size(size, size),
        painter: _AvecMarkPainter(
          markColor: markColor ?? AppColors.orangeOn,
        ),
      ),
    );
  }
}

class _AvecMarkPainter extends CustomPainter {
  _AvecMarkPainter({required this.markColor});
  final Color markColor;

  // Design grid is 240x240 — everything below scales to the actual size.
  static const double _grid = 240;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / _grid;
    canvas.scale(scale, scale);

    final markPaint = Paint()..color = markColor;

    final topTriangle = Path()
      ..moveTo(120, 40)
      ..lineTo(58, 128)
      ..lineTo(182, 128)
      ..close();
    canvas.drawPath(topTriangle, markPaint);

    final bottomTriangle = Path()
      ..moveTo(58, 138)
      ..lineTo(182, 138)
      ..lineTo(120, 226)
      ..close();
    canvas.drawPath(bottomTriangle, markPaint);
  }

  @override
  bool shouldRepaint(covariant _AvecMarkPainter oldDelegate) {
    return oldDelegate.markColor != markColor;
  }
}

/// The lockup used across the Operations (POS) app: AvecMark + "AVEC
/// OPERATIONS" wordmark, matching Manager's lockup style.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.markSize = 40});
  final double markSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AvecMark(size: markSize),
        SizedBox(width: markSize * 0.3),
        RichText(
          text: TextSpan(
            style: TextStyle(
              fontSize: markSize * 0.42,
              fontWeight: FontWeight.w800,
              letterSpacing: markSize * 0.05,
            ),
            children: [
              const TextSpan(
                text: 'AVEC ',
                style: TextStyle(color: AppColors.textPrimary),
              ),
              TextSpan(
                text: 'OPERATIONS',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
