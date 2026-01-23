import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:reflex_po/ui/pulse_chart.dart';

import '../themes/theme_extensions.dart';

import '../blocs/ble/ble_bloc.dart';
import '../blocs/ble/ble_event.dart';
import '../blocs/ble/ble_state.dart';
import '../widgets/angle_indicator.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  Widget _buildComparisonInfo(BleState state, AppThemeExtension themeExt) {
    final seconds = (state.elapsedTimeMs / 1000).toStringAsFixed(1);
    final currentAngle = state.values.isNotEmpty ? state.values.last : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildInfoCard(
            'Время',
            '${seconds}s',
            themeExt,
          ),
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

  Widget _buildReferenceButton(
    BuildContext context,
    BleState state,
    AppThemeExtension themeExt,
  ) {
    final isRecording = state.isRecordingReference;
    final hasReference = state.referenceSegments.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        children: [
          // Кнопка записи
          ElevatedButton(
            onPressed: state.status == BleConnectionStatus.connected
                ? () {
                    if (isRecording) {
                      context.read<BleBloc>().add(BleStopReferenceRecording());
                    } else {
                      context.read<BleBloc>().add(BleStartReferenceRecording());
                    }
                  }
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  isRecording ? themeExt.accentColor : themeExt.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 3,
              disabledBackgroundColor:
                  themeExt.textSecondaryColor.withOpacity(0.3),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isRecording ? Icons.stop_circle : Icons.fiber_manual_record,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Text(
                  isRecording ? 'Остановить запись' : 'Записать эталон',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Индикатор состояния
          if (isRecording && !state.isComparing)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: themeExt.accentColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        themeExt.accentColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Идёт запись эталона...',
                    style: TextStyle(
                      color: themeExt.textPrimaryColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
          else if (hasReference && !state.isComparing)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: themeExt.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle,
                    color: themeExt.primaryColor,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Эталон загружен (${state.referenceSegments.length} сегментов)',
                    style: TextStyle(
                      color: themeExt.textPrimaryColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
          else
            Text(
              'Нет сохранённого эталона',
              style: TextStyle(
                color: themeExt.textSecondaryColor,
                fontSize: 12,
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
          leading: BlocBuilder<BleBloc, BleState>(
            builder: (context, state) {
              final hasReference = state.referenceSegments.isNotEmpty;
              final isComparing = state.isComparing;

              if (!hasReference) {
                return const SizedBox.shrink();
              }

              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      isComparing ? Icons.pause : Icons.play_arrow,
                      color: themeExt.primaryColor,
                    ),
                    onPressed: state.status == BleConnectionStatus.connected
                        ? () {
                            if (isComparing) {
                              context.read<BleBloc>().add(BlePauseComparison());
                            } else {
                              context.read<BleBloc>().add(BleStartComparison());
                            }
                          }
                        : null,
                  ),
                ],
              );
            },
          ),
          title: Text(
            "Reflex",
            style: TextStyle(color: themeExt.textPrimaryColor),
          ),
          centerTitle: true,
          actions: [
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
                PulseChart(values: emgValues),

                const SizedBox(height: 5),

                // Индикатор углов
                AngleIndicator(
                  currentAngle: angle,
                  referenceAngle: state.currentReferenceAngle,
                  showReference: state.isComparing,
                ),

                const SizedBox(height: 5),

                // Информация о сравнении
                if (state.isComparing) _buildComparisonInfo(state, themeExt),

                if (state.isComparing) const SizedBox(height: 5),

                // Кнопка записи эталона
                _buildReferenceButton(context, state, themeExt),

                const SizedBox(height: 8),
              ],
            );
          },
        ),
      ),
    );
  }
}
