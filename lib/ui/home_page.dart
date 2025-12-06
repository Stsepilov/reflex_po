import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:reflex_po/ui/pulse_chart.dart';

import '../themes/app_theme.dart';
import '../themes/theme_extensions.dart';

import '../blocs/ble/ble_bloc.dart';
import '../blocs/ble/ble_event.dart';
import '../blocs/ble/ble_state.dart';
import '../widgets/angle_indicator.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final gradient =
        Theme.of(context).extension<AppThemeExtension>()!.backgroundGradient;

    return Container(
        decoration: BoxDecoration(
          gradient: gradient,
        ),
        child: Scaffold(
          backgroundColor: Colors.transparent,

          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: const Text("Reflex", style: TextStyle(color: Colors.white),),
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
                    icon: Icon(icon, color: Colors.white,),
                    onPressed: () {
                      context.read<BleBloc>().add(BleRestartScan());
                    },
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.list, color: Colors.white,),
                onPressed: () {
                  context.read<BleBloc>().printReference();
                },
              ),
            ],
          ),

          body: BlocBuilder<BleBloc, BleState>(
            builder: (context, state) {
              final values = state.values;
              double sum = 0;
              for (var el in values) {
                sum += el;
              }
              final currentAngle = values.isNotEmpty ? sum / values.length : 0.0;

              print("UI sees ${state.referenceSegments.length} reference segments");
              final reference = state.referenceSegments;

              int segmentIndex = 0;
              double referenceAngle = 0;

              if (reference.isNotEmpty) {
                // вычисляем нужный сегмент
                segmentIndex = (currentAngle ~/ 5);

                // clamp требует min <= max, иначе ошибка
                segmentIndex = segmentIndex.clamp(
                  0,
                  reference.length - 1,
                );

                referenceAngle = segmentIndex * 5;
              }

              return Column(
                children: [
                  PulseChart(values: values), // верхняя половина экрана
                  const SizedBox(height: 20),

                  // 🔥 индикатор угла
                  AngleIndicator(
                    currentAngle: currentAngle,
                    referenceAngle: referenceAngle,
                  ),
                ],
              );
            },
          ),

          floatingActionButton: BlocBuilder<BleBloc, BleState>(
            builder: (context, state) {
              final isRecording = state.isRecordingReference;

              return FloatingActionButton(
                backgroundColor: isRecording ? Colors.red : Colors.green,
                child: Icon(
                  isRecording ? Icons.stop : Icons.fiber_manual_record,
                ),
                onPressed: () {
                  if (isRecording) {
                    context
                        .read<BleBloc>()
                        .add(BleStopReferenceRecording());
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Эталон сохранён")),
                    );
                  } else {
                    context
                        .read<BleBloc>()
                        .add(BleStartReferenceRecording());
                  }
                },
              );
            },
          ),
          floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        ),
      );
  }
}
