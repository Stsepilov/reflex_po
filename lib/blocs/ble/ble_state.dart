import 'package:equatable/equatable.dart';

import '../../models/reference_segment.dart';

enum BleConnectionStatus {
  disconnected,
  scanning,
  connecting,
  connected,
}

class BleState extends Equatable {
  final BleConnectionStatus status;
  final List<double> values; // Angle values
  final List<double> emgValues; // EMG values
  final bool isRecordingReference;
  final List<ReferenceSegment> referenceSegments;
  final bool isComparing;
  final double currentReferenceAngle;
  final int elapsedTimeMs;
  final double angleDifference;

  const BleState({
    required this.status,
    required this.values,
    required this.emgValues,
    required this.referenceSegments,
    this.isRecordingReference = false,
    this.isComparing = false,
    this.currentReferenceAngle = 0.0,
    this.elapsedTimeMs = 0,
    this.angleDifference = 0.0,
  });

  factory BleState.initial() => const BleState(
        status: BleConnectionStatus.disconnected,
        values: [],
        emgValues: [],
        isRecordingReference: false,
        referenceSegments: [],
        isComparing: false,
        currentReferenceAngle: 0.0,
        elapsedTimeMs: 0,
        angleDifference: 0.0,
      );

  BleState copyWith({
    BleConnectionStatus? status,
    List<double>? values,
    List<double>? emgValues,
    bool? isRecordingReference,
    List<ReferenceSegment>? referenceSegments,
    bool? isComparing,
    double? currentReferenceAngle,
    int? elapsedTimeMs,
    double? angleDifference,
  }) {
    return BleState(
      status: status ?? this.status,
      values: values ?? this.values,
      emgValues: emgValues ?? this.emgValues,
      isRecordingReference: isRecordingReference ?? this.isRecordingReference,
      referenceSegments: referenceSegments ?? this.referenceSegments,
      isComparing: isComparing ?? this.isComparing,
      currentReferenceAngle:
          currentReferenceAngle ?? this.currentReferenceAngle,
      elapsedTimeMs: elapsedTimeMs ?? this.elapsedTimeMs,
      angleDifference: angleDifference ?? this.angleDifference,
    );
  }

  @override
  List<Object?> get props => [
        status,
        values,
        emgValues,
        isRecordingReference,
        referenceSegments,
        isComparing,
        currentReferenceAngle,
        elapsedTimeMs,
        angleDifference,
      ];
}
