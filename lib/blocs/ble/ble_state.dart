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
  final List<double> values;
  final bool isRecordingReference;
  final List<ReferenceSegment> referenceSegments;

  const BleState({
    required this.status,
    required this.values,
    required this.referenceSegments,
    this.isRecordingReference = false,
  });

  factory BleState.initial() => BleState(
    status: BleConnectionStatus.disconnected,
    values: [],
    isRecordingReference: false,
    referenceSegments: [],
  );

  BleState copyWith({
    BleConnectionStatus? status,
    List<double>? values,
    bool? isRecordingReference,
    List<ReferenceSegment>? referenceSegments,
  }) {
    return BleState(
      status: status ?? this.status,
      values: values ?? this.values,
      isRecordingReference: isRecordingReference ?? this.isRecordingReference,
      referenceSegments: referenceSegments ?? this.referenceSegments,
    );
  }

  @override
  List<Object?> get props => [status, values, isRecordingReference, referenceSegments];
}
