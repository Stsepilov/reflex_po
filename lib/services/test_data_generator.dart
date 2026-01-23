import 'dart:async';
import 'dart:math';

/// Генератор тестовых данных для EMG и угла
/// Используется для тестирования UI без физического устройства
class TestDataGenerator {
  Timer? _timer;
  final Random _random = Random();
  
  final Function({
    required List<double> angleValues,
    required List<double> emgValues,
  }) onNewData;

  TestDataGenerator({required this.onNewData});

  /// Начать генерацию тестовых данных
  void start() {
    _timer?.cancel();
    
    // Генерируем данные каждые 200ms (как в реальном BLE сервисе)
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
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
    // Генерируем 2 значения угла (как в реальном устройстве)
    final angleValues = [
      _generateAngle(),
      _generateAngle(),
    ];

    // Генерируем 5 значений EMG (как в примере)
    final emgValues = [
      _generateEMG(),
      _generateEMG(),
      _generateEMG(),
      _generateEMG(),
      _generateEMG(),
    ];

    onNewData(angleValues: angleValues, emgValues: emgValues);
  }

  /// Генерировать случайное значение угла (0-180°)
  double _generateAngle() {
    // Симулируем плавное изменение угла
    final baseAngle = (DateTime.now().millisecondsSinceEpoch / 100) % 180;
    final noise = _random.nextDouble() * 5 - 2.5; // ±2.5° шум
    return (baseAngle + noise).clamp(0, 180);
  }

  /// Генерировать случайное значение EMG (500-50000)
  double _generateEMG() {
    // Базовый уровень EMG
    final baseLevel = 1000.0;
    
    // Добавляем периодический сигнал (симуляция мышечной активности)
    final time = DateTime.now().millisecondsSinceEpoch / 1000;
    final periodicSignal = sin(time * 2 * pi / 3) * 5000; // 3-секундный цикл
    
    // Добавляем случайный шум
    final noise = _random.nextDouble() * 10000;
    
    // Случайные всплески активности (10% вероятность)
    final burst = _random.nextDouble() < 0.1 ? _random.nextDouble() * 30000 : 0;
    
    return (baseLevel + periodicSignal + noise + burst).clamp(100, 50000);
  }

  /// Освободить ресурсы
  void dispose() {
    stop();
  }
}
