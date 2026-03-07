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
        Future.delayed(const Duration(seconds: 3), () {
          if (Navigator.of(dialogContext).canPop()) {
            Navigator.of(dialogContext).pop();
          }
        });
        return AlertDialog(
          title: const Text('Калибровка EMG'),
          content: const Text('Пожалуйста, держите руку в покое 3 секунды.'),
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
