import 'dart:async';
import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'ble_event.dart';
import 'ble_state.dart';
import '../../services/ble_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/reference_segment.dart';

class BleBloc extends Bloc<BleEvent, BleState> {
  late BleService _bleService;

  bool _isRecordingReference = false;
  int _currentSegment = 0; // 0..36 для 0–180°
  DateTime? _segmentStartTime;
  final List<double> _angleBuffer = [];
  List<ReferenceSegment> _referenceSegments = [];

  BleBloc() : super(BleState.initial()) {
    _bleService = BleService(
      targetDeviceName: "MyESP32",
      onNewData: (values) {
        add(BleNewDataReceived(values));
      },
      onConnected: () => add(BleConnected()),
    );

    on<BleLoadReference>(_onLoadReference);
    add(BleLoadReference());
    on<BleStartScan>(_onStartScan);
    on<BleRestartScan>(_onRestartScan);
    on<BleNewDataReceived>(_onNewData);
    on<BleConnected>((event, emit) {
      emit(state.copyWith(status: BleConnectionStatus.connected));
      _bleService.stopScan();
    });
    on<BleStopScan>((event, emit) {
      emit(state.copyWith(status: BleConnectionStatus.disconnected));
      _bleService.stopScan();
    });
    on<BleStartReferenceRecording>(_onStartReference);
    on<BleStopReferenceRecording>(_onStopReference);
  }

  Future<void> _onStartScan(BleStartScan event, Emitter<BleState> emit) async {
    emit(state.copyWith(status: BleConnectionStatus.scanning));
    _bleService.startScan();
  }

  Future<void> _onRestartScan(BleRestartScan event, Emitter<BleState> emit) async {
    _bleService.stopScan();

    emit(
      state.copyWith(
        values: [],
        status: BleConnectionStatus.scanning,
      ),
    );

    _bleService.startScan();
  }


  Future<void> _onNewData(BleNewDataReceived event, Emitter<BleState> emit) async {
    final updated = List<double>.from(state.values)..addAll(event.values);

    if (updated.length > 500) {
      updated.removeRange(0, updated.length - 500);
    }

    emit(state.copyWith(values: updated));

    if (_isRecordingReference) {
      _processReferenceAngles(event.values);
    }
  }

  Future<void> _onStartReference(
      BleStartReferenceRecording event, Emitter<BleState> emit) async {
    _isRecordingReference = true;
    _currentSegment = 0;
    _segmentStartTime = DateTime.now();
    _angleBuffer.clear();
    _referenceSegments.clear();

    emit(state.copyWith(isRecordingReference: true));
  }

  Future<void> _onStopReference(
      BleStopReferenceRecording event,
      Emitter<BleState> emit,
      ) async {
    _isRecordingReference = false;

    // сохранить в SharedPreferences
    await _saveReferenceToStorage();

    // обновить состояние состояния Bloc
    emit(
      state.copyWith(
        isRecordingReference: false,
        referenceSegments: List.from(_referenceSegments), // вот ЭТО важно
      ),
    );
  }


  void _processReferenceAngles(List<double> newAngles) {
    if (!_isRecordingReference || _segmentStartTime == null) return;

    for (final angle in newAngles) {
      _angleBuffer.add(angle);

      final expectedAngle = (_currentSegment + 1) * 5; // следующий шаг в 5°

      if (angle >= expectedAngle) {
        final now = DateTime.now();
        final durationMs =
            now.difference(_segmentStartTime!).inMilliseconds;

        final avgAngle =
            _angleBuffer.reduce((a, b) => a + b) / _angleBuffer.length;

        _referenceSegments.add(
          ReferenceSegment(
            segment: _currentSegment,
            avgAngle: avgAngle,
            timeMs: durationMs,
          ),
        );

        _currentSegment++;
        _segmentStartTime = now;
        _angleBuffer.clear();

        // дошли до 180° (36 * 5 = 180)
        if (_currentSegment > 36) {
          // автоматом завершаем запись
          _isRecordingReference = false;
          add(BleStopReferenceRecording());
          break;
        }
      }
    }
  }

  Future<void> _saveReferenceToStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = _referenceSegments.map((e) => e.toJson()).toList();
    final encoded = jsonEncode(jsonList);
    await prefs.setString("reference_table", encoded);
    print("Эталонная таблица углов сохранена: $encoded");
  }

  Future<void> printReference() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString("reference_table");
    print("REFERENCE DATA: $data");
  }

  Future<void> _onLoadReference(
      BleLoadReference event,
      Emitter<BleState> emit,
      ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString("reference_table");

    if (raw == null) {
      print("Reference table not found — running with empty.");
      return;
    }

    try {
      final decoded = jsonDecode(raw) as List;
      _referenceSegments = decoded
          .map((e) => ReferenceSegment.fromJson(e))
          .toList();

      print("Loaded reference segments: ${_referenceSegments.length}");

      // ОБНОВЛЯЕМ STATE
      emit(
        state.copyWith(
          referenceSegments: List.from(_referenceSegments),
        ),
      );
    } catch (e) {
      print("Error loading reference table: $e");
    }
  }


  @override
  Future<void> close() async {
    _bleService.dispose();
    return super.close();
  }
}
