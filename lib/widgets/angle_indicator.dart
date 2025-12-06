import 'dart:math';
import 'package:flutter/material.dart';

class AngleIndicator extends StatelessWidget {
  final double currentAngle;      // текущий угол пользователя (0..180)
  final double referenceAngle;    // эталонный угол на текущем шаге

  const AngleIndicator({
    super.key,
    required this.currentAngle,
    required this.referenceAngle,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(200, 200),
      painter: _AnglePainter(
        currentAngle: currentAngle,
        referenceAngle: referenceAngle,
      ),
    );
  }
}

class _AnglePainter extends CustomPainter {
  final double currentAngle;
  final double referenceAngle;

  _AnglePainter({
    required this.currentAngle,
    required this.referenceAngle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    final radius = size.width * 0.35;

    final whitePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    final greenPaint = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    // Текущий угол (переделываем в радианы)
    final userAngleRad = currentAngle * pi / 180;

    // Эталонный угол
    final refAngleRad = referenceAngle * pi / 180;

    // Линия пользователя
    final userEnd = Offset(
      center.dx + radius * cos(userAngleRad),
      center.dy - radius * sin(userAngleRad),
    );

    // Линия эталона
    final refEnd = Offset(
      center.dx + radius * cos(refAngleRad),
      center.dy - radius * sin(refAngleRad),
    );

    // Рисуем лучи
    canvas.drawLine(center, refEnd, greenPaint);
    canvas.drawLine(center, userEnd, whitePaint);

    // Подписываем значения
    final textPainter = TextPainter(
      text: TextSpan(
        text: '${currentAngle.toStringAsFixed(0)}°',
        style: const TextStyle(color: Colors.white, fontSize: 20),
      ),
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2, center.dy + radius + 10),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
