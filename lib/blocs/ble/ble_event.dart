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
  final List<double> values;

  BleNewDataReceived(this.values);

  @override
  List<Object?> get props => [values];
}

class BleStartReferenceRecording extends BleEvent {}
class BleStopReferenceRecording extends BleEvent {}