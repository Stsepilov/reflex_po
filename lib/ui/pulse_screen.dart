import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/ble/ble_bloc.dart';
import '../../blocs/ble/ble_event.dart';
import '../../blocs/ble/ble_state.dart';
import 'pulse_chart.dart';

class PulseScreen extends StatelessWidget {
  const PulseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => BleBloc()..add(BleStartScan()),
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text("Pulse Monitor"),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                context.read<BleBloc>().add(BleRestartScan());
              },
            )
          ],
        ),
        body: BlocBuilder<BleBloc, BleState>(
          builder: (context, state) {
            return PulseChart(values: state.values);
          },
        ),
      ),
    );
  }
}
