class ReferenceSegment {
  final int segment;      // номер сегмента (0..36)
  final double avgAngle;  // средний угол в сегменте
  final int timeMs;       // время на сегмент в миллисекундах

  ReferenceSegment({
    required this.segment,
    required this.avgAngle,
    required this.timeMs,
  });

  Map<String, dynamic> toJson() => {
    "segment": segment,
    "avgAngle": avgAngle,
    "timeMs": timeMs,
  };

  factory ReferenceSegment.fromJson(Map<String, dynamic> json) {
    return ReferenceSegment(
      segment: json["segment"],
      avgAngle: (json["avgAngle"] as num).toDouble(),
      timeMs: json["timeMs"] as int,
    );
  }
}
