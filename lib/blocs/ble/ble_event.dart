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

  BleNewDataReceived({
    required this.angleValues,
    required this.emgValues,
  });

  @override
  List<Object?> get props => [angleValues, emgValues];
}

class BleStartReferenceRecording extends BleEvent {}

class BleStopReferenceRecording extends BleEvent {}

class BleStartComparison extends BleEvent {}

class BlePauseComparison extends BleEvent {}

class BleResetComparison extends BleEvent {}
