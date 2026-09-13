import 'package:flutter/material.dart';
import '../app/theme.dart';

/// Merged P + I + L monogram, matching the Manager app's mark.
class PilMark extends StatelessWidget {
  const PilMark({
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
    return CustomPaint(
      size: Size(size, size),
      painter: _PilMarkPainter(
        markColor: markColor ?? AppColors.orangeOn,
        backgroundColor: backgroundColor ?? AppColors.orange,
      ),
    );
  }
}

class _PilMarkPainter extends CustomPainter {
  _PilMarkPainter({required this.markColor, required this.backgroundColor});
  final Color markColor;
  final Color backgroundColor;

  static const double _grid = 240;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / _grid;
    canvas.scale(scale, scale);

    final bgPaint = Paint()..color = backgroundColor;
    final markPaint = Paint()..color = markColor;

    final badge = RRect.fromRectAndRadius(
      const Rect.fromLTWH(20, 20, 200, 200),
      const Radius.circular(48),
    );
    canvas.drawRRect(badge, bgPaint);

    final stem = RRect.fromRectAndRadius(
      const Rect.fromLTWH(75, 50, 24, 140),
      const Radius.circular(12),
    );
    canvas.drawRRect(stem, markPaint);

    final bowl = Path()
      ..moveTo(99, 50)
      ..lineTo(131, 50)
      ..arcToPoint(
        const Offset(131, 114),
        radius: const Radius.circular(32),
      )
      ..lineTo(99, 114)
      ..close();
    canvas.drawPath(bowl, markPaint);

    final foot = RRect.fromRectAndRadius(
      const Rect.fromLTWH(75, 168, 90, 22),
      const Radius.circular(11),
    );
    canvas.drawRRect(foot, markPaint);
  }

  @override
  bool shouldRepaint(covariant _PilMarkPainter oldDelegate) {
    return oldDelegate.markColor != markColor ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}

/// The lockup used across the POS app: PilMark + "POS" wordmark.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.markSize = 40});
  final double markSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PilMark(size: markSize),
        SizedBox(width: markSize * 0.3),
        Text(
          'POS',
          style: TextStyle(
            fontSize: markSize * 0.42,
            fontWeight: FontWeight.w800,
            letterSpacing: markSize * 0.06,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
