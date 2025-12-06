import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class PulseChart extends StatelessWidget {
  final List<double> values;

  const PulseChart({super.key, required this.values});

  @override
  Widget build(BuildContext context) {
    final maxX = values.isEmpty ? 1.0 : values.length.toDouble();

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.5, // 👈 половина экрана сверху
      child: LineChart(
        LineChartData(
          backgroundColor: Colors.transparent,

          // 👇 Ограничение графика по Y
          minY: 0,
          maxY: 360,

          minX: 0,
          maxX: maxX,

          gridData: FlGridData(
            show: true,
            drawHorizontalLine: true,
            drawVerticalLine: false,
            horizontalInterval: 60, // линии на 0, 60, 120, 180, 240, 300, 360
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: Colors.white24,
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
                reservedSize: 40,
                interval: 60,
                getTitlesWidget: (value, _) {
                  return Text(
                    value.toInt().toString(),
                    style: const TextStyle(color: Colors.white),
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
                    style: const TextStyle(color: Colors.white70),
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
                  FlSpot(i.toDouble(), values[i].clamp(0, 360).toDouble())
              ],
              isCurved: false,
              color: Colors.white,
              barWidth: 2,
              dotData: FlDotData(show: false),
            ),
          ],

          borderData: FlBorderData(
            show: true,
            border: Border.all(color: Colors.white24, width: 1),
          ),
        ),
      ),
    );
  }
}
