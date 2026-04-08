import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:math';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'ble_event.dart';
import 'ble_state.dart';
import '../../services/ble_service.dart';
import '../../services/app_logger.dart';
import '../../services/pchip.dart';
// import '../../services/test_data_generator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/reference_segment.dart';
import '../../models/temp_segment_data.dart';
import '../../models/final_segment.dart';

enum _MovementDirection { unknown, up, down }

enum _ExtremumType { minimum, maximum }

class _RuntimeRepPoint {
  final double angle;
  final int status; // -1=unknown, 0=inactive, 1=active

  const _RuntimeRepPoint({
    required this.angle,
    required this.status,
  });
}

class BleBloc extends Bloc<BleEvent, BleState> {
  static const String _referenceTableKey = "reference_table";
  static const String _repetitionTablesKey = "reference_repetition_tables";
  static const String _phaseProfileKey = "reference_phase_profile";
  static const int _phaseGridPoints = 101;

  late BleService _bleService;
  bool _acceptIncomingData = true;
  // late TestDataGenerator _testDataGenerator;

  bool _isRecordingReference = false;
  int _minAngle = 0; // Minimum angle for recording
  int _maxAngle = 180; // Maximum angle for recording
  DateTime? _recordingStartTime;
  int _tempDataIndex = 0; // Index for temp table rows (packet table)
  int _shiftDataIndex = 0; // Index for shift table rows

  // In one BLE packet MCU may send multiple sequential samples.
  static const int _inPacketSampleSpacingMs = 20;
  int _lastRecordedSampleTimeMs = -1;
  // UI/state buffers to avoid data loss between throttled emits
  final List<double> _anglesForUi = [];
  final List<double> _emgForUi = [];
  final List<double> _emgMedianWindow = [];
  int _emgSampleCount = 0;
  double? _emgEmaValue;
  double _latestAngle = 0.0;
  double? _emaAngle;
  // Adaptive EMA: lower alpha for calm motion, higher alpha for sharp motion.
  static const double _angleEmaAlphaMin = 0.15;
  static const double _angleEmaAlphaMax = 0.85;
  static const double _emaSlowDeltaDeg = 0.5;
  static const double _emaFastDeltaDeg = 8.0;
  static const int _emgMedianWindowSize = 3;
  static const double _emgEmaDtSeconds = 0.02;
  static const double _emgEmaTauUpSeconds = 0.08;
  static const double _emgEmaTauDownSeconds = 0.18;
  static const double _referenceActivationThreshold = 0.2;
  static const double _realtimeActivationKOn = 3.0;
  static const double _realtimeActivationKOff = 1.8;
  static const int _realtimeActivationSamplePoints = 3;
  static const double _runtimeExtremumEpsilon = 0.1;

  // Repetition tracking (auto-detected start: max/min cycle)
  int _completedReps = 0;
  final int _targetReps = 10;
  _ExtremumType? _anchorExtremum;
  bool _sawOppositeExtremumInCurrentRep = false;
  double? _previousAvgAngle;
  _MovementDirection _lastDirection = _MovementDirection.unknown;

  // Thresholds used by the new algorithm
  static const double _shiftAngleThreshold = 5.0;
  static const double _directionEpsilon = 0.5;
  static const double _turnConfirmationDelta = 2.0;
  static const int _turnDirectionConfirmationSamples = 8;
  double? _pendingPivotAngle;
  _MovementDirection _pendingDirection = _MovementDirection.unknown;
  _MovementDirection _directionBeforePending = _MovementDirection.unknown;
  final List<_MovementDirection> _pendingDirectionWindow = [];

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
  bool _awaitingTerminalEmgSample = false;
  double? _terminalEmgFromNextPacket;

  // Comparison mode
  bool _isComparing = false;
  DateTime? _comparisonStartTime;
  Timer? _comparisonTimer;

  // EMG baseline calibration
  static const int _baselineCalibrationDurationMs = 4000;
  static const int _baselinePhaseDurationMs = 2000;
  static const double _noiseScaleFactor = 1.4826;
  double _emgBaseline = 0.0;
  double _emgNoise = 0.0;
  bool _isCollectingBaseline = false;
  bool _isCollectingNoise = false;
  final List<double> _baselineSamples = [];
  final List<double> _noiseDeviationSamples = [];
  Timer? _baselineTimer;
  Timer? _baselinePhaseTimer;

  // EMG activity comparison state (reference vs runtime)
  List<int> _referenceMuscleStatus = [];
  List<int> _currentRepMuscleStatus = [];
  List<int> _previousRepMuscleStatus = [];
  final List<_RuntimeRepPoint> _runtimeRepPoints = [];
  int _runtimeRepWriteIndex = 0;
  bool _runtimeRepStarted = false;
  bool _runtimeMuscleActive = false;
  int _runtimeActivationStreak = 0;
  int _runtimeDeactivationStreak = 0;
  double _currentRepEffortPercent = 0.0;
  double _referenceMinEmg = 0.0;
  double _referenceMaxEmg = 1.0;

  _ExtremumType? _runtimeAnchorExtremum;
  bool _runtimeSawOppositeExtremum = false;
  final List<double> _runtimeAngleDetectionWindow = [];

  // Performance monitoring
  int _droppedFrames = 0;
  DateTime _lastProcessTime = DateTime.now();

  BleBloc() : super(BleState.initial()) {
    _bleService = BleService(
      targetDeviceName: "MyESP32",
      onNewData: ({
        required angleValues,
        required emgValues,
        required timeValues,
      }) {
        if (!_acceptIncomingData) return;
        add(BleNewDataReceived(
          angleValues: angleValues,
          emgValues: emgValues,
          timeValues: timeValues,
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
    on<BleStartBaselineCalibration>(_onStartBaselineCalibration);
    on<BleFinishBaselineCalibration>(_onFinishBaselineCalibration);
  }

  // Used by UI screens that need to open modal interactions without BLE flood.
  void suspendIncomingDataImmediately() {
    _acceptIncomingData = false;
  }

  void resumeIncomingDataImmediately() {
    _acceptIncomingData = true;
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
    _emgMedianWindow.clear();
    _emgSampleCount = 0;
    _emgEmaValue = null;
    _latestAngle = 0.0;
    _emaAngle = null;
    _referenceMuscleStatus = [];
    _currentRepMuscleStatus = [];
    _previousRepMuscleStatus = [];
    _resetRuntimeComparisonTracking();

    emit(
      state.copyWith(
        values: [],
        emgValues: [],
        emgStartX: 0,
        referenceMuscleStatus: [],
        currentRepMuscleStatus: [],
        previousRepMuscleStatus: [],
        currentRepEffortPercent: 0.0,
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
        appTalker.warning(
            "BLE bloc slow processing: ${timeSinceLastProcess}ms (dropped: $_droppedFrames)");
      }
    }
    _lastProcessTime = now;

    // Process and render packet angles immediately (without playback queue).
    if (event.angleValues.isNotEmpty) {
      for (final rawAngle in event.angleValues) {
        if (_emaAngle == null) {
          _emaAngle = rawAngle;
        } else {
          final alpha = _adaptiveEmaAlpha(rawAngle);
          _emaAngle = alpha * rawAngle + (1 - alpha) * _emaAngle!;
        }
        _latestAngle = _emaAngle!;
        _anglesForUi.add(_latestAngle);
      }
      if (_anglesForUi.length > 500) {
        _anglesForUi.removeRange(0, _anglesForUi.length - 500);
      }
    }

    final adjustedPacketEmg = <double>[];
    if (event.emgValues.isNotEmpty) {
      final packetEmg = event.emgValues;
      if (_isCollectingBaseline) {
        for (final emgValue in packetEmg) {
          if (_isCollectingNoise) {
            final adjusted = _applyBaseline(emgValue);
            final medianFiltered = _nextEmgMedian(adjusted);
            if (medianFiltered == null) {
              continue;
            }
            final emgNow = _updateEmgAttackReleaseEma(medianFiltered);
            final deviation = (_emgBaseline - emgNow).abs();
            _noiseDeviationSamples.add(deviation);
          } else {
            _baselineSamples.add(emgValue);
          }
        }
      } else {
        for (int i = 0; i < packetEmg.length; i++) {
          final emgValue = packetEmg[i];
          final adjusted = _applyBaseline(emgValue);
          final medianFiltered = _nextEmgMedian(adjusted);
          if (medianFiltered == null) {
            continue;
          }

          final emaFiltered = _updateEmgAttackReleaseEma(medianFiltered);
          final angleForSample = event.angleValues.isNotEmpty
              ? _valueAtOrLast(event.angleValues, i)
              : _latestAngle;

          _processRealtimeEmgComparisonSample(
            emgNow: emaFiltered,
            currentAngle: angleForSample,
          );

          adjustedPacketEmg.add(emaFiltered);
          _emgForUi.add(emaFiltered);
          _emgSampleCount++;
        }
      }

      if (_emgForUi.length > 500) {
        _emgForUi.removeRange(0, _emgForUi.length - 500);
      }
    }

    // Process recording data (always process, regardless of UI throttling)
    if (_isRecordingReference) {
      _processReferenceData(
        event.angleValues,
        adjustedPacketEmg,
        event.timeValues,
      );
    }

    // Update charts directly on new packets.
    final emgStartX =
        (_emgSampleCount - _emgForUi.length) * _inPacketSampleSpacingMs;
    emit(state.copyWith(
      values: List<double>.from(_anglesForUi),
      emgValues: List<double>.from(_emgForUi),
      emgStartX: emgStartX < 0 ? 0 : emgStartX,
      referenceMuscleStatus: List<int>.from(_referenceMuscleStatus),
      currentRepMuscleStatus: List<int>.from(_currentRepMuscleStatus),
      previousRepMuscleStatus: List<int>.from(_previousRepMuscleStatus),
      currentRepEffortPercent: _currentRepEffortPercent,
      emgNoise: _emgNoise,
    ));
  }

  double _adaptiveEmaAlpha(double rawAngle) {
    if (_emaAngle == null) return _angleEmaAlphaMax;

    final delta = (rawAngle - _emaAngle!).abs();
    if (delta <= _emaSlowDeltaDeg) return _angleEmaAlphaMin;
    if (delta >= _emaFastDeltaDeg) return _angleEmaAlphaMax;

    final t =
        (delta - _emaSlowDeltaDeg) / (_emaFastDeltaDeg - _emaSlowDeltaDeg);
    return _angleEmaAlphaMin + (_angleEmaAlphaMax - _angleEmaAlphaMin) * t;
  }

  double? _nextEmgMedian(double emgValue) {
    _emgMedianWindow.add(emgValue);
    if (_emgMedianWindow.length < _emgMedianWindowSize) {
      return null;
    }

    if (_emgMedianWindow.length > _emgMedianWindowSize) {
      _emgMedianWindow.removeAt(0);
    }

    return _median(_emgMedianWindow);
  }

  double _updateEmgAttackReleaseEma(double x) {
    _emgEmaValue ??= x;
    final yPrev = _emgEmaValue!;
    final rising = x > yPrev;
    final tau = rising ? _emgEmaTauUpSeconds : _emgEmaTauDownSeconds;
    final alpha = 1.0 - exp(-_emgEmaDtSeconds / tau);
    final yNew = yPrev + alpha * (x - yPrev);
    _emgEmaValue = yNew;
    return yNew;
  }

  double _applyBaseline(double emgValue) {
    return (emgValue - _emgBaseline).abs();
  }

  Future<void> _onStartBaselineCalibration(
    BleStartBaselineCalibration event,
    Emitter<BleState> emit,
  ) async {
    _baselinePhaseTimer?.cancel();
    _baselineTimer?.cancel();
    _baselineSamples.clear();
    _noiseDeviationSamples.clear();
    _emgMedianWindow.clear();
    _emgEmaValue = null;
    _isCollectingBaseline = true;
    _isCollectingNoise = false;
    appTalker.info(
      "EMG baseline calibration started (${_baselineCalibrationDurationMs}ms)",
    );
    _baselinePhaseTimer = Timer(
      const Duration(milliseconds: _baselinePhaseDurationMs),
      _startNoiseCollectionPhase,
    );
    _baselineTimer = Timer(
      const Duration(milliseconds: _baselineCalibrationDurationMs),
      () {
        if (!isClosed) {
          add(BleFinishBaselineCalibration());
        }
      },
    );
  }

  Future<void> _onFinishBaselineCalibration(
    BleFinishBaselineCalibration event,
    Emitter<BleState> emit,
  ) async {
    _baselinePhaseTimer?.cancel();
    _baselinePhaseTimer = null;
    _baselineTimer?.cancel();
    _baselineTimer = null;
    _isCollectingBaseline = false;

    if (_isCollectingNoise && _noiseDeviationSamples.isNotEmpty) {
      final deviationMedian = _median(_noiseDeviationSamples);
      _emgNoise = _noiseScaleFactor * deviationMedian;
      appTalker.info(
        "EMG calibration finished: baseline=$_emgBaseline, noise=$_emgNoise, deviations=${_noiseDeviationSamples.length}",
      );
    } else if (_baselineSamples.isEmpty) {
      appTalker.warning(
        "EMG baseline calibration finished without samples. Keep previous baseline=$_emgBaseline",
      );
    } else {
      _emgBaseline = _median(_baselineSamples);
      appTalker.warning(
        "EMG baseline calibration finished without noise samples. baseline=$_emgBaseline, keep previous noise=$_emgNoise",
      );
    }

    _isCollectingNoise = false;
    _baselineSamples.clear();
    _noiseDeviationSamples.clear();
    _emgMedianWindow.clear();
    _emgEmaValue = null;
    emit(state.copyWith(emgNoise: _emgNoise));
  }

  void _startNoiseCollectionPhase() {
    if (!_isCollectingBaseline) return;
    if (_baselineSamples.isEmpty) {
      appTalker.warning(
        "EMG baseline phase finished without samples. Keep previous baseline=$_emgBaseline",
      );
      _isCollectingNoise = true;
      return;
    }

    _emgBaseline = _median(_baselineSamples);
    _baselineSamples.clear();
    _noiseDeviationSamples.clear();
    _emgMedianWindow.clear();
    _emgEmaValue = null;
    _isCollectingNoise = true;

    appTalker.info(
      "EMG baseline phase finished: baseline=$_emgBaseline. Start noise collection (${_baselineCalibrationDurationMs - _baselinePhaseDurationMs}ms)",
    );
  }

  void _prepareReferenceMuscleStatus() {
    if (_phaseEmg.isEmpty || _phaseTheta.isEmpty) {
      _referenceMuscleStatus = [];
      _currentRepMuscleStatus = [];
      _previousRepMuscleStatus = [];
      _referenceMinEmg = 0.0;
      _referenceMaxEmg = 1.0;
      return;
    }

    _referenceMinEmg = _phaseEmg.reduce(min);
    _referenceMaxEmg = _phaseEmg.reduce(max);
    final emgRange = (_referenceMaxEmg - _referenceMinEmg).abs();
    _referenceMuscleStatus = _phaseEmg.map((emg) {
      final relative =
          emgRange < 1e-9 ? 0.0 : (emg - _referenceMinEmg) / emgRange;
      return relative > _referenceActivationThreshold ? 1 : 0;
    }).toList();

    _currentRepMuscleStatus =
        List<int>.filled(_referenceMuscleStatus.length, -1);
    _previousRepMuscleStatus =
        List<int>.filled(_referenceMuscleStatus.length, -1);
  }

  void _resetRuntimeComparisonTracking() {
    _runtimeRepPoints.clear();
    _runtimeRepWriteIndex = 0;
    _runtimeRepStarted = false;
    _runtimeMuscleActive = false;
    _runtimeActivationStreak = 0;
    _runtimeDeactivationStreak = 0;
    _currentRepEffortPercent = 0.0;
    _runtimeAnchorExtremum = null;
    _runtimeSawOppositeExtremum = false;
    _runtimeAngleDetectionWindow.clear();

    if (_referenceMuscleStatus.isNotEmpty) {
      _currentRepMuscleStatus =
          List<int>.filled(_referenceMuscleStatus.length, -1);
      _previousRepMuscleStatus =
          List<int>.filled(_referenceMuscleStatus.length, -1);
    } else {
      _currentRepMuscleStatus = [];
      _previousRepMuscleStatus = [];
    }
  }

  void _processRealtimeEmgComparisonSample({
    required double emgNow,
    required double currentAngle,
  }) {
    if (!_isComparing || _referenceMuscleStatus.isEmpty) return;

    final maxRefEmg = _referenceMaxEmg <= 0 ? 1.0 : _referenceMaxEmg;
    _currentRepEffortPercent = (emgNow / maxRefEmg * 100).clamp(0.0, 999.0);

    final isMuscleActive = _updateRuntimeMuscleState(emgNow);
    _processRuntimeRepPoint(
        currentAngle: currentAngle, isMuscleActive: isMuscleActive);
    if (_runtimeRepStarted) {
      _detectRuntimeExtrema(currentAngle);
    }
  }

  bool _updateRuntimeMuscleState(double emgNow) {
    final noiseBase = _emgNoise <= 1e-9 ? 1.0 : _emgNoise;
    final onThreshold = _realtimeActivationKOn * noiseBase;
    final offThreshold = _realtimeActivationKOff * noiseBase;

    if (!_runtimeMuscleActive) {
      if (emgNow >= onThreshold) {
        _runtimeActivationStreak++;
      } else {
        _runtimeActivationStreak = 0;
      }
      _runtimeDeactivationStreak = 0;
      if (_runtimeActivationStreak >= _realtimeActivationSamplePoints) {
        _runtimeMuscleActive = true;
        _runtimeActivationStreak = 0;
      }
      return _runtimeMuscleActive;
    }

    if (emgNow <= offThreshold) {
      _runtimeDeactivationStreak++;
    } else {
      _runtimeDeactivationStreak = 0;
    }
    _runtimeActivationStreak = 0;
    if (_runtimeDeactivationStreak >= _realtimeActivationSamplePoints) {
      _runtimeMuscleActive = false;
      _runtimeDeactivationStreak = 0;
    }
    return _runtimeMuscleActive;
  }

  void _processRuntimeRepPoint({
    required double currentAngle,
    required bool isMuscleActive,
  }) {
    if (!_runtimeRepStarted) {
      _runtimeRepStarted = true;
      _runtimeRepPoints.clear();
      _runtimeRepWriteIndex = 0;
      // Start extrema detection from scratch for this repetition only.
      _runtimeAnchorExtremum = null;
      _runtimeSawOppositeExtremum = false;
      _runtimeAngleDetectionWindow.clear();
      _currentRepMuscleStatus =
          List<int>.filled(_referenceMuscleStatus.length, -1);
    }

    final status = isMuscleActive ? 1 : 0;
    _runtimeRepPoints
        .add(_RuntimeRepPoint(angle: currentAngle, status: status));
    if (_currentRepMuscleStatus.isEmpty) return;
    if (_runtimeRepWriteIndex < _currentRepMuscleStatus.length) {
      _currentRepMuscleStatus[_runtimeRepWriteIndex] = status;
      _runtimeRepWriteIndex++;
      return;
    }
    // If incoming stream is longer than reference grid, keep updating tail cell.
    _currentRepMuscleStatus[_currentRepMuscleStatus.length - 1] = status;
  }

  void _detectRuntimeExtrema(double currentAngle) {
    _runtimeAngleDetectionWindow.add(currentAngle);
    if (_runtimeAngleDetectionWindow.length < 4) {
      return;
    }
    if (_runtimeAngleDetectionWindow.length > 4) {
      _runtimeAngleDetectionWindow.removeAt(0);
    }

    // For exercise runtime only:
    // candidate extremum is confirmed by the next 2 angle samples.
    final prev = _runtimeAngleDetectionWindow[0];
    final candidate = _runtimeAngleDetectionWindow[1];
    final next1 = _runtimeAngleDetectionWindow[2];
    final next2 = _runtimeAngleDetectionWindow[3];

    final isMaximum = (candidate - prev) > _runtimeExtremumEpsilon &&
        (candidate - next1) > _runtimeExtremumEpsilon &&
        (candidate - next2) > _runtimeExtremumEpsilon;
    if (isMaximum) {
      _onRuntimeExtremumDetected(_ExtremumType.maximum);
      return;
    }

    final isMinimum = (prev - candidate) > _runtimeExtremumEpsilon &&
        (next1 - candidate) > _runtimeExtremumEpsilon &&
        (next2 - candidate) > _runtimeExtremumEpsilon;
    if (isMinimum) {
      _onRuntimeExtremumDetected(_ExtremumType.minimum);
    }
  }

  void _onRuntimeExtremumDetected(_ExtremumType currentExtremum) {
    if (_runtimeAnchorExtremum == null) {
      _runtimeAnchorExtremum = currentExtremum;
      _runtimeSawOppositeExtremum = false;
      return;
    }

    if (currentExtremum != _runtimeAnchorExtremum) {
      _runtimeSawOppositeExtremum = true;
      return;
    }

    if (!_runtimeSawOppositeExtremum) return;

    if (_runtimeRepStarted && _currentRepMuscleStatus.isNotEmpty) {
      _previousRepMuscleStatus = List<int>.from(_currentRepMuscleStatus);
    }

    _runtimeRepPoints.clear();
    _runtimeRepWriteIndex = 0;
    _currentRepMuscleStatus =
        List<int>.filled(_referenceMuscleStatus.length, -1);
    _runtimeRepStarted = false;
    _runtimeAnchorExtremum = null;
    _runtimeSawOppositeExtremum = false;
    _runtimeAngleDetectionWindow.clear();
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
    _anchorExtremum = _ExtremumType.maximum;
    _sawOppositeExtremumInCurrentRep = false;
    _previousAvgAngle = null;
    _lastDirection = _MovementDirection.unknown;
    _pendingPivotAngle = null;
    _pendingDirection = _MovementDirection.unknown;
    _directionBeforePending = _MovementDirection.unknown;
    _pendingDirectionWindow.clear();

    _finalSegments.clear();
    _currentTempTable.clear();
    _currentRepTable.clear();
    _repetitionTables.clear();
    _lastRecordedSampleTimeMs = -1;
    _awaitingTerminalEmgSample = false;
    _terminalEmgFromNextPacket = null;

    appTalker.info(
        "Эталон: старт записи ($_targetReps повторений, диапазон $_minAngle°-$_maxAngle°, фиксированный цикл max->min->max)");
    emit(state.copyWith(isRecordingReference: true));
  }

  Future<void> _onStopReference(
    BleStopReferenceRecording event,
    Emitter<BleState> emit,
  ) async {
    _isRecordingReference = false;
    _awaitingTerminalEmgSample = false;

    // Flush current temp table if it already reached threshold but was not
    // finalized yet due to manual stop timing.
    _tryFinalizeCurrentShift();

    appTalker.info(
        "Эталон: начало обработки, повторы=${_repetitionTables.length}, сдвиги=${_finalSegments.length}");

    if (_repetitionTables.isEmpty) {
      appTalker.warning("Эталон: нет данных повторов для обработки");
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
    appTalker.info(
        "Эталон: усреднено в ${_referenceSegments.length} референсных сегментов");

    // Save to SharedPreferences
    await _saveRepetitionTablesToStorage();
    await _savePhaseProfileToStorage();
    await _saveReferenceToStorage();

    appTalker.critical("Эталон успешно создан");

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

    for (int trialIndex = 0; trialIndex < repTables.length; trialIndex++) {
      final table = repTables[trialIndex];
      final nextRepFirstAvgEmg = trialIndex + 1 < repTables.length
          ? (repTables[trialIndex + 1].isNotEmpty
              ? repTables[trialIndex + 1].first.avgEmg
              : null)
          : _terminalEmgFromNextPacket;
      final timeSeries = _buildTimePhaseSeries(
        table,
        nextRepFirstAvgEmg: nextRepFirstAvgEmg,
      );
      final angleSeries = _buildAnglePhaseSeries(table);
      if (timeSeries == null || angleSeries == null) {
        continue;
      }

      try {
        final thetaPchip = Pchip(timeSeries['phi']!, timeSeries['theta']!);
        final emgPchip = Pchip(timeSeries['phi']!, timeSeries['emg']!);
        final timePchip = Pchip(angleSeries['phi']!, angleSeries['time']!);

        final thetaResampled = thetaPchip.resample(phiGrid);
        final emgResampled = emgPchip.resample(phiGrid);
        final timeResampled = timePchip.resample(phiGrid);
        thetaTrials.add(thetaResampled);
        emgTrials.add(emgResampled);
        timeTrials.add(timeResampled);

        _logInterpolationTrial(
          trialIndex: thetaTrials.length - 1,
          timeSeries: timeSeries,
          angleSeries: angleSeries,
          phiGrid: phiGrid,
          thetaResampled: thetaResampled,
          emgResampled: emgResampled,
          timeResampled: timeResampled,
        );
      } catch (e) {
        appTalker
            .warning("Эталон: пропуск таблицы при фазовой интерполяции: $e");
      }
    }

    if (thetaTrials.isEmpty || emgTrials.isEmpty || timeTrials.isEmpty) {
      appTalker.warning(
          "Эталон: недостаточно валидных таблиц для фазовой нормализации");
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

    appTalker.info(
        "Эталон: фазовая нормализация готова (trials=${thetaTrials.length}, points=$_phaseGridPoints)");
    _printFinalReferenceArrays(
      phi: _phasePhi,
      theta: _phaseTheta,
      emg: _phaseEmg,
      time: _phaseTime,
    );
    return true;
  }

  void _logInterpolationTrial({
    required int trialIndex,
    required Map<String, List<double>> timeSeries,
    required Map<String, List<double>> angleSeries,
    required List<double> phiGrid,
    required List<double> thetaResampled,
    required List<double> emgResampled,
    required List<double> timeResampled,
  }) {
    dev.log(
      "Interpolation trial #$trialIndex input(time): "
      "phi=[${timeSeries['phi']!.join(', ')}], "
      "theta=[${timeSeries['theta']!.join(', ')}], "
      "emg=[${timeSeries['emg']!.join(', ')}]",
      name: 'BleBloc.Interpolation',
    );
    dev.log(
      "Interpolation trial #$trialIndex input(angle): "
      "phi=[${angleSeries['phi']!.join(', ')}], "
      "time=[${angleSeries['time']!.join(', ')}]",
      name: 'BleBloc.Interpolation',
    );
    dev.log(
      "Interpolation trial #$trialIndex grid/resampled: "
      "phiGrid=[${phiGrid.join(', ')}], "
      "theta=[${thetaResampled.join(', ')}], "
      "emg=[${emgResampled.join(', ')}], "
      "time=[${timeResampled.join(', ')}]",
      name: 'BleBloc.Interpolation',
    );
  }

  Map<String, List<double>>? _buildTimePhaseSeries(
    List<FinalSegment> table, {
    double? nextRepFirstAvgEmg,
  }) {
    if (table.isEmpty) return null;

    final nodes = _buildAngleTimeNodes(
      table,
      nextRepFirstAvgEmg: nextRepFirstAvgEmg,
    );
    if (nodes == null) return null;
    final theta = nodes['theta']!;
    final emg = nodes['emg']!;
    final cumulativeTime = nodes['time']!;

    final totalTime = cumulativeTime.last;
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

    final nodes = _buildAngleTimeNodes(table);
    if (nodes == null) return null;
    final theta = nodes['theta']!;
    final cumulativeTime = nodes['time']!;

    final cumulativeAngle = <double>[0.0];
    var runningAngle = 0.0;
    for (int i = 1; i < theta.length; i++) {
      final dTheta = (theta[i] - theta[i - 1]).abs();
      runningAngle += dTheta;
      cumulativeAngle.add(runningAngle);
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

  Map<String, List<double>>? _buildAngleTimeNodes(
    List<FinalSegment> table, {
    double? nextRepFirstAvgEmg,
  }) {
    if (table.isEmpty) return null;

    final theta = <double>[table.first.firstAvgAngle];
    final emg = <double>[];
    final cumulativeTime = <double>[0.0];

    var runningTime = 0.0;
    for (final row in table) {
      final dt = max(0, row.timeMs).toDouble();
      runningTime += dt;
      theta.add(row.lastAvgAngle);
      emg.add(row.avgEmg);
      cumulativeTime.add(runningTime);
    }
    emg.add(nextRepFirstAvgEmg ?? table.last.avgEmg);

    if (theta.length < 2 || cumulativeTime.length < 2) return null;
    return {
      'theta': theta,
      'emg': emg,
      'time': cumulativeTime,
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
    result[0] = 0; // phi=0 must correspond to the initial angle at t=0.
    for (int i = 1; i < cumulativeTime.length; i++) {
      final dt = (cumulativeTime[i] - cumulativeTime[i - 1]).round();
      result[i] = dt <= 0 ? 1 : dt;
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
    List<double> newAngles,
    List<double> newEmgValues,
    List<double> newTimeValues,
  ) {
    if (!_isRecordingReference || _recordingStartTime == null) return;
    if (newAngles.isEmpty || newEmgValues.isEmpty) return;

    if (_awaitingTerminalEmgSample) {
      _terminalEmgFromNextPacket = _valueAtOrLast(newEmgValues, 0);
      _awaitingTerminalEmgSample = false;
      appTalker.info(
        "Эталон: финальная EMG-точка взята из следующего пакета: $_terminalEmgFromNextPacket",
      );
      _isRecordingReference = false;
      add(BleStopReferenceRecording());
      return;
    }

    final packetTimeMs =
        DateTime.now().difference(_recordingStartTime!).inMilliseconds;
    final sampleCount = max(newAngles.length, newEmgValues.length);

    for (int i = 0; i < sampleCount; i++) {
      final angle = _valueAtOrLast(newAngles, i);
      final emg = _valueAtOrLast(newEmgValues, i);

      // Prefer MCU timestamps from packet. Fallback to local approximation.
      var sampleTimeMs = _resolveSampleTimeMs(
        packetTimeMs: packetTimeMs,
        timeValuesFromMcu: newTimeValues,
        sampleIndex: i,
        sampleCount: sampleCount,
      );
      if (sampleTimeMs <= _lastRecordedSampleTimeMs) {
        sampleTimeMs = _lastRecordedSampleTimeMs + 1;
      }
      _lastRecordedSampleTimeMs = sampleTimeMs;

      _currentTempTable.add(TempSegmentData(
        index: _tempDataIndex++,
        avgAngle: angle,
        avgEmg: emg,
        timeMs: sampleTimeMs,
      ));

      _tryFinalizeCurrentShift();
      _detectExtremaAndCountRepetitions(angle);
    }
  }

  double _valueAtOrLast(List<double> values, int index) {
    if (index < values.length) return values[index];
    return values.last;
  }

  int _resolveSampleTimeMs({
    required int packetTimeMs,
    required List<double> timeValuesFromMcu,
    required int sampleIndex,
    required int sampleCount,
  }) {
    if (timeValuesFromMcu.isNotEmpty) {
      // MCU time is used as packet anchor; inside one packet we keep fixed
      // spacing between sequential samples.
      final anchorTimeMs = _valueAtOrLast(
        timeValuesFromMcu,
        sampleCount - 1,
      ).round();
      if (anchorTimeMs >= 0) {
        final offsetFromNewest =
            (sampleCount - 1 - sampleIndex) * _inPacketSampleSpacingMs;
        final estimatedFromAnchor = anchorTimeMs - offsetFromNewest;
        return estimatedFromAnchor < 0 ? 0 : estimatedFromAnchor;
      }
    }

    final offsetFromNewest =
        (sampleCount - 1 - sampleIndex) * _inPacketSampleSpacingMs;
    final estimated = packetTimeMs - offsetFromNewest;
    return estimated < 0 ? 0 : estimated;
  }

  void _tryFinalizeCurrentShift() {
    if (_currentTempTable.length < 2) return;

    final first = _currentTempTable.first;
    final last = _currentTempTable.last;
    final shiftAbs = (last.avgAngle - first.avgAngle).abs();

    // Keep collecting while shift is under 5°.
    if (shiftAbs < _shiftAngleThreshold) return;

    // Boundary sample (that reaches 5° threshold) is included in finalized
    // segment and also carried over as the first sample of the next segment.
    final carryToNextSegment = _currentTempTable.last;
    final finalizedRows = List<TempSegmentData>.from(_currentTempTable);
    if (finalizedRows.length < 2) return;

    final shiftRow =
        FinalSegment.fromTempData(_shiftDataIndex++, finalizedRows);
    _finalSegments.add(shiftRow);
    _currentRepTable.add(shiftRow);
    _printCurrentTempTableBeforeFinalize(finalizedRows, carryToNextSegment);

    appTalker.info(
        "Сдвиг #${shiftRow.index}: start=${shiftRow.firstAvgAngle.toStringAsFixed(1)}°, abs=${shiftRow.absoluteAngle.toStringAsFixed(1)}°, t=${shiftRow.timeMs}ms");

    _currentTempTable
      ..clear()
      ..add(carryToNextSegment);
  }

  void _printCurrentTempTableBeforeFinalize(
    List<TempSegmentData> rows,
    TempSegmentData carryToNextSegment,
  ) {
    print("----- TEMP TIME TABLE (before 5° segment finalize) -----");
    if (rows.isEmpty) {
      print("Пусто");
      print("---------------------------------------------------------");
      return;
    }

    final firstTime = rows.first.timeMs;
    int prevTime = firstTime;
    for (final row in rows) {
      final dtFromStart = row.timeMs - firstTime;
      final dtFromPrev = row.timeMs - prevTime;
      print(
          "idx=${row.index.toString().padLeft(3)} | angle=${row.avgAngle.toStringAsFixed(2).padLeft(7)} | emg=${row.avgEmg.toStringAsFixed(2).padLeft(8)} | t=${row.timeMs.toString().padLeft(5)}ms | dt0=${dtFromStart.toString().padLeft(4)}ms | dt=${dtFromPrev.toString().padLeft(3)}ms");
      prevTime = row.timeMs;
    }
    print(
        "carry -> idx=${carryToNextSegment.index.toString().padLeft(3)} | angle=${carryToNextSegment.avgAngle.toStringAsFixed(2).padLeft(7)} | emg=${carryToNextSegment.avgEmg.toStringAsFixed(2).padLeft(8)} | t=${carryToNextSegment.timeMs.toString().padLeft(5)}ms");
    print("---------------------------------------------------------");
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

    if (_pendingDirection == _MovementDirection.unknown) {
      if (_lastDirection != _MovementDirection.unknown &&
          newDirection != _lastDirection) {
        // First opposite sample: register a pivot candidate and require a
        // stable run of samples in the new direction before confirming turn.
        _pendingPivotAngle = _previousAvgAngle!;
        _pendingDirection = newDirection;
        _directionBeforePending = _lastDirection;
        _pendingDirectionWindow
          ..clear()
          ..add(newDirection);
        _previousAvgAngle = currentAvgAngle;
        return;
      }

      _lastDirection = newDirection;
      _previousAvgAngle = currentAvgAngle;
      return;
    }

    if (newDirection != _pendingDirection) {
      _resetPendingTurnCandidate();
      _lastDirection = newDirection;
      _previousAvgAngle = currentAvgAngle;
      return;
    }

    _pendingDirectionWindow.add(newDirection);
    if (_pendingDirectionWindow.length > _turnDirectionConfirmationSamples) {
      _pendingDirectionWindow.removeAt(0);
    }

    if (_pendingPivotAngle != null) {
      final movedInNewDirection = (currentAvgAngle - _pendingPivotAngle!).abs();
      if (_isPendingDirectionStable() &&
          movedInNewDirection >= _turnConfirmationDelta) {
        final extremumAngle = _pendingPivotAngle!;
        if (_directionBeforePending == _MovementDirection.up &&
            _pendingDirection == _MovementDirection.down) {
          _onLocalMaximum(extremumAngle);
        } else if (_directionBeforePending == _MovementDirection.down &&
            _pendingDirection == _MovementDirection.up) {
          _onLocalMinimum(extremumAngle);
        }

        _lastDirection = _pendingDirection;
        _resetPendingTurnCandidate();
      }
    }

    _previousAvgAngle = currentAvgAngle;
  }

  bool _isPendingDirectionStable() {
    if (_pendingDirectionWindow.length < _turnDirectionConfirmationSamples) {
      return false;
    }
    return _pendingDirectionWindow.every((d) => d == _pendingDirection);
  }

  void _resetPendingTurnCandidate() {
    _pendingPivotAngle = null;
    _pendingDirection = _MovementDirection.unknown;
    _directionBeforePending = _MovementDirection.unknown;
    _pendingDirectionWindow.clear();
  }

  void _onLocalMaximum(double angle) {
    appTalker.info("Локальный максимум: ${angle.toStringAsFixed(1)}°");
    _onExtremumDetected(_ExtremumType.maximum);
  }

  List<FinalSegment> _extractBoundaryShifts(_ExtremumType closingExtremum) {
    if (_currentRepTable.isEmpty) return const [];

    // While turn confirmation accumulates samples, trailing shifts of the
    // next half-cycle can already be appended to the current repetition.
    // Carry them to the next repetition based on the closing extremum.
    final carrySign = closingExtremum == _ExtremumType.maximum ? -1.0 : 1.0;
    int splitIndex = _currentRepTable.length;
    while (splitIndex > 0) {
      final row = _currentRepTable[splitIndex - 1];
      if (row.signedAngle * carrySign > 0) {
        splitIndex--;
        continue;
      }
      break;
    }

    if (splitIndex >= _currentRepTable.length) return const [];
    final carry = List<FinalSegment>.from(_currentRepTable.sublist(splitIndex));
    _currentRepTable.removeRange(splitIndex, _currentRepTable.length);
    return carry;
  }

  void _onLocalMinimum(double angle) {
    appTalker.info("Локальный минимум: ${angle.toStringAsFixed(1)}°");
    _onExtremumDetected(_ExtremumType.minimum);
  }

  void _onExtremumDetected(_ExtremumType currentExtremum) {
    if (_anchorExtremum == null) {
      _anchorExtremum = currentExtremum;
      _sawOppositeExtremumInCurrentRep = false;
      appTalker.info(
          "Установлен стартовый экстремум: ${currentExtremum == _ExtremumType.maximum ? "максимум" : "минимум"}");
      return;
    }

    if (currentExtremum != _anchorExtremum) {
      _sawOppositeExtremumInCurrentRep = true;
      return;
    }

    // Count repetition only when the cycle is closed:
    // anchor -> opposite -> anchor.
    if (!_sawOppositeExtremumInCurrentRep) return;

    if (_currentRepTable.isNotEmpty) {
      final carryForNextRep = _extractBoundaryShifts(currentExtremum);

      _repetitionTables.add(List<FinalSegment>.from(_currentRepTable));
      final repNumber = _repetitionTables.length;
      appTalker.info(
          "Экстремум #$repNumber подтверждён. Повтор #$repNumber сохранён (${_currentRepTable.length} строк)");
      _printRepetitionTable(repNumber, _currentRepTable);
      _currentRepTable.clear();

      if (carryForNextRep.isNotEmpty) {
        _currentRepTable.addAll(carryForNextRep);
      }
    }

    _completedReps = _repetitionTables.length;
    _sawOppositeExtremumInCurrentRep = false;

    if (_completedReps >= _targetReps) {
      appTalker.critical(
          "Достигнуто $_targetReps повторений, ожидание следующего EMG пакета");
      _awaitingTerminalEmgSample = true;
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

    appTalker.info(
        "Эталонная таблица сохранена: ${_referenceSegments.length} сегментов");
  }

  Future<void> _saveRepetitionTablesToStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final limitedTables = _repetitionTables.take(_targetReps).toList();

    final tablesJson = limitedTables
        .map((table) => table.map((row) => row.toJson()).toList())
        .toList();

    await prefs.setString(_repetitionTablesKey, jsonEncode(tablesJson));
    appTalker.info("Сохранено таблиц повторов: ${limitedTables.length}");
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
    appTalker.info("Фазовый эталон сохранён: ${_phasePhi.length} точек");
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
      appTalker
          .warning("ETALON STATUS: NOT FOUND. Running with empty reference.");
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

      appTalker.info(
          "ETALON DATA LOADED ON APP START. Total segments: ${_referenceSegments.length}");

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

      appTalker.info("ETALON DATA LOAD COMPLETED");
      _prepareReferenceMuscleStatus();

      // ОБНОВЛЯЕМ STATE
      emit(
        state.copyWith(
          minAngleBorder: minAngle,
          maxAngleBorder: maxAngle,
          referenceSegments: List.from(_referenceSegments),
          referenceMuscleStatus: List<int>.from(_referenceMuscleStatus),
          currentRepMuscleStatus: List<int>.from(_currentRepMuscleStatus),
          previousRepMuscleStatus: List<int>.from(_previousRepMuscleStatus),
          currentRepEffortPercent: 0.0,
        ),
      );
    } catch (e) {
      appTalker.error("ERROR LOADING ETALON", e);
    }
  }

  void _printSavedRepetitionTables(SharedPreferences prefs) {
    final rawTables = prefs.getString(_repetitionTablesKey);
    if (rawTables == null) {
      appTalker.warning("REPETITION TABLES STATUS: NOT FOUND");
      return;
    }

    try {
      final decoded = jsonDecode(rawTables) as List;
      appTalker.info(
          "SAVED REPETITION TABLES LOADED. Всего таблиц: ${decoded.length}");

      for (int i = 0; i < decoded.length; i++) {
        final tableRaw = decoded[i] as List;
        final tableRows = tableRaw
            .map((row) => FinalSegment.fromJson(row as Map<String, dynamic>))
            .toList();
        _printRepetitionTable(i + 1, tableRows);
      }
    } catch (e) {
      appTalker.error("ERROR LOADING REPETITION TABLES", e);
    }
  }

  void _printSavedPhaseProfile(SharedPreferences prefs) {
    final rawProfile = prefs.getString(_phaseProfileKey);
    if (rawProfile == null) {
      appTalker.warning("PHASE PROFILE STATUS: NOT FOUND");
      return;
    }

    try {
      final decoded = jsonDecode(rawProfile) as Map<String, dynamic>;
      final phi = (decoded['phi'] as List).map((e) => (e as num).toDouble());
      final theta =
          (decoded['theta'] as List).map((e) => (e as num).toDouble());
      final emg = (decoded['emg'] as List).map((e) => (e as num).toDouble());
      final time = (decoded['time'] as List).map((e) => (e as num).toDouble());

      appTalker.info("PHASE PROFILE LOADED");
      appTalker.info(
          "points: phi=${phi.length}, theta=${theta.length}, emg=${emg.length}, time=${time.length}");
      if (phi.isNotEmpty &&
          theta.isNotEmpty &&
          emg.isNotEmpty &&
          time.isNotEmpty) {
        dev.log(
          "sample[0]: phi=${phi.first}, theta=${theta.first}, emg=${emg.first}, time=${time.first}",
          name: 'BleBloc.PhaseProfile',
        );
        dev.log(
          "sample[last]: phi=${phi.last}, theta=${theta.last}, emg=${emg.last}, time=${time.last}",
          name: 'BleBloc.PhaseProfile',
        );
      }
      _printFinalReferenceArrays(
        phi: phi.toList(),
        theta: theta.toList(),
        emg: emg.toList(),
        time: time.toList(),
      );
      _phasePhi = phi.toList();
      _phaseTheta = theta.toList();
      _phaseEmg = emg.toList();
      _phaseTime = time.toList();
      appTalker.info("PHASE PROFILE LOAD COMPLETED");
    } catch (e) {
      appTalker.error("ERROR LOADING PHASE PROFILE", e);
    }
  }

  void _printFinalReferenceArrays({
    required List<double> phi,
    required List<double> theta,
    required List<double> emg,
    required List<double> time,
  }) {
    dev.log("phi=[${phi.join(', ')}]", name: 'BleBloc.ReferenceArrays');
    dev.log("theta=[${theta.join(', ')}]", name: 'BleBloc.ReferenceArrays');
    dev.log("emg=[${emg.join(', ')}]", name: 'BleBloc.ReferenceArrays');
    dev.log("time=[${time.join(', ')}]", name: 'BleBloc.ReferenceArrays');
  }

  // ==================== COMPARISON MODE ====================

  Future<void> _onStartComparison(
    BleStartComparison event,
    Emitter<BleState> emit,
  ) async {
    if (_referenceSegments.isEmpty) {
      appTalker.warning("Cannot start comparison: no reference data");
      return;
    }

    _prepareReferenceMuscleStatus();
    _resetRuntimeComparisonTracking();

    _isComparing = true;
    _comparisonStartTime = DateTime.now();
    _comparisonTimer?.cancel();
    _comparisonTimer = Timer.periodic(
        const Duration(milliseconds: _inPacketSampleSpacingMs), (_) {
      if (_isComparing && _comparisonStartTime != null) {
        add(BleResetComparison());
      }
    });

    emit(state.copyWith(
      isComparing: true,
      elapsedTimeMs: 0,
      currentReferenceAngle: 0.0,
      angleDifference: 0.0,
      referenceMuscleStatus: List<int>.from(_referenceMuscleStatus),
      currentRepMuscleStatus: List<int>.from(_currentRepMuscleStatus),
      previousRepMuscleStatus: List<int>.from(_previousRepMuscleStatus),
      currentRepEffortPercent: _currentRepEffortPercent,
      emgNoise: _emgNoise,
    ));
  }

  Future<void> _onPauseComparison(
    BlePauseComparison event,
    Emitter<BleState> emit,
  ) async {
    _isComparing = false;
    _comparisonTimer?.cancel();
    _resetRuntimeComparisonTracking();

    emit(state.copyWith(
      isComparing: false,
      currentRepMuscleStatus: List<int>.from(_currentRepMuscleStatus),
      previousRepMuscleStatus: List<int>.from(_previousRepMuscleStatus),
      currentRepEffortPercent: _currentRepEffortPercent,
    ));
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

    final totalDurationMs =
        _referenceSegments.fold<int>(0, (sum, seg) => sum + seg.timeMs);
    if (totalDurationMs <= 0) return _referenceSegments.last.avgAngle;

    // Loop reference trajectory by time.
    final loopedElapsed = elapsedMs % totalDurationMs;

    int cumulativeTime = 0;

    for (int i = 0; i < _referenceSegments.length; i++) {
      final segment = _referenceSegments[i];
      cumulativeTime += segment.timeMs;

      if (loopedElapsed <= cumulativeTime) {
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
    appTalker.info("Запуск потока данных");
    _acceptIncomingData = true;
    await _bleService.resumeDataStream();
    // _testDataGenerator.start();
  }

  Future<void> _onStopDataStream(
    BleStopDataStream event,
    Emitter<BleState> emit,
  ) async {
    appTalker.info("Остановка потока данных");
    _acceptIncomingData = false;
    _emgMedianWindow.clear();
    _emgEmaValue = null;
    _resetRuntimeComparisonTracking();
    _bleService.pauseDataStream();
    // _testDataGenerator.stop();
  }

  Future<void> _onUpdateAngleBorders(
    BleUpdateAngleBorders event,
    Emitter<BleState> emit,
  ) async {
    appTalker.info(
        "Обновление границ углов: ${event.minAngle}° - ${event.maxAngle}°");
    _minAngle = event.minAngle;
    _maxAngle = event.maxAngle;
    emit(state.copyWith(
      minAngleBorder: event.minAngle,
      maxAngleBorder: event.maxAngle,
    ));
    unawaited(
      _saveAngleBordersToStorage(event.minAngle, event.maxAngle),
    );
  }

  Future<void> _saveAngleBordersToStorage(int minAngle, int maxAngle) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt("min_angle_border", minAngle);
    await prefs.setInt("max_angle_border", maxAngle);
  }

  @override
  Future<void> close() async {
    _comparisonTimer?.cancel();
    _baselinePhaseTimer?.cancel();
    _baselineTimer?.cancel();
    _bleService.dispose();
    // _testDataGenerator.dispose();
    return super.close();
  }
}
