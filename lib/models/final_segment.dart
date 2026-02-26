// Import for TempSegmentData
import 'temp_segment_data.dart';

/// Final segment table row after each completed 5-degree shift
class FinalSegment {
  final int index; // Shift number (0, 1, 2, ...)
  final double firstAvgAngle; // First avg angle from temp table
  final double absoluteAngle; // Absolute difference between last and first angle
  final double avgEmg; // Average EMG across the whole temp table
  final double absoluteEmg; // Difference between last and first EMG
  final double deltaAngle; // (max - min) / 2 for angle
  final double deltaEmg; // (max - min) / 2 for EMG
  final int timeMs; // Time from last row - first row

  FinalSegment({
    required this.index,
    required this.firstAvgAngle,
    required this.absoluteAngle,
    required this.avgEmg,
    required this.absoluteEmg,
    required this.deltaAngle,
    required this.deltaEmg,
    required this.timeMs,
  });

  Map<String, dynamic> toJson() => {
        'index': index,
        'firstAvgAngle': firstAvgAngle,
        'absoluteAngle': absoluteAngle,
        'avgEmg': avgEmg,
        'absoluteEmg': absoluteEmg,
        'deltaAngle': deltaAngle,
        'deltaEmg': deltaEmg,
        'timeMs': timeMs,
      };

  factory FinalSegment.fromJson(Map<String, dynamic> json) => FinalSegment(
        index: json['index'] as int,
        firstAvgAngle: (json['firstAvgAngle'] as num).toDouble(),
        absoluteAngle: (json['absoluteAngle'] as num).toDouble(),
        avgEmg: (json['avgEmg'] as num).toDouble(),
        absoluteEmg: (json['absoluteEmg'] as num).toDouble(),
        deltaAngle: (json['deltaAngle'] as num).toDouble(),
        deltaEmg: (json['deltaEmg'] as num).toDouble(),
        timeMs: json['timeMs'] as int,
      );

  /// Calculate shift-row values from temporary packet table
  static FinalSegment fromTempData(
    int shiftIndex,
    List<TempSegmentData> tempData,
  ) {
    if (tempData.isEmpty) {
      throw ArgumentError('Temp data cannot be empty');
    }

    final firstRow = tempData.first;
    final lastRow = tempData.last;

    // Calculate absolute values (difference between last and first)
    final absoluteAngle = (lastRow.avgAngle - firstRow.avgAngle).abs();
    final absoluteEmg = lastRow.avgEmg - firstRow.avgEmg;

    // Calculate delta values (max - min) / 2
    final angles = tempData.map((e) => e.avgAngle).toList();
    final emgs = tempData.map((e) => e.avgEmg).toList();

    final maxAngle = angles.reduce((a, b) => a > b ? a : b);
    final minAngle = angles.reduce((a, b) => a < b ? a : b);
    final deltaAngle = (maxAngle - minAngle) / 2;

    final maxEmg = emgs.reduce((a, b) => a > b ? a : b);
    final minEmg = emgs.reduce((a, b) => a < b ? a : b);
    final deltaEmg = (maxEmg - minEmg) / 2;

    // Average EMG for the whole shift
    final avgEmg = emgs.reduce((a, b) => a + b) / emgs.length;

    // Calculate time: last - first
    final timeMs = lastRow.timeMs - firstRow.timeMs;

    return FinalSegment(
      index: shiftIndex,
      firstAvgAngle: firstRow.avgAngle,
      absoluteAngle: absoluteAngle,
      avgEmg: avgEmg,
      absoluteEmg: absoluteEmg,
      deltaAngle: deltaAngle,
      deltaEmg: deltaEmg,
      timeMs: timeMs,
    );
  }
}
