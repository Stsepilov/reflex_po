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
  final int emgStartX; // X-offset for sliding EMG window
  final bool isRecordingReference;
  final List<ReferenceSegment> referenceSegments;
  final bool isComparing;
  final double currentReferenceAngle;
  final int elapsedTimeMs;
  final double angleDifference;
  final int minAngleBorder; // Minimum angle border (e.g., 0°)
  final int maxAngleBorder; // Maximum angle border (e.g., 180°)
  final List<int> referenceMuscleStatus; // 0=inactive, 1=active
  final List<int> currentRepMuscleStatus; // -1=unknown, 0=inactive, 1=active
  final List<int> previousRepMuscleStatus; // -1=unknown, 0=inactive, 1=active
  final double currentRepEffortPercent; // current EMG / max reference EMG * 100
  final double emgNoise;

  const BleState({
    required this.status,
    required this.values,
    required this.emgValues,
    required this.emgStartX,
    required this.referenceSegments,
    this.isRecordingReference = false,
    this.isComparing = false,
    this.currentReferenceAngle = 0.0,
    this.elapsedTimeMs = 0,
    this.angleDifference = 0.0,
    this.minAngleBorder = 0,
    this.maxAngleBorder = 180,
    this.referenceMuscleStatus = const [],
    this.currentRepMuscleStatus = const [],
    this.previousRepMuscleStatus = const [],
    this.currentRepEffortPercent = 0.0,
    this.emgNoise = 0.0,
  });

  factory BleState.initial() => const BleState(
        status: BleConnectionStatus.disconnected,
        values: [],
        emgValues: [],
        emgStartX: 0,
        isRecordingReference: false,
        referenceSegments: [],
        isComparing: false,
        currentReferenceAngle: 0.0,
        elapsedTimeMs: 0,
        angleDifference: 0.0,
        minAngleBorder: 0,
        maxAngleBorder: 180,
        referenceMuscleStatus: [],
        currentRepMuscleStatus: [],
        previousRepMuscleStatus: [],
        currentRepEffortPercent: 0.0,
        emgNoise: 0.0,
      );

  BleState copyWith({
    BleConnectionStatus? status,
    List<double>? values,
    List<double>? emgValues,
    int? emgStartX,
    bool? isRecordingReference,
    List<ReferenceSegment>? referenceSegments,
    bool? isComparing,
    double? currentReferenceAngle,
    int? elapsedTimeMs,
    double? angleDifference,
    int? minAngleBorder,
    int? maxAngleBorder,
    List<int>? referenceMuscleStatus,
    List<int>? currentRepMuscleStatus,
    List<int>? previousRepMuscleStatus,
    double? currentRepEffortPercent,
    double? emgNoise,
  }) {
    return BleState(
      status: status ?? this.status,
      values: values ?? this.values,
      emgValues: emgValues ?? this.emgValues,
      emgStartX: emgStartX ?? this.emgStartX,
      isRecordingReference: isRecordingReference ?? this.isRecordingReference,
      referenceSegments: referenceSegments ?? this.referenceSegments,
      isComparing: isComparing ?? this.isComparing,
      currentReferenceAngle:
          currentReferenceAngle ?? this.currentReferenceAngle,
      elapsedTimeMs: elapsedTimeMs ?? this.elapsedTimeMs,
      angleDifference: angleDifference ?? this.angleDifference,
      minAngleBorder: minAngleBorder ?? this.minAngleBorder,
      maxAngleBorder: maxAngleBorder ?? this.maxAngleBorder,
      referenceMuscleStatus: referenceMuscleStatus ?? this.referenceMuscleStatus,
      currentRepMuscleStatus:
          currentRepMuscleStatus ?? this.currentRepMuscleStatus,
      previousRepMuscleStatus:
          previousRepMuscleStatus ?? this.previousRepMuscleStatus,
      currentRepEffortPercent:
          currentRepEffortPercent ?? this.currentRepEffortPercent,
      emgNoise: emgNoise ?? this.emgNoise,
    );
  }

  @override
  List<Object?> get props => [
        status,
        values,
        emgValues,
        emgStartX,
        isRecordingReference,
        referenceSegments,
        isComparing,
        currentReferenceAngle,
        elapsedTimeMs,
        angleDifference,
        minAngleBorder,
        maxAngleBorder,
        referenceMuscleStatus,
        currentRepMuscleStatus,
        previousRepMuscleStatus,
        currentRepEffortPercent,
        emgNoise,
      ];
}
