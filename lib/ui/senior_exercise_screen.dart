import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../blocs/ble/ble_bloc.dart';
import '../blocs/ble/ble_event.dart';
import '../blocs/ble/ble_state.dart';
import '../themes/theme_extensions.dart';

class SeniorExerciseScreen extends StatefulWidget {
  const SeniorExerciseScreen({super.key});

  @override
  State<SeniorExerciseScreen> createState() => _SeniorExerciseScreenState();
}

class _SeniorExerciseScreenState extends State<SeniorExerciseScreen> {
  static const double _nearRangeDeg = 5.0;
  static const Duration _nearBoundaryCooldown = Duration(milliseconds: 220);
  static const Duration _outsideCooldown = Duration(milliseconds: 140);
  static const Duration _streamWarmupDelay = Duration(milliseconds: 700);
  static const String _boundarySoundAsset = 'sounds/boundary_beep.mp3';
  static const String _outsideSoundAsset = 'sounds/outside_beep.mp3';

  late final AudioPlayer _boundaryPlayer;
  late final AudioPlayer _outsidePlayer;
  late final TextEditingController _minController;
  late final TextEditingController _maxController;

  final _formKey = GlobalKey<FormState>();

  DateTime? _lastNearBoundaryBeepAt;
  DateTime? _lastOutsideBeepAt;
  BleBloc? _bleBloc;
  bool _isBusy = false;
  bool _isConfigured = false;
  int? _referenceMin;
  int? _referenceMax;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bleBloc ??= context.read<BleBloc>();
  }

  @override
  void initState() {
    super.initState();
    _boundaryPlayer = AudioPlayer(playerId: 'senior-boundary-beep');
    _outsidePlayer = AudioPlayer(playerId: 'senior-outside-beep');
    _boundaryPlayer.setPlayerMode(PlayerMode.lowLatency);
    _outsidePlayer.setPlayerMode(PlayerMode.lowLatency);
    _boundaryPlayer.setReleaseMode(ReleaseMode.stop);
    _outsidePlayer.setReleaseMode(ReleaseMode.stop);

    _minController = TextEditingController();
    _maxController = TextEditingController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _initializeSetupState();
    });
  }

  @override
  void dispose() {
    _bleBloc?.add(BlePauseComparison());
    _bleBloc?.add(BleStopDataStream());
    _minController.dispose();
    _maxController.dispose();
    _boundaryPlayer.dispose();
    _outsidePlayer.dispose();
    super.dispose();
  }

  void _initializeSetupState() {
    final bloc = context.read<BleBloc>();
    final state = bloc.state;

    bloc.add(BlePauseComparison());
    bloc.add(BleStopDataStream());

    _minController.text = state.minAngleBorder.toString();
    _maxController.text = state.maxAngleBorder.toString();

    if (state.referenceSegments.isNotEmpty) {
      final angles =
          state.referenceSegments.map((segment) => segment.avgAngle).toList();
      _referenceMin = angles.reduce((a, b) => a < b ? a : b).round();
      _referenceMax = angles.reduce((a, b) => a > b ? a : b).round();
    }
  }

  void _onApplyRange() {
    if (!_formKey.currentState!.validate()) return;
    final bloc = context.read<BleBloc>();
    bloc.add(
      BleUpdateAngleBorders(
        minAngle: int.parse(_minController.text),
        maxAngle: int.parse(_maxController.text),
      ),
    );
    _lastNearBoundaryBeepAt = null;
    _lastOutsideBeepAt = null;
    setState(() {
      _isConfigured = true;
    });
  }

  Future<void> _onStartStopPressed(BleState state) async {
    if (_isBusy) return;
    final bloc = context.read<BleBloc>();

    if (state.isComparing) {
      bloc.add(BlePauseComparison());
      bloc.add(BleStopDataStream());
      return;
    }

    setState(() => _isBusy = true);
    bloc.add(BleStartDataStream());
    await Future<void>.delayed(_streamWarmupDelay);
    if (!mounted) return;
    bloc.add(BleStartComparison());
    if (mounted) {
      setState(() => _isBusy = false);
    }
  }

  Future<void> _playBoundaryBeep() async {
    await _boundaryPlayer.stop();
    await _boundaryPlayer.play(AssetSource(_boundarySoundAsset), volume: 1.0);
  }

  Future<void> _playOutsideBeep() async {
    await _outsidePlayer.stop();
    await _outsidePlayer.play(AssetSource(_outsideSoundAsset), volume: 1.0);
  }

  double _distanceFromRange({
    required double angle,
    required double minAngle,
    required double maxAngle,
  }) {
    if (angle < minAngle) return minAngle - angle;
    if (angle > maxAngle) return angle - maxAngle;
    return 0.0;
  }

  void _handleAudioAlerts(BleState state) {
    if (!state.isComparing || state.values.isEmpty) return;

    final currentAngle = state.values.last;
    final distance = _distanceFromRange(
      angle: currentAngle,
      minAngle: state.minAngleBorder.toDouble(),
      maxAngle: state.maxAngleBorder.toDouble(),
    );
    if (distance <= 0) return;

    final now = DateTime.now();
    if (distance <= _nearRangeDeg) {
      final canPlay = _lastNearBoundaryBeepAt == null ||
          now.difference(_lastNearBoundaryBeepAt!) >= _nearBoundaryCooldown;
      if (canPlay) {
        _lastNearBoundaryBeepAt = now;
        _playBoundaryBeep();
      }
      return;
    }

    final canPlay = _lastOutsideBeepAt == null ||
        now.difference(_lastOutsideBeepAt!) >= _outsideCooldown;
    if (canPlay) {
      _lastOutsideBeepAt = now;
      _playOutsideBeep();
    }
  }

  Widget _buildSetupView(AppThemeExtension themeExt) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Упражнение в ограниченном угле',
                      style: TextStyle(
                        color: themeExt.textPrimaryColor,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('Настройте диапазон перед началом упражнения.'),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _minController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Минимальный угол (°)',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty)
                          return 'Введите минимум';
                        final parsed = int.tryParse(value);
                        if (parsed == null || parsed < 0 || parsed > 180) {
                          return 'Диапазон: 0..180';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _maxController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Максимальный угол (°)',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty)
                          return 'Введите максимум';
                        final maxValue = int.tryParse(value);
                        if (maxValue == null ||
                            maxValue < 0 ||
                            maxValue > 180) {
                          return 'Диапазон: 0..180';
                        }
                        final minValue = int.tryParse(_minController.text);
                        if (minValue != null && maxValue <= minValue) {
                          return 'Максимум должен быть больше минимума';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: (_referenceMin != null &&
                              _referenceMax != null)
                          ? () {
                              _minController.text = _referenceMin!.toString();
                              _maxController.text = _referenceMax!.toString();
                            }
                          : null,
                      icon: const Icon(Icons.auto_fix_high),
                      label: Text(
                        (_referenceMin != null && _referenceMax != null)
                            ? 'Подставить минимум/максимум из эталона'
                            : 'Эталон не найден',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Отмена'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _onApplyRange,
                          child: const Text('Применить'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeExt = Theme.of(context).extension<AppThemeExtension>()!;
    final gradient = themeExt.backgroundGradient;

    return Container(
      decoration: BoxDecoration(gradient: gradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(
            'Упражнение в ограниченном угле',
            style: TextStyle(color: themeExt.textPrimaryColor),
          ),
          centerTitle: true,
        ),
        body: BlocListener<BleBloc, BleState>(
          listener: (context, state) => _handleAudioAlerts(state),
          child: BlocBuilder<BleBloc, BleState>(
            builder: (context, state) {
              if (!_isConfigured) {
                return _buildSetupView(themeExt);
              }

              final currentAngle =
                  state.values.isNotEmpty ? state.values.last : 0.0;
              final hasReference = state.referenceSegments.isNotEmpty;
              final distance = _distanceFromRange(
                angle: currentAngle,
                minAngle: state.minAngleBorder.toDouble(),
                maxAngle: state.maxAngleBorder.toDouble(),
              );
              final isInsideRange =
                  state.isComparing && hasReference && distance <= 0;
              final ringColor = !state.isComparing
                  ? themeExt.textSecondaryColor
                  : (isInsideRange ? Colors.green : Colors.red);

              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    RepaintBoundary(
                      child: Container(
                        width: 300,
                        height: 300,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: ringColor,
                          boxShadow: [
                            BoxShadow(
                              color: ringColor.withOpacity(0.22),
                              blurRadius: 16,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Диапазон: ${state.minAngleBorder}° - ${state.maxAngleBorder}°',
                      style: TextStyle(color: themeExt.textPrimaryColor),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: (!hasReference || _isBusy)
                          ? null
                          : () => _onStartStopPressed(state),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(240, 64),
                        textStyle: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      child: Text(
                        _isBusy
                            ? 'Подготовка...'
                            : (state.isComparing ? 'Стоп' : 'Начать'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
