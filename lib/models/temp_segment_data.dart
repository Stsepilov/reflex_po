/// Temporary table for collecting data within a 5-degree shift
class TempSegmentData {
  final int index;
  final double avgAngle;
  final double avgEmg;
  final int timeMs;

  TempSegmentData({
    required this.index,
    required this.avgAngle,
    required this.avgEmg,
    required this.timeMs,
  });

  Map<String, dynamic> toJson() => {
        'index': index,
        'avgAngle': avgAngle,
        'avgEmg': avgEmg,
        'timeMs': timeMs,
      };

  factory TempSegmentData.fromJson(Map<String, dynamic> json) =>
      TempSegmentData(
        index: json['index'] as int,
        avgAngle: (json['avgAngle'] as num).toDouble(),
        avgEmg: (json['avgEmg'] as num).toDouble(),
        timeMs: json['timeMs'] as int,
      );
}
