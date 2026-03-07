import 'package:equatable/equatable.dart';

abstract class BleEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class BleStartScan extends BleEvent {}

class BleStopScan extends BleEvent {}

class BleRestartScan extends BleEvent {}

class BleConnected extends BleEvent {}

class BleDisconnected extends BleEvent {}

class BleLoadReference extends BleEvent {}

class BleNewDataReceived extends BleEvent {
  final List<double> angleValues;
  final List<double> emgValues;
  final List<double> timeValues;

  BleNewDataReceived({
    required this.angleValues,
    required this.emgValues,
    required this.timeValues,
  });

  @override
  List<Object?> get props => [angleValues, emgValues, timeValues];
}

class BleStartReferenceRecording extends BleEvent {
  final int minAngle;
  final int maxAngle;

  BleStartReferenceRecording({
    required this.minAngle,
    required this.maxAngle,
  });

  @override
  List<Object?> get props => [minAngle, maxAngle];
}

class BleStopReferenceRecording extends BleEvent {}

class BleStartComparison extends BleEvent {}

class BlePauseComparison extends BleEvent {}

class BleResetComparison extends BleEvent {}

class BleStartDataStream extends BleEvent {}

class BleStopDataStream extends BleEvent {}

class BleUpdateAngleBorders extends BleEvent {
  final int minAngle;
  final int maxAngle;

  BleUpdateAngleBorders({
    required this.minAngle,
    required this.maxAngle,
  });

  @override
  List<Object?> get props => [minAngle, maxAngle];
}

class BleStartBaselineCalibration extends BleEvent {}

class BleFinishBaselineCalibration extends BleEvent {}

class BleUiTick extends BleEvent {}
