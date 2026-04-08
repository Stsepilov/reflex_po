import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:reflex_po/ui/pulse_chart.dart';

import '../themes/theme_extensions.dart';

import '../blocs/ble/ble_bloc.dart';
import '../blocs/ble/ble_event.dart';
import '../blocs/ble/ble_state.dart';
import '../widgets/angle_indicator.dart';

class ExerciseScreen extends StatefulWidget {
  const ExerciseScreen({super.key});

  @override
  State<ExerciseScreen> createState() => _ExerciseScreenState();
}

class _ExerciseScreenState extends State<ExerciseScreen> {
  BleBloc? _bleBloc;
  bool _isBaselineDialogActive = false;
  bool _showEmgComparison = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Сохраняем ссылку на BleBloc для безопасного использования в dispose
    _bleBloc ??= context.read<BleBloc>();
  }

  @override
  void initState() {
    super.initState();
    // Запускаем поток данных при входе на экран
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      context.read<BleBloc>().add(BleStartDataStream());
      await _runBaselineCalibrationDialog();
    });
  }

  Future<void> _runBaselineCalibrationDialog() async {
    if (!mounted || _isBaselineDialogActive) return;
    _isBaselineDialogActive = true;
    context.read<BleBloc>().add(BleStartBaselineCalibration());

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        Future.delayed(const Duration(seconds: 4), () {
          if (Navigator.of(dialogContext).canPop()) {
            Navigator.of(dialogContext).pop();
          }
        });
        return AlertDialog(
          title: const Text('Калибровка EMG'),
          content: const Text(
            'Пожалуйста, держите руку в покое 4 секунды.\n'
            'Первые 2 секунды: baseline, следующие 2 секунды: оценка шума.',
          ),
        );
      },
    );

    _isBaselineDialogActive = false;
  }

  @override
  void dispose() {
    // Останавливаем поток данных при выходе с экрана
    _bleBloc?.add(BleStopDataStream());
    super.dispose();
  }

  Widget _buildComparisonInfo(BleState state, AppThemeExtension themeExt) {
    final currentAngle = state.values.isNotEmpty ? state.values.last : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildInfoCard(
            'Текущий',
            '${currentAngle.toStringAsFixed(1)}°',
            themeExt,
          ),
          _buildInfoCard(
            'Эталон',
            '${state.currentReferenceAngle.toStringAsFixed(1)}°',
            themeExt,
          ),
          _buildInfoCard(
            'Разница',
            '${state.angleDifference.toStringAsFixed(1)}°',
            themeExt,
            isError: state.angleDifference > 10,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(
    String label,
    String value,
    AppThemeExtension themeExt, {
    bool isError = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: isError
            ? themeExt.accentColor.withOpacity(0.1)
            : themeExt.primaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: themeExt.textSecondaryColor,
              fontSize: 9,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            value,
            style: TextStyle(
              color: isError ? themeExt.accentColor : themeExt.primaryColor,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmgStatusRow({
    required String label,
    required List<int> statuses,
    required AppThemeExtension themeExt,
    String? trailingText,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 58,
            child: Text(
              label,
              style: TextStyle(
                color: themeExt.textSecondaryColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                border: Border.all(
                    color: themeExt.textSecondaryColor.withOpacity(0.18)),
                borderRadius: BorderRadius.circular(8),
                color: Colors.white.withOpacity(0.6),
              ),
              clipBehavior: Clip.antiAlias,
              child: _EmgStatusStrip(
                statuses: statuses,
                activeColor: Colors.green.shade300,
                inactiveColor: Colors.red.shade200,
                unknownColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 78,
            child: Text(
              trailingText ?? '',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: themeExt.textPrimaryColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmgComparisonPanel(BleState state, AppThemeExtension themeExt) {
    final referenceStatus = state.referenceMuscleStatus;
    final currentStatus = state.currentRepMuscleStatus;
    final previousStatus = state.previousRepMuscleStatus;
    final effortPercent = state.currentRepEffortPercent;

    if (referenceStatus.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'Для сравнения EMG сначала запишите эталон.',
          style: TextStyle(color: themeExt.textSecondaryColor),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        children: [
          _buildEmgStatusRow(
            label: 'Эталон',
            statuses: referenceStatus,
            themeExt: themeExt,
          ),
          _buildEmgStatusRow(
            label: 'Текущее',
            statuses: currentStatus,
            themeExt: themeExt,
            trailingText: '${effortPercent.toStringAsFixed(0)}%',
          ),
          _buildEmgStatusRow(
            label: 'Прошлый',
            statuses: previousStatus,
            themeExt: themeExt,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 16),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Усилие = EMG / max EMG эталона',
                style: TextStyle(
                  color: themeExt.textSecondaryColor,
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ],
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
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back,
              color: themeExt.primaryColor,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
          leadingWidth: 56,
          title: Text(
            "Упражнение",
            style: TextStyle(color: themeExt.textPrimaryColor),
          ),
          centerTitle: true,
          actions: [
            // Play/Pause button (only shown when reference exists)
            BlocBuilder<BleBloc, BleState>(
              builder: (context, state) {
                final hasReference = state.referenceSegments.isNotEmpty;
                final isComparing = state.isComparing;

                if (hasReference) {
                  return IconButton(
                    icon: Icon(
                      isComparing ? Icons.pause : Icons.play_arrow,
                      color: themeExt.primaryColor,
                    ),
                    onPressed: state.status == BleConnectionStatus.connected
                        ? () async {
                            if (isComparing) {
                              context.read<BleBloc>().add(BlePauseComparison());
                            } else {
                              await _runBaselineCalibrationDialog();
                              if (!context.mounted) return;
                              context.read<BleBloc>().add(BleStartComparison());
                            }
                          }
                        : null,
                  );
                }
                return const SizedBox.shrink();
              },
            ),
            // Bluetooth button
            BlocBuilder<BleBloc, BleState>(
              builder: (context, state) {
                IconData icon;
                switch (state.status) {
                  case BleConnectionStatus.connected:
                    icon = Icons.bluetooth_connected;
                    break;
                  case BleConnectionStatus.scanning:
                    icon = Icons.bluetooth_searching;
                    break;
                  case BleConnectionStatus.connecting:
                    icon = Icons.bluetooth;
                    break;
                  case BleConnectionStatus.disconnected:
                  default:
                    icon = Icons.bluetooth_disabled;
                }

                return IconButton(
                  icon: Icon(icon, color: themeExt.primaryColor),
                  onPressed: () {
                    context.read<BleBloc>().add(BleRestartScan());
                  },
                );
              },
            ),
          ],
        ),
        body: BlocBuilder<BleBloc, BleState>(
          builder: (context, state) {
            final angleValues = state.values;
            final emgValues = state.emgValues;

            // Среднее за пакет
            double angle = angleValues.isNotEmpty ? angleValues.last : 0.0;

            return Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: SwitchListTile(
                          dense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 8),
                          title: const Text('Сравнение EMG'),
                          value: _showEmgComparison,
                          onChanged: (value) {
                            setState(() => _showEmgComparison = value);
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                if (_showEmgComparison)
                  _buildEmgComparisonPanel(state, themeExt)
                else
                  PulseChart(
                    values: emgValues,
                    xStart: state.emgStartX,
                  ),

                const SizedBox(height: 5),

                // Индикатор углов с плавной интерполяцией между тиками данных
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: angle),
                  duration: const Duration(milliseconds: 10),
                  curve: Curves.linear,
                  builder: (context, animatedAngle, child) {
                    return AngleIndicator(
                      currentAngle: animatedAngle,
                      referenceAngle: state.currentReferenceAngle,
                      showReference: state.isComparing,
                    );
                  },
                ),

                const SizedBox(height: 5),

                // Информация о сравнении
                if (state.isComparing) _buildComparisonInfo(state, themeExt),

                if (state.isComparing) const SizedBox(height: 5),

                const SizedBox(height: 8),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EmgStatusStrip extends StatelessWidget {
  final List<int> statuses;
  final Color activeColor;
  final Color inactiveColor;
  final Color unknownColor;

  const _EmgStatusStrip({
    required this.statuses,
    required this.activeColor,
    required this.inactiveColor,
    required this.unknownColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      width: double.infinity,
      child: CustomPaint(
        painter: _EmgStatusStripPainter(
          statuses: statuses,
          activeColor: activeColor,
          inactiveColor: inactiveColor,
          unknownColor: unknownColor,
        ),
      ),
    );
  }
}

class _EmgStatusStripPainter extends CustomPainter {
  final List<int> statuses;
  final Color activeColor;
  final Color inactiveColor;
  final Color unknownColor;

  _EmgStatusStripPainter({
    required this.statuses,
    required this.activeColor,
    required this.inactiveColor,
    required this.unknownColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (statuses.isEmpty) {
      final p = Paint()..color = unknownColor;
      canvas.drawRect(Offset.zero & size, p);
      return;
    }

    final widthPx = size.width.floor().clamp(1, 1000000);
    final rawValues = List<double?>.filled(widthPx, null);

    double? valueAt(int index) {
      if (index < 0 || index >= statuses.length) return null;
      final status = statuses[index];
      if (status < 0) return null;
      return status == 1 ? 1.0 : 0.0;
    }

    for (int x = 0; x < widthPx; x++) {
      final t = widthPx == 1 ? 0.0 : x / (widthPx - 1);
      final position = t * (statuses.length - 1);
      final left = position.floor();
      final right = position.ceil();
      final frac = position - left;
      final leftValue = valueAt(left);
      final rightValue = valueAt(right);

      if (leftValue == null && rightValue == null) {
        rawValues[x] = null;
      } else if (leftValue == null) {
        rawValues[x] = rightValue;
      } else if (rightValue == null) {
        rawValues[x] = leftValue;
      } else {
        rawValues[x] = leftValue + (rightValue - leftValue) * frac;
      }
    }

    // Small spatial smoothing removes hard rectangular borders.
    final smoothedValues = List<double?>.filled(widthPx, null);
    const smoothRadius = 3;
    for (int x = 0; x < widthPx; x++) {
      double sum = 0.0;
      int count = 0;
      for (int k = -smoothRadius; k <= smoothRadius; k++) {
        final idx = x + k;
        if (idx < 0 || idx >= widthPx) continue;
        final v = rawValues[idx];
        if (v == null) continue;
        sum += v;
        count++;
      }
      smoothedValues[x] = count == 0 ? null : sum / count;
    }

    final paint = Paint()..isAntiAlias = true;
    for (int x = 0; x < widthPx; x++) {
      final v = smoothedValues[x];
      paint.color = v == null
          ? unknownColor
          : Color.lerp(inactiveColor, activeColor, v.clamp(0.0, 1.0))!;
      canvas.drawRect(Rect.fromLTWH(x.toDouble(), 0, 1.2, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _EmgStatusStripPainter oldDelegate) {
    return oldDelegate.statuses != statuses ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.unknownColor != unknownColor;
  }
}
