import 'dart:math';
import 'package:flutter/material.dart';
import '../themes/theme_extensions.dart';

class AngleIndicator extends StatelessWidget {
  final double currentAngle;
  final double? referenceAngle;
  final bool showReference;

  const AngleIndicator({
    super.key,
    required this.currentAngle,
    this.referenceAngle,
    this.showReference = false,
  });

  @override
  Widget build(BuildContext context) {
    final themeExt = Theme.of(context).extension<AppThemeExtension>()!;

    return CustomPaint(
      size: const Size(180, 180),
      painter: _AnglePainter(
        currentAngle: currentAngle,
        referenceAngle: referenceAngle,
        showReference: showReference,
        primaryColor: themeExt.primaryColor,
        secondaryColor: themeExt.secondaryColor,
        textColor: themeExt.textPrimaryColor,
        borderColor: themeExt.textSecondaryColor.withOpacity(0.2),
      ),
    );
  }
}

class _AnglePainter extends CustomPainter {
  final double currentAngle;
  final double? referenceAngle;
  final bool showReference;
  final Color primaryColor;
  final Color secondaryColor;
  final Color textColor;
  final Color borderColor;

  _AnglePainter({
    required this.currentAngle,
    this.referenceAngle,
    this.showReference = false,
    required this.primaryColor,
    required this.secondaryColor,
    required this.textColor,
    required this.borderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.35;
    final circleRadius = size.width * 0.05;

    final userPaint = Paint()
      ..color = primaryColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final paintBorder = Paint()
      ..color = borderColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final paintBorderCircle = Paint()
      ..color = borderColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final circleRect = Rect.fromCircle(center: center, radius: radius);
    final circlePath = Path()..addArc(circleRect, -pi, pi);

    final smallCircleRect =
        Rect.fromCircle(center: center, radius: circleRadius);
    final smallCirclePath = Path()..addArc(smallCircleRect, -pi, pi);

    const dashLen = 3.0;
    const gapLen = 6.0;
    final dashedCircle = _dashPath(circlePath, dash: dashLen, gap: gapLen);

    // Текущий угол в радианах
    final angleRad = currentAngle * pi / 180;

    final end = Offset(
      center.dx + radius * cos(angleRad),
      center.dy - radius * sin(angleRad),
    );

    final borderStart = Offset(
      center.dx + radius,
      center.dy,
    );

    final borderEnd = Offset(
      center.dx - radius,
      center.dy,
    );

    // Рисуем эталонный угол (если есть)
    if (showReference && referenceAngle != null) {
      final refAngleRad = referenceAngle! * pi / 180;
      final refEnd = Offset(
        center.dx + radius * cos(refAngleRad),
        center.dy - radius * sin(refAngleRad),
      );

      final refPaint = Paint()
        ..color = secondaryColor.withOpacity(0.6)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;

      canvas.drawLine(center, refEnd, refPaint);
    }

    // Рисуем угол пользователя
    canvas.drawLine(center, end, userPaint);

    canvas.drawLine(borderStart, borderEnd, paintBorder);
    canvas.drawPath(dashedCircle, paintBorderCircle);
    canvas.drawPath(smallCirclePath, paintBorderCircle);

    // Текст угла
    final textPainter = TextPainter(
      text: TextSpan(
        text: '${currentAngle.toStringAsFixed(0)}°',
        style: TextStyle(
            color: textColor, fontSize: 20, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2, center.dy + radius + 12),
    );
  }

  Path _dashPath(Path source, {required double dash, required double gap}) {
    final out = Path();
    for (final metric in source.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + dash).clamp(0.0, metric.length);
        out.addPath(metric.extractPath(distance, next), Offset.zero);
        distance += dash + gap;
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
