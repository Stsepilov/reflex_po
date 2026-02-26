import 'dart:async';
import 'dart:math';

/// Генератор тестовых данных для EMG и угла
/// Используется для тестирования UI без физического устройства
class TestDataGenerator {
  Timer? _timer;
  final Random _random = Random();
  int _simulatedTimeMs = 0;
  double _currentAngle = 140.0;
  bool _movingDown = true;
  int _packetIndexInSegment = 0;
  double _segmentStartAngle = 140.0;
  double _segmentEndAngle = 135.0;

  static const double _maxAngle = 140.0;
  static const double _minAngle = 0.0;
  static const double _angleStepPerTick = 5.0;
  static const int _tickMs = 50;
  static const int _packetsPerSegment = 3;
  
  final Function({
    required List<double> angleValues,
    required List<double> emgValues,
  }) onNewData;
  final void Function(String packet)? onRawPacket;

  TestDataGenerator({
    required this.onNewData,
    this.onRawPacket,
  });

  /// Начать генерацию тестовых данных
  void start() {
    _timer?.cancel();
    _simulatedTimeMs = 0;
    _currentAngle = _maxAngle;
    _movingDown = true;
    _packetIndexInSegment = 0;
    _segmentStartAngle = _maxAngle;
    _segmentEndAngle = _maxAngle - _angleStepPerTick;
    
    // Генерируем данные каждые 50ms
    _timer = Timer.periodic(const Duration(milliseconds: _tickMs), (_) {
      _generateTestPacket();
    });
    
    print("🧪 Генератор тестовых данных запущен");
  }

  /// Остановить генерацию
  void stop() {
    _timer?.cancel();
    _timer = null;
    print("🧪 Генератор тестовых данных остановлен");
  }

  /// Генерировать один пакет тестовых данных
  void _generateTestPacket() {
    _updateInterpolatedAngle();

    // 2 угла, как у BLE: второй с небольшим шумом
    final angle1 = _currentAngle;
    final angle2 = (_currentAngle + (_random.nextDouble() * 2 - 1))
        .clamp(_minAngle, _maxAngle)
        .toDouble();
    final angleValues = [angle1, angle2];

    // 3 EMG-канала по условию
    final emgValues = [
      _generateEMG(),
      _generateEMG(),
      _generateEMG(),
    ];

    final packet = _buildBleLikePacket(
      angleValues: angleValues,
      emgValues: emgValues,
      timeMs: _simulatedTimeMs,
    );
    onRawPacket?.call(packet);

    onNewData(angleValues: angleValues, emgValues: emgValues);
    _simulatedTimeMs += _tickMs;
    _advanceSegmentCursor();
  }

  void _updateInterpolatedAngle() {
    final fraction = _packetIndexInSegment / (_packetsPerSegment - 1);
    _currentAngle =
        _segmentStartAngle + (_segmentEndAngle - _segmentStartAngle) * fraction;
  }

  void _advanceSegmentCursor() {
    _packetIndexInSegment++;
    if (_packetIndexInSegment < _packetsPerSegment) return;

    _packetIndexInSegment = 0;
    _segmentStartAngle = _segmentEndAngle;
    _updateDirectionByBounds();

    final nextEnd = _movingDown
        ? _segmentStartAngle - _angleStepPerTick
        : _segmentStartAngle + _angleStepPerTick;
    _segmentEndAngle = nextEnd.clamp(_minAngle, _maxAngle).toDouble();
  }

  void _updateDirectionByBounds() {
    if (_segmentStartAngle <= _minAngle) {
      _movingDown = false;
    } else if (_segmentStartAngle >= _maxAngle) {
      _movingDown = true;
    }
  }

  String _buildBleLikePacket({
    required List<double> angleValues,
    required List<double> emgValues,
    required int timeMs,
  }) {
    final angles = angleValues.map((a) => a.toStringAsFixed(1)).join(' ');
    final emg = emgValues.map((e) => e.round().toString()).join(' ');
    return "Angle: $angles EMG: $emg Time: $timeMs";
  }

  /// Генерировать значение EMG (более активно в середине амплитуды)
  double _generateEMG() {
    final normalized = ((_currentAngle - _minAngle) / (_maxAngle - _minAngle))
        .clamp(0.0, 1.0);
    final activation = sin(normalized * pi); // Пик в середине
    final base = 2000.0 + activation * 6000.0;
    final noise = (_random.nextDouble() * 1200) - 600;
    return (base + noise).clamp(300, 20000);
  }

  /// Освободить ресурсы
  void dispose() {
    stop();
  }
}
