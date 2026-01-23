import 'dart:async';
import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'ble_event.dart';
import 'ble_state.dart';
import '../../services/ble_service.dart';
// import '../../services/test_data_generator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/reference_segment.dart';

class BleBloc extends Bloc<BleEvent, BleState> {
  late BleService _bleService;
  //late TestDataGenerator _testDataGenerator;

  bool _isRecordingReference = false;
  int _currentSegment = 0; // 0..36 для 0–180°
  DateTime? _segmentStartTime;
  final List<double> _angleBuffer = [];
  List<ReferenceSegment> _referenceSegments = [];

  // Comparison mode
  bool _isComparing = false;
  DateTime? _comparisonStartTime;
  Timer? _comparisonTimer;

  BleBloc() : super(BleState.initial()) {
    _bleService = BleService(
      targetDeviceName: "MyESP32",
      onNewData: ({required angleValues, required emgValues}) {
        add(BleNewDataReceived(
          angleValues: angleValues,
          emgValues: emgValues,
        ));
      },
      onConnected: () => add(BleConnected()),
    );

    // _testDataGenerator = TestDataGenerator(
    //   onNewData: ({required angleValues, required emgValues}) {
    //     add(BleNewDataReceived(
    //       angleValues: angleValues,
    //       emgValues: emgValues,
    //     ));
    //   },
    // );

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
      //_testDataGenerator.stop();
    });
    on<BleStartReferenceRecording>(_onStartReference);
    on<BleStopReferenceRecording>(_onStopReference);
    on<BleStartComparison>(_onStartComparison);
    on<BlePauseComparison>(_onPauseComparison);
    on<BleResetComparison>(_onResetComparison);
  }

  Future<void> _onStartScan(BleStartScan event, Emitter<BleState> emit) async {
    emit(state.copyWith(status: BleConnectionStatus.scanning));
    _bleService.startScan();

    // await Future.delayed(const Duration(seconds: 1));
    // add(BleConnected());
    // _testDataGenerator.start();
  }

  Future<void> _onRestartScan(
      BleRestartScan event, Emitter<BleState> emit) async {
    _bleService.stopScan();
    //_testDataGenerator.stop();

    emit(
      state.copyWith(
        values: [],
        emgValues: [],
        status: BleConnectionStatus.scanning,
      ),
    );

    _bleService.startScan();

    // await Future.delayed(const Duration(seconds: 1));
    // add(BleConnected());
    // _testDataGenerator.start();
  }

  Future<void> _onNewData(
      BleNewDataReceived event, Emitter<BleState> emit) async {
    // Update angle values
    final updatedAngles = List<double>.from(state.values)
      ..addAll(event.angleValues);
    if (updatedAngles.length > 500) {
      updatedAngles.removeRange(0, updatedAngles.length - 500);
    }

    // Calculate average EMG from the package and add it to the list
    final updatedEmg = List<double>.from(state.emgValues);
    if (event.emgValues.isNotEmpty) {
      final avgEmg =
          event.emgValues.reduce((a, b) => a + b) / event.emgValues.length;
      updatedEmg.add(avgEmg);

      if (updatedEmg.length > 500) {
        updatedEmg.removeRange(0, updatedEmg.length - 500);
      }
    }

    emit(state.copyWith(
      values: updatedAngles,
      emgValues: updatedEmg,
    ));

    if (_isRecordingReference) {
      _processReferenceAngles(event.angleValues);
    }

    if (_isComparing) {
      _updateComparison(emit);
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
        final durationMs = now.difference(_segmentStartTime!).inMilliseconds;

        // Защита от пустого буфера
        if (_angleBuffer.isEmpty) continue;

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

        // дошли до 180° (36 сегментов: 0-35, каждый по 5°)
        if (_currentSegment >= 36) {
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
      _referenceSegments =
          decoded.map((e) => ReferenceSegment.fromJson(e)).toList();

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

  // ==================== COMPARISON MODE ====================

  Future<void> _onStartComparison(
    BleStartComparison event,
    Emitter<BleState> emit,
  ) async {
    if (_referenceSegments.isEmpty) {
      print("Cannot start comparison: no reference data");
      return;
    }

    _isComparing = true;
    _comparisonStartTime = DateTime.now();

    // Запускаем таймер для обновления времени
    _comparisonTimer?.cancel();
    _comparisonTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (_isComparing && _comparisonStartTime != null) {
        add(BleResetComparison()); // Используем для обновления времени
      }
    });

    emit(state.copyWith(
      isComparing: true,
      elapsedTimeMs: 0,
      currentReferenceAngle: 0.0,
      angleDifference: 0.0,
    ));
  }

  Future<void> _onPauseComparison(
    BlePauseComparison event,
    Emitter<BleState> emit,
  ) async {
    _isComparing = false;
    _comparisonTimer?.cancel();

    emit(state.copyWith(isComparing: false));
  }

  Future<void> _onResetComparison(
    BleResetComparison event,
    Emitter<BleState> emit,
  ) async {
    if (!_isComparing) {
      // Полный сброс
      _comparisonStartTime = null;
      _comparisonTimer?.cancel();

      emit(state.copyWith(
        isComparing: false,
        elapsedTimeMs: 0,
        currentReferenceAngle: 0.0,
        angleDifference: 0.0,
      ));
    } else {
      // Обновление времени во время сравнения
      if (_comparisonStartTime != null) {
        final elapsed =
            DateTime.now().difference(_comparisonStartTime!).inMilliseconds;
        final referenceAngle = _getReferenceAngleAtTime(elapsed);
        final currentAngle = state.values.isNotEmpty ? state.values.last : 0.0;
        final difference = (currentAngle - referenceAngle).abs();

        emit(state.copyWith(
          elapsedTimeMs: elapsed,
          currentReferenceAngle: referenceAngle,
          angleDifference: difference,
        ));
      }
    }
  }

  // Получить эталонный угол для заданного времени
  double _getReferenceAngleAtTime(int elapsedMs) {
    if (_referenceSegments.isEmpty) return 0.0;

    int cumulativeTime = 0;

    for (int i = 0; i < _referenceSegments.length; i++) {
      final segment = _referenceSegments[i];
      cumulativeTime += segment.timeMs;

      if (elapsedMs <= cumulativeTime) {
        // Находимся в этом сегменте
        return segment.avgAngle;
      }
    }

    // Если время превысило все сегменты, возвращаем последний угол
    return _referenceSegments.last.avgAngle;
  }

  // Обновление сравнения при получении новых данных
  void _updateComparison(Emitter<BleState> emit) {
    if (!_isComparing || _comparisonStartTime == null) return;

    final elapsed =
        DateTime.now().difference(_comparisonStartTime!).inMilliseconds;
    final referenceAngle = _getReferenceAngleAtTime(elapsed);
    final currentAngle = state.values.isNotEmpty ? state.values.last : 0.0;
    final difference = (currentAngle - referenceAngle).abs();

    emit(state.copyWith(
      elapsedTimeMs: elapsed,
      currentReferenceAngle: referenceAngle,
      angleDifference: difference,
    ));
  }

  @override
  Future<void> close() async {
    _comparisonTimer?.cancel();
    _bleService.dispose();
    //_testDataGenerator.dispose();
    return super.close();
  }
}
