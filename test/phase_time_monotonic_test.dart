import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:reflex_po/blocs/ble/ble_bloc.dart';
import 'package:reflex_po/blocs/ble/ble_event.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'phase time profile has 101 strictly increasing points',
    () async {
    SharedPreferences.setMockInitialValues({});
    final bloc = BleBloc();
    final random = Random(42);

    await Future<void>.delayed(const Duration(milliseconds: 50));
    bloc.add(BleStartReferenceRecording(minAngle: 0, maxAngle: 140));

    for (final angle in _buildInterpolatedSamples(repetitions: 12)) {
      bloc.add(BleNewDataReceived(
        angleValues: [angle, angle],
        emgValues: const [4200, 4300, 4400],
      ));
      final jitterMs = 50 + random.nextInt(11); // 50..60 ms
      await Future<void>.delayed(Duration(milliseconds: jitterMs));
    }

    await Future<void>.delayed(const Duration(milliseconds: 1000));

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('reference_phase_profile');
    expect(raw, isNotNull);

    final decoded = jsonDecode(raw!) as Map<String, dynamic>;
    final time = (decoded['time'] as List).map((e) => (e as num).toDouble()).toList();
    expect(time.length, 101);

    for (int i = 1; i < time.length; i++) {
      expect(time[i] > time[i - 1], isTrue);
    }

      await bloc.close();
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

List<double> _buildInterpolatedSamples({required int repetitions}) {
  const maxAngle = 140.0;
  const minAngle = 0.0;
  const step = 5.0;
  const perSegment = 3;

  final oneRep = <double>[];
  double segmentStart = maxAngle;
  bool movingDown = true;

  while (true) {
    final segmentEnd = movingDown ? segmentStart - step : segmentStart + step;
    final clampedEnd = segmentEnd.clamp(minAngle, maxAngle).toDouble();

    for (int i = 0; i < perSegment; i++) {
      final t = i / (perSegment - 1);
      oneRep.add(segmentStart + (clampedEnd - segmentStart) * t);
    }

    segmentStart = clampedEnd;
    if (segmentStart <= minAngle) {
      movingDown = false;
    } else if (segmentStart >= maxAngle) {
      break;
    }
  }

  final all = <double>[];
  for (int r = 0; r < repetitions; r++) {
    all.addAll(oneRep);
  }
  return all;
}
