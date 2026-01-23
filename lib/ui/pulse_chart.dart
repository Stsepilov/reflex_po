import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../themes/theme_extensions.dart';

class PulseChart extends StatelessWidget {
  final List<double> values;

  const PulseChart({super.key, required this.values});

  @override
  Widget build(BuildContext context) {
    final themeExt = Theme.of(context).extension<AppThemeExtension>()!;
    final maxX = values.isEmpty ? 1.0 : values.length.toDouble();

    // Auto-scale Y axis based on EMG values
    double maxY = 5000; // Default max for EMG
    double minY = 0;
    double interval = 1000;

    if (values.isNotEmpty) {
      final maxValue = values.reduce((a, b) => a > b ? a : b);
      final minValue = values.reduce((a, b) => a < b ? a : b);

      // Add some padding
      maxY = (maxValue * 1.2).ceilToDouble();
      minY = (minValue * 0.8).floorToDouble();

      // Calculate appropriate interval
      interval = ((maxY - minY) / 5).ceilToDouble();
      if (interval < 1) interval = 1;
    }

    return SizedBox(
      height:
          MediaQuery.of(context).size.height * 0.5, // 👈 половина экрана сверху
      child: LineChart(
        LineChartData(
          backgroundColor: Colors.transparent,

          // 👇 Auto-scaled Y axis for EMG values
          minY: minY,
          maxY: maxY,

          minX: 0,
          maxX: maxX,

          gridData: FlGridData(
            show: true,
            drawHorizontalLine: true,
            drawVerticalLine: false,
            horizontalInterval: interval,
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: themeExt.textSecondaryColor.withOpacity(0.2),
                strokeWidth: 1,
              );
            },
          ),

          titlesData: FlTitlesData(
            show: true,

            // Y Ось (слева)
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 50,
                interval: interval,
                getTitlesWidget: (value, _) {
                  return Text(
                    value.toInt().toString(),
                    style: TextStyle(
                      color: themeExt.textSecondaryColor,
                      fontSize: 10,
                    ),
                  );
                },
              ),
            ),

            // X Ось (снизу)
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 50, // каждые 50 точек подпись
                reservedSize: 24,
                getTitlesWidget: (value, _) {
                  return Text(
                    value.toInt().toString(),
                    style: TextStyle(color: themeExt.textSecondaryColor),
                  );
                },
              ),
            ),

            // Остальные отключаем
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),

          lineBarsData: [
            LineChartBarData(
              spots: [
                for (int i = 0; i < values.length; i++)
                  FlSpot(i.toDouble(), values[i])
              ],
              isCurved: false,
              color: themeExt.primaryColor,
              barWidth: 2,
              dotData: const FlDotData(show: false),
            ),
          ],

          borderData: FlBorderData(
            show: true,
            border: Border.all(
              color: themeExt.textSecondaryColor.withOpacity(0.2),
              width: 1,
            ),
          ),
        ),
      ),
    );
  }
}
