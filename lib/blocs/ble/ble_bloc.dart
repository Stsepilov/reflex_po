import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'ble_event.dart';
import 'ble_state.dart';
import '../../services/ble_service.dart';
import '../../services/pchip.dart';
// import '../../services/test_data_generator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/reference_segment.dart';
import '../../models/temp_segment_data.dart';
import '../../models/final_segment.dart';

enum _MovementDirection { unknown, up, down }

class BleBloc extends Bloc<BleEvent, BleState> {
  static const String _referenceTableKey = "reference_table";
  static const String _repetitionTablesKey = "reference_repetition_tables";
  static const String _phaseProfileKey = "reference_phase_profile";
  static const int _phaseGridPoints = 101;

  late BleService _bleService;
  // late TestDataGenerator _testDataGenerator;

  bool _isRecordingReference = false;
  int _minAngle = 0; // Minimum angle for recording
  int _maxAngle = 180; // Maximum angle for recording
  DateTime? _recordingStartTime;
  int _tempDataIndex = 0; // Index for temp table rows (packet table)
  int _shiftDataIndex = 0; // Index for shift table rows

  // Buffers for averaging
  final List<double> _angleBuffer = [];
  final List<double> _emgBuffer = [];
  // UI/state buffers to avoid data loss between throttled emits
  final List<double> _anglesForUi = [];
  final List<double> _emgForUi = [];
  int _emgSampleCount = 0;
  double _latestAngle = 0.0;

  // Repetition tracking (max -> min -> max)
  int _completedReps = 0;
  final int _targetReps = 10;
  bool _sawLocalMinInCurrentRep = false;
  double? _previousAvgAngle;
  _MovementDirection _lastDirection = _MovementDirection.unknown;

  // Thresholds used by the new algorithm
  static const double _shiftAngleThreshold = 5.0;
  static const double _directionEpsilon = 0.5;
  static const double _turnConfirmationDelta = 2.0;
  static const double _extremaTolerance = 5.0;
  double? _pendingPivotAngle;
  _MovementDirection _pendingDirection = _MovementDirection.unknown;
  _MovementDirection _directionBeforePending = _MovementDirection.unknown;

  // Shift table for all data points (global second table)
  final List<FinalSegment> _finalSegments = [];
  // Temporary packet table (first table)
  final List<TempSegmentData> _currentTempTable = [];
  // Shift rows collected for current repetition
  final List<FinalSegment> _currentRepTable = [];
  // 10 final tables (one table per repetition)
  final List<List<FinalSegment>> _repetitionTables = [];

  // Old reference segments (for backward compatibility)
  List<ReferenceSegment> _referenceSegments = [];
  List<double> _phasePhi = [];
  List<double> _phaseTheta = [];
  List<double> _phaseEmg = [];
  List<double> _phaseTime = [];

  // Comparison mode
  bool _isComparing = false;
  DateTime? _comparisonStartTime;
  Timer? _comparisonTimer;

  // Performance monitoring
  int _dataProcessCounter = 0;
  int _droppedFrames = 0;
  DateTime _lastProcessTime = DateTime.now();

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
    //   onRawPacket: (packet) {
    //     print("TEST PACKET: $packet");
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
      // _testDataGenerator.stop();
    });
    on<BleStartReferenceRecording>(_onStartReference);
    on<BleStopReferenceRecording>(_onStopReference);
    on<BleStartComparison>(_onStartComparison);
    on<BlePauseComparison>(_onPauseComparison);
    on<BleResetComparison>(_onResetComparison);
    on<BleStartDataStream>(_onStartDataStream);
    on<BleStopDataStream>(_onStopDataStream);
    on<BleUpdateAngleBorders>(_onUpdateAngleBorders);
  }

  Future<void> _onStartScan(BleStartScan event, Emitter<BleState> emit) async {
    emit(state.copyWith(status: BleConnectionStatus.scanning));
    _bleService.startScan();

    // await Future.delayed(const Duration(milliseconds: 300));
    // add(BleConnected());
  }

  Future<void> _onRestartScan(
      BleRestartScan event, Emitter<BleState> emit) async {
    _bleService.stopScan();
    // _testDataGenerator.stop();
    _anglesForUi.clear();
    _emgForUi.clear();
    _emgSampleCount = 0;
    _latestAngle = 0.0;

    emit(
      state.copyWith(
        values: [],
        emgValues: [],
        emgStartX: 0,
        status: BleConnectionStatus.scanning,
      ),
    );

    _bleService.startScan();

    // await Future.delayed(const Duration(milliseconds: 300));
    // add(BleConnected());
  }

  Future<void> _onNewData(
      BleNewDataReceived event, Emitter<BleState> emit) async {
    // Performance monitoring
    final now = DateTime.now();
    final timeSinceLastProcess =
        now.difference(_lastProcessTime).inMilliseconds;

    if (timeSinceLastProcess > 100) {
      _droppedFrames++;
      if (_droppedFrames % 10 == 0) {
        print(
            "⚠️ Slow processing detected: ${timeSinceLastProcess}ms (dropped frames: $_droppedFrames)");
      }
    }
    _lastProcessTime = now;
    _dataProcessCounter++;

    // Keep accumulating in dedicated buffers even when we skip emit.
    _anglesForUi.addAll(event.angleValues);
    if (_anglesForUi.length > 500) {
      _anglesForUi.removeRange(0, _anglesForUi.length - 500);
    }
    if (event.angleValues.isNotEmpty) {
      _latestAngle = event.angleValues.last;
    }

    if (event.emgValues.isNotEmpty) {
      final avgEmg =
          event.emgValues.reduce((a, b) => a + b) / event.emgValues.length;
      _emgForUi.add(avgEmg);
      _emgSampleCount++;

      if (_emgForUi.length > 500) {
        _emgForUi.removeRange(0, _emgForUi.length - 500);
      }
    }

    // Throttle UI updates: only emit state every 2nd update (reduces from 20Hz to 10Hz)
    // This reduces UI rebuilds while keeping data processing at full speed
    final shouldEmit = _dataProcessCounter % 2 == 0;

    if (shouldEmit) {
      final emgStartX = _emgSampleCount - _emgForUi.length;
      emit(state.copyWith(
        values: List<double>.from(_anglesForUi),
        emgValues: List<double>.from(_emgForUi),
        emgStartX: emgStartX < 0 ? 0 : emgStartX,
      ));
    }

    // Process recording data (always process, regardless of UI throttling)
    if (_isRecordingReference) {
      _processReferenceData(event.angleValues, event.emgValues);
    }

    // Comparison updates (always process)
    if (_isComparing) {
      _updateComparison(emit);
    }
  }

  Future<void> _onStartReference(
      BleStartReferenceRecording event, Emitter<BleState> emit) async {
    _isRecordingReference = true;
    _minAngle = event.minAngle;
    _maxAngle = event.maxAngle;
    _recordingStartTime = DateTime.now();
    _tempDataIndex = 0;
    _shiftDataIndex = 0;
    _completedReps = 0;
    _sawLocalMinInCurrentRep = false;
    _previousAvgAngle = null;
    _lastDirection = _MovementDirection.unknown;
    _pendingPivotAngle = null;
    _pendingDirection = _MovementDirection.unknown;
    _directionBeforePending = _MovementDirection.unknown;

    _finalSegments.clear();
    _currentTempTable.clear();
    _currentRepTable.clear();
    _repetitionTables.clear();
    _angleBuffer.clear();
    _emgBuffer.clear();

    print(
        "Начало записи эталона: $_targetReps повторений ($_maxAngle° → $_minAngle° → $_maxAngle°)");
    emit(state.copyWith(isRecordingReference: true));
  }

  Future<void> _onStopReference(
    BleStopReferenceRecording event,
    Emitter<BleState> emit,
  ) async {
    _isRecordingReference = false;

    // Flush current temp table if it already reached threshold but was not
    // finalized yet due to manual stop timing.
    _tryFinalizeCurrentShift();

    print("========================================");
    print("НАЧАЛО ОБРАБОТКИ ЭТАЛОНА");
    print("Всего повторов: ${_repetitionTables.length}");
    print("Всего сдвигов: ${_finalSegments.length}");
    print("========================================");

    if (_repetitionTables.isEmpty) {
      print("Нет данных повторов для обработки");
      emit(state.copyWith(isRecordingReference: false));
      return;
    }

    final repTables = _repetitionTables.take(_targetReps).toList();

    // Build phase-normalized reference (phi/theta/emg/time) first.
    final phaseReady = _buildPhaseNormalizedReference(repTables);
    if (!phaseReady) {
      // Fallback to old averaging if there is not enough valid data.
      _averageRepetitionTablesIntoReference(repTables);
    }
    print("Усреднено в ${_referenceSegments.length} референсных сегментов");

    // Save to SharedPreferences
    await _saveRepetitionTablesToStorage();
    await _savePhaseProfileToStorage();
    await _saveReferenceToStorage();

    print("========================================");
    print("ЭТАЛОН УСПЕШНО СОЗДАН");
    print("========================================");

    // Update state
    emit(
      state.copyWith(
        isRecordingReference: false,
        referenceSegments: List.from(_referenceSegments),
      ),
    );
  }

  void _averageRepetitionTablesIntoReference(
      List<List<FinalSegment>> repTables) {
    _referenceSegments.clear();

    if (repTables.isEmpty) return;

    // Find the maximum repetition-table length
    final maxLength =
        repTables.map((c) => c.length).reduce((a, b) => a > b ? a : b);

    print(
        "Усреднение ${repTables.length} таблиц повторов, максимальная длина: $maxLength строк");

    // Average each row position across all repetition tables
    for (int segmentPos = 0; segmentPos < maxLength; segmentPos++) {
      double sumAngle = 0.0;
      int sumTime = 0;
      int count = 0;

      for (final repTable in repTables) {
        if (segmentPos < repTable.length) {
          sumAngle += repTable[segmentPos].firstAvgAngle;
          sumTime += repTable[segmentPos].timeMs;
          count++;
        }
      }

      if (count > 0) {
        final avgAngle = sumAngle / count;
        final avgTime = (sumTime / count).round();

        _referenceSegments.add(ReferenceSegment(
          segment: segmentPos,
          avgAngle: avgAngle,
          timeMs: avgTime,
        ));
      }
    }

    print("Создано ${_referenceSegments.length} усреднённых сегментов");
  }

  bool _buildPhaseNormalizedReference(List<List<FinalSegment>> repTables) {
    _referenceSegments.clear();
    _phasePhi = [];
    _phaseTheta = [];
    _phaseEmg = [];
    _phaseTime = [];

    if (repTables.isEmpty) return false;

    final phiGrid = List<double>.generate(_phaseGridPoints, (i) => i / 100.0);

    final List<List<double>> thetaTrials = [];
    final List<List<double>> emgTrials = [];
    final List<List<double>> timeTrials = [];

    for (final table in repTables) {
      final timeSeries = _buildTimePhaseSeries(table);
      final angleSeries = _buildAnglePhaseSeries(table);
      if (timeSeries == null || angleSeries == null) {
        continue;
      }

      try {
        final thetaPchip = Pchip(timeSeries['phi']!, timeSeries['theta']!);
        final emgPchip = Pchip(timeSeries['phi']!, timeSeries['emg']!);
        final timePchip = Pchip(angleSeries['phi']!, angleSeries['time']!);

        thetaTrials.add(thetaPchip.resample(phiGrid));
        emgTrials.add(emgPchip.resample(phiGrid));
        timeTrials.add(timePchip.resample(phiGrid));
      } catch (e) {
        print("Пропуск таблицы при фазовой интерполяции: $e");
      }
    }

    if (thetaTrials.isEmpty || emgTrials.isEmpty || timeTrials.isEmpty) {
      print("Недостаточно валидных таблиц для фазовой нормализации");
      return false;
    }

    final thetaMedian = _medianAcrossTrials(thetaTrials);
    final emgMedian = _medianAcrossTrials(emgTrials);
    final timeMedian = _medianAcrossTrials(timeTrials);

    // Phase->time profile must be strictly increasing (101 points).
    _enforceStrictlyIncreasing(timeMedian);

    final segmentDurations = _toSegmentDurations(timeMedian);
    for (int i = 0; i < thetaMedian.length; i++) {
      _referenceSegments.add(ReferenceSegment(
        segment: i,
        avgAngle: thetaMedian[i],
        timeMs: segmentDurations[i],
      ));
    }

    _phasePhi = phiGrid;
    _phaseTheta = thetaMedian;
    _phaseEmg = emgMedian;
    _phaseTime = timeMedian;

    print(
        "Фазовая нормализация готова: trials=${thetaTrials.length}, points=$_phaseGridPoints");
    _printFinalReferenceArrays(
      theta: _phaseTheta,
      emg: _phaseEmg,
      time: _phaseTime,
    );
    return true;
  }

  Map<String, List<double>>? _buildTimePhaseSeries(List<FinalSegment> table) {
    if (table.isEmpty) return null;

    final theta = <double>[];
    final emg = <double>[];
    final cumulativeTime = <double>[];

    double runningTime = 0.0;
    for (final row in table) {
      final dt = max(0, row.timeMs);
      runningTime += dt;
      theta.add(row.firstAvgAngle);
      emg.add(row.avgEmg);
      cumulativeTime.add(runningTime);
    }

    final totalTime = runningTime;
    if (totalTime <= 0) return null;

    final phi = cumulativeTime.map((t) => t / totalTime).toList();
    final strictTheta = _ensureStrictlyIncreasing(phi, theta);
    final strictEmg = _ensureStrictlyIncreasing(phi, emg);
    if (strictTheta == null || strictEmg == null) return null;

    return {
      'phi': strictTheta['x']!,
      'theta': strictTheta['y']!,
      'emg': strictEmg['y']!,
    };
  }

  Map<String, List<double>>? _buildAnglePhaseSeries(List<FinalSegment> table) {
    if (table.isEmpty) return null;

    final cumulativeAngle = <double>[];
    final cumulativeTime = <double>[];
    double runningAngle = 0.0;
    double runningTime = 0.0;

    for (final row in table) {
      final dTheta = row.absoluteAngle.abs();
      final dt = max(0, row.timeMs);
      runningAngle += dTheta;
      runningTime += dt;
      cumulativeAngle.add(runningAngle);
      cumulativeTime.add(runningTime);
    }

    if (runningAngle <= 0) return null;
    final phi = cumulativeAngle.map((a) => a / runningAngle).toList();
    final strict = _ensureStrictlyIncreasing(phi, cumulativeTime);
    if (strict == null) return null;
    return {
      'phi': strict['x']!,
      'time': strict['y']!,
    };
  }

  Map<String, List<double>>? _ensureStrictlyIncreasing(
      List<double> x, List<double> y) {
    if (x.length != y.length || x.isEmpty) return null;

    const eps = 1e-9;
    final sx = <double>[];
    final sy = <double>[];

    for (int i = 0; i < x.length; i++) {
      final xi = x[i].clamp(0.0, 1.0).toDouble();
      final yi = y[i];

      if (sx.isEmpty) {
        sx.add(xi);
        sy.add(yi);
        continue;
      }

      if (xi <= sx.last + eps) {
        sy[sy.length - 1] = yi;
      } else {
        sx.add(xi);
        sy.add(yi);
      }
    }

    if (sx.length < 2) return null;
    return {'x': sx, 'y': sy};
  }

  List<double> _medianAcrossTrials(List<List<double>> data) {
    if (data.isEmpty) {
      throw ArgumentError('Нет данных');
    }

    final points = data[0].length;
    for (final arr in data) {
      if (arr.length != points) {
        throw ArgumentError('Все массивы должны быть одинаковой длины');
      }
    }

    final result = List<double>.filled(points, 0.0);
    for (int j = 0; j < points; j++) {
      final column = <double>[];
      for (int i = 0; i < data.length; i++) {
        column.add(data[i][j]);
      }
      result[j] = _median(column);
    }
    return result;
  }

  double _median(List<double> values) {
    if (values.isEmpty) return 0.0;
    final sorted = List<double>.from(values)..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid];
    return (sorted[mid - 1] + sorted[mid]) / 2.0;
  }

  List<int> _toSegmentDurations(List<double> cumulativeTime) {
    if (cumulativeTime.isEmpty) return [];

    final result = List<int>.filled(cumulativeTime.length, 1);
    var prev = 0.0;
    for (int i = 0; i < cumulativeTime.length; i++) {
      final dt = (cumulativeTime[i] - prev).round();
      result[i] = dt <= 0 ? 1 : dt;
      prev = cumulativeTime[i];
    }
    return result;
  }

  void _enforceStrictlyIncreasing(List<double> values) {
    if (values.isEmpty) return;
    // Keep original scale, only fix non-increasing plateaus after median.
    const minStep = 1e-6;
    for (int i = 1; i < values.length; i++) {
      if (values[i] <= values[i - 1]) {
        values[i] = values[i - 1] + minStep;
      }
    }
  }

  void _processReferenceData(
      List<double> newAngles, List<double> newEmgValues) {
    if (!_isRecordingReference || _recordingStartTime == null) return;

    // Add new data to buffers
    _angleBuffer.addAll(newAngles);
    _emgBuffer.addAll(newEmgValues);

    // Calculate averages
    if (_angleBuffer.isEmpty || _emgBuffer.isEmpty) return;

    final avgAngle = _angleBuffer.reduce((a, b) => a + b) / _angleBuffer.length;
    final avgEmg = _emgBuffer.reduce((a, b) => a + b) / _emgBuffer.length;
    final currentTime =
        DateTime.now().difference(_recordingStartTime!).inMilliseconds;

    // Add packet row to temporary table (table #1)
    _currentTempTable.add(TempSegmentData(
      index: _tempDataIndex++,
      avgAngle: avgAngle,
      avgEmg: avgEmg,
      timeMs: currentTime,
    ));

    // Clear buffers for next iteration
    _angleBuffer.clear();
    _emgBuffer.clear();

    _tryFinalizeCurrentShift();
    _detectExtremaAndCountRepetitions(avgAngle);
  }

  void _tryFinalizeCurrentShift() {
    if (_currentTempTable.length < 2) return;

    final first = _currentTempTable.first;
    final last = _currentTempTable.last;
    final shiftAbs = (last.avgAngle - first.avgAngle).abs();

    // Keep collecting while shift is under 5°.
    if (shiftAbs < _shiftAngleThreshold) return;

    final shiftRow =
        FinalSegment.fromTempData(_shiftDataIndex++, _currentTempTable);
    _finalSegments.add(shiftRow);
    _currentRepTable.add(shiftRow);

    print(
        "Сдвиг #${shiftRow.index}: start=${shiftRow.firstAvgAngle.toStringAsFixed(1)}°, abs=${shiftRow.absoluteAngle.toStringAsFixed(1)}°, t=${shiftRow.timeMs}ms");

    _currentTempTable.clear();
  }

  void _detectExtremaAndCountRepetitions(double currentAvgAngle) {
    if (_previousAvgAngle == null) {
      _previousAvgAngle = currentAvgAngle;
      return;
    }

    final delta = currentAvgAngle - _previousAvgAngle!;
    _MovementDirection newDirection = _MovementDirection.unknown;

    if (delta > _directionEpsilon) {
      newDirection = _MovementDirection.up;
    } else if (delta < -_directionEpsilon) {
      newDirection = _MovementDirection.down;
    } else {
      _previousAvgAngle = currentAvgAngle;
      return;
    }

    if (_pendingDirection == _MovementDirection.unknown &&
        _lastDirection != _MovementDirection.unknown &&
        newDirection != _lastDirection) {
      // First opposite sample: register a pivot candidate and wait for
      // additional movement in the new direction to confirm the turn.
      _pendingPivotAngle = _previousAvgAngle!;
      _pendingDirection = newDirection;
      _directionBeforePending = _lastDirection;
      _previousAvgAngle = currentAvgAngle;
      return;
    }

    if (_pendingDirection != _MovementDirection.unknown) {
      if (newDirection != _pendingDirection) {
        // Reversal was not stable, drop candidate.
        _pendingPivotAngle = null;
        _pendingDirection = _MovementDirection.unknown;
        _directionBeforePending = _MovementDirection.unknown;
      } else if (_pendingPivotAngle != null) {
        final movedInNewDirection =
            (currentAvgAngle - _pendingPivotAngle!).abs();
        if (movedInNewDirection >= _turnConfirmationDelta) {
          final extremumAngle = _pendingPivotAngle!;
          if (_directionBeforePending == _MovementDirection.up &&
              _pendingDirection == _MovementDirection.down) {
            _onLocalMaximum(extremumAngle);
          } else if (_directionBeforePending == _MovementDirection.down &&
              _pendingDirection == _MovementDirection.up) {
            _onLocalMinimum(extremumAngle);
          }

          _lastDirection = _pendingDirection;
          _pendingPivotAngle = null;
          _pendingDirection = _MovementDirection.unknown;
          _directionBeforePending = _MovementDirection.unknown;
          _previousAvgAngle = currentAvgAngle;
          return;
        }
      }
    }

    _lastDirection = newDirection;
    _previousAvgAngle = currentAvgAngle;
  }

  void _onLocalMaximum(double angle) {
    print("Локальный максимум: ${angle.toStringAsFixed(1)}°");

    // Full repetition is counted only after a valid minimum.
    if (!_sawLocalMinInCurrentRep) return;
    if (angle < _maxAngle - _extremaTolerance) return;

    if (_currentRepTable.isNotEmpty) {
      // When turn is confirmed at the top, the very first descending shift
      // (typically starting near max angle) can already be in the current
      // table. Move it to the next repetition so each rep starts from max.
      final carryForNextRep = _extractTopBoundaryShift();

      _repetitionTables.add(List<FinalSegment>.from(_currentRepTable));
      final repNumber = _repetitionTables.length;
      print(
          "Максимум #$repNumber подтверждён. Повтор #$repNumber сохранён (${_currentRepTable.length} строк)");
      _printRepetitionTable(repNumber, _currentRepTable);
      _currentRepTable.clear();

      if (carryForNextRep != null) {
        _currentRepTable.add(carryForNextRep);
      }
    }

    _completedReps = _repetitionTables.length;
    _sawLocalMinInCurrentRep = false;

    if (_completedReps >= _targetReps) {
      print("Достигнуто $_targetReps повторений, завершение записи");
      _isRecordingReference = false;
      add(BleStopReferenceRecording());
    }
  }

  FinalSegment? _extractTopBoundaryShift() {
    if (_currentRepTable.isEmpty) return null;

    final last = _currentRepTable.last;
    final isNearTop = last.firstAvgAngle >= (_maxAngle - _extremaTolerance);
    if (!isNearTop) return null;

    // Move boundary row to next repetition to avoid losing first top sample.
    return _currentRepTable.removeLast();
  }

  void _onLocalMinimum(double angle) {
    print("Локальный минимум: ${angle.toStringAsFixed(1)}°");
    if (angle <= _minAngle + _extremaTolerance) {
      _sawLocalMinInCurrentRep = true;
    }
  }

  void _printRepetitionTable(int repNumber, List<FinalSegment> repTable) {
    print("---------- TABLE $repNumber / $_targetReps ----------");
    if (repTable.isEmpty) {
      print("Таблица повтора пуста");
      print("----------------------------------------");
      return;
    }

    for (final row in repTable) {
      print(
          "idx=${row.index.toString().padLeft(3)} | start=${row.firstAvgAngle.toStringAsFixed(2).padLeft(7)} | abs=${row.absoluteAngle.toStringAsFixed(2).padLeft(6)} | emg=${row.avgEmg.toStringAsFixed(2).padLeft(8)} | t=${row.timeMs.toString().padLeft(4)}ms");
    }
    print("----------------------------------------");
  }

  Future<void> _saveReferenceToStorage() async {
    final prefs = await SharedPreferences.getInstance();

    // Save reference segments
    final jsonList = _referenceSegments.map((e) => e.toJson()).toList();
    final encoded = jsonEncode(jsonList);
    await prefs.setString(_referenceTableKey, encoded);

    print(
        "Эталонная таблица сохранена: ${_referenceSegments.length} сегментов");
  }

  Future<void> _saveRepetitionTablesToStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final limitedTables = _repetitionTables.take(_targetReps).toList();

    final tablesJson = limitedTables
        .map((table) => table.map((row) => row.toJson()).toList())
        .toList();

    await prefs.setString(_repetitionTablesKey, jsonEncode(tablesJson));
    print("Сохранено таблиц повторов: ${limitedTables.length}");
  }

  Future<void> _savePhaseProfileToStorage() async {
    if (_phasePhi.isEmpty ||
        _phaseTheta.isEmpty ||
        _phaseEmg.isEmpty ||
        _phaseTime.isEmpty) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final phaseJson = <String, dynamic>{
      'phi': _phasePhi,
      'theta': _phaseTheta,
      'emg': _phaseEmg,
      'time': _phaseTime,
    };
    await prefs.setString(_phaseProfileKey, jsonEncode(phaseJson));
    print("Фазовый эталон сохранён: ${_phasePhi.length} точек");
  }

  Future<void> printReference() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_referenceTableKey);
    print("REFERENCE DATA: $data");
  }

  Future<void> _onLoadReference(
    BleLoadReference event,
    Emitter<BleState> emit,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final savedMinAngle = prefs.getInt("min_angle_border");
    final savedMaxAngle = prefs.getInt("max_angle_border");

    int minAngle = savedMinAngle ?? state.minAngleBorder;
    int maxAngle = savedMaxAngle ?? state.maxAngleBorder;
    if (maxAngle <= minAngle) {
      minAngle = 0;
      maxAngle = 180;
    }

    final raw = prefs.getString(_referenceTableKey);
    _printSavedRepetitionTables(prefs);
    _printSavedPhaseProfile(prefs);

    if (raw == null) {
      print("========================================");
      print("ETALON STATUS: NOT FOUND");
      print("Reference table not found — running with empty.");
      print("========================================");
      emit(state.copyWith(
        minAngleBorder: minAngle,
        maxAngleBorder: maxAngle,
      ));
      return;
    }

    try {
      final decoded = jsonDecode(raw) as List;
      _referenceSegments =
          decoded.map((e) => ReferenceSegment.fromJson(e)).toList();

      print("========================================");
      print("ETALON DATA LOADED ON APP START");
      print("========================================");
      print("Total segments: ${_referenceSegments.length}");
      print("");

      if (_referenceSegments.isNotEmpty) {
        // Calculate angle range
        final angles = _referenceSegments.map((e) => e.avgAngle).toList();
        final minAngle = angles.reduce((a, b) => a < b ? a : b);
        final maxAngle = angles.reduce((a, b) => a > b ? a : b);
        final totalTime =
            _referenceSegments.fold<int>(0, (sum, seg) => sum + seg.timeMs);

        print(
            "Angle range: ${minAngle.toStringAsFixed(1)}° - ${maxAngle.toStringAsFixed(1)}°");
        print(
            "Total time: ${totalTime}ms (${(totalTime / 1000).toStringAsFixed(2)}s)");
        print("");
        print("Segment details:");
        print("----------------------------------------");

        for (var segment in _referenceSegments) {
          print("Segment ${segment.segment.toString().padLeft(2)}: "
              "angle=${segment.avgAngle.toStringAsFixed(2).padLeft(6)}°, "
              "time=${segment.timeMs.toString().padLeft(4)}ms");
        }
      }

      print("========================================");

      // ОБНОВЛЯЕМ STATE
      emit(
        state.copyWith(
          minAngleBorder: minAngle,
          maxAngleBorder: maxAngle,
          referenceSegments: List.from(_referenceSegments),
        ),
      );
    } catch (e) {
      print("========================================");
      print("ERROR LOADING ETALON");
      print("Error loading reference table: $e");
      print("========================================");
    }
  }

  void _printSavedRepetitionTables(SharedPreferences prefs) {
    final rawTables = prefs.getString(_repetitionTablesKey);
    if (rawTables == null) {
      print("========================================");
      print("REPETITION TABLES STATUS: NOT FOUND");
      print("========================================");
      return;
    }

    try {
      final decoded = jsonDecode(rawTables) as List;
      print("========================================");
      print("SAVED REPETITION TABLES LOADED");
      print("Всего таблиц: ${decoded.length}");
      print("========================================");

      for (int i = 0; i < decoded.length; i++) {
        final tableRaw = decoded[i] as List;
        final tableRows = tableRaw
            .map((row) => FinalSegment.fromJson(row as Map<String, dynamic>))
            .toList();
        _printRepetitionTable(i + 1, tableRows);
      }
    } catch (e) {
      print("========================================");
      print("ERROR LOADING REPETITION TABLES");
      print("Error: $e");
      print("========================================");
    }
  }

  void _printSavedPhaseProfile(SharedPreferences prefs) {
    final rawProfile = prefs.getString(_phaseProfileKey);
    if (rawProfile == null) {
      print("========================================");
      print("PHASE PROFILE STATUS: NOT FOUND");
      print("========================================");
      return;
    }

    try {
      final decoded = jsonDecode(rawProfile) as Map<String, dynamic>;
      final phi = (decoded['phi'] as List).map((e) => (e as num).toDouble());
      final theta =
          (decoded['theta'] as List).map((e) => (e as num).toDouble());
      final emg = (decoded['emg'] as List).map((e) => (e as num).toDouble());
      final time = (decoded['time'] as List).map((e) => (e as num).toDouble());

      print("========================================");
      print("PHASE PROFILE LOADED");
      print(
          "points: phi=${phi.length}, theta=${theta.length}, emg=${emg.length}, time=${time.length}");
      if (phi.isNotEmpty && theta.isNotEmpty && emg.isNotEmpty && time.isNotEmpty) {
        print(
            "sample[0]: phi=${phi.first.toStringAsFixed(2)}, theta=${theta.first.toStringAsFixed(2)}, emg=${emg.first.toStringAsFixed(2)}, time=${time.first.toStringAsFixed(1)}");
        print(
            "sample[last]: phi=${phi.last.toStringAsFixed(2)}, theta=${theta.last.toStringAsFixed(2)}, emg=${emg.last.toStringAsFixed(2)}, time=${time.last.toStringAsFixed(1)}");
      }
      _printFinalReferenceArrays(
        theta: theta.toList(),
        emg: emg.toList(),
        time: time.toList(),
      );
      print("========================================");
    } catch (e) {
      print("========================================");
      print("ERROR LOADING PHASE PROFILE");
      print("Error: $e");
      print("========================================");
    }
  }

  void _printFinalReferenceArrays({
    required List<double> theta,
    required List<double> emg,
    required List<double> time,
  }) {
    print("theta=[${theta.map((v) => v.toStringAsFixed(4)).join(', ')}]");
    print("emg=[${emg.map((v) => v.toStringAsFixed(4)).join(', ')}]");
    print("time=[${time.map((v) => v.toStringAsFixed(4)).join(', ')}]");
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
        final currentAngle = _latestAngle;
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
    final currentAngle = _latestAngle;
    final difference = (currentAngle - referenceAngle).abs();

    emit(state.copyWith(
      elapsedTimeMs: elapsed,
      currentReferenceAngle: referenceAngle,
      angleDifference: difference,
    ));
  }

  Future<void> _onStartDataStream(
    BleStartDataStream event,
    Emitter<BleState> emit,
  ) async {
    print("Запуск потока данных");
    await _bleService.resumeDataStream();
    // _testDataGenerator.start();
  }

  Future<void> _onStopDataStream(
    BleStopDataStream event,
    Emitter<BleState> emit,
  ) async {
    print("Остановка потока данных");
    _bleService.pauseDataStream();
    // _testDataGenerator.stop();
  }

  Future<void> _onUpdateAngleBorders(
    BleUpdateAngleBorders event,
    Emitter<BleState> emit,
  ) async {
    print("Обновление границ углов: ${event.minAngle}° - ${event.maxAngle}°");
    _minAngle = event.minAngle;
    _maxAngle = event.maxAngle;
    await _saveAngleBordersToStorage(event.minAngle, event.maxAngle);
    emit(state.copyWith(
      minAngleBorder: event.minAngle,
      maxAngleBorder: event.maxAngle,
    ));
  }

  Future<void> _saveAngleBordersToStorage(int minAngle, int maxAngle) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt("min_angle_border", minAngle);
    await prefs.setInt("max_angle_border", maxAngle);
  }

  @override
  Future<void> close() async {
    _comparisonTimer?.cancel();
    _bleService.dispose();
    // _testDataGenerator.dispose();
    return super.close();
  }
}
