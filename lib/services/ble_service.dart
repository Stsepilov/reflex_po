import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:reflex_po/services/permission_handler.dart';

typedef OnNewDataCallback = void Function({
  required List<double> angleValues,
  required List<double> emgValues,
});

/// 🔴 ЭТОТ ФАЙЛ ЗАКОММЕНТИРОВАН В BLE_BLOC ДЛЯ ТЕСТИРОВАНИЯ
/// 📝 Чтобы вернуться к реальному BLE:
///    1. В lib/blocs/ble/ble_bloc.dart раскомментируйте import BleService
///    2. Закомментируйте import TestDataGenerator
///    3. Замените _testDataGenerator на _bleService во всех местах
class BleService {
  final OnNewDataCallback onNewData;
  final String targetDeviceName;
  final VoidCallback? onConnected;
  static const String serviceUUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";

  static const String characteristicUUID =
      "beb5483e-36e1-4688-b7f5-ea07361b26a8";

  BluetoothDevice? _targetDevice;
  StreamSubscription? _scanSubscription;
  StreamSubscription<List<int>>? _valueSubscription;
  Timer? _queueProcessorTimer;
  bool _isStreamingData = false;
  BluetoothCharacteristic? _dataCharacteristic;

  // Queue for buffering incoming data
  final Queue<Map<String, List<double>>> _dataQueue = Queue();
  final int _maxQueueSize = 100; // Prevent memory overflow
  int _droppedDataCount = 0;

  BleService({
    required this.onNewData,
    required this.targetDeviceName,
    required this.onConnected,
  });

  /// 🔍 Старт сканирования
  Future<void> startScan() async {
    print("Начинаем сканирование...");

    final ok = await checkBlePermissions();
    if (!ok) {
      print("Нет разрешений на BLE");
      return;
    }

    // Подписка на результаты
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      print("Получено ${results.length} результатов сканирования");
      for (ScanResult result in results) {
        if (result.device.platformName == targetDeviceName) {
          print("Найден девайс: ${result.device.platformName}");
          onConnected?.call();
          stopScan();
          _targetDevice = result.device;
          _connectToDevice();
          break;
        }
      }
    }, onError: (error) {
      print("Ошибка сканирования: $error");
    });

    FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
  }

  void stopScan() {
    print("Останавливаем сканирование...");
    FlutterBluePlus.stopScan();
    _scanSubscription?.cancel();
    _scanSubscription = null;
  }

  Future<void> _connectToDevice() async {
    if (_targetDevice == null) return;

    try {
      await _targetDevice!.connect(autoConnect: false);
      print("Подключено к ${_targetDevice!.platformName}");
      onConnected?.call();
      await _discoverServices();
    } catch (e) {
      print("Ошибка подключения: $e");
    }
  }

  Future<void> _discoverServices() async {
    if (_targetDevice == null) return;

    try {
      List<BluetoothService> services = await _targetDevice!.discoverServices();

      for (BluetoothService service in services) {
        if (service.uuid.toString().startsWith('180')) continue;
        if (service.uuid.toString().toLowerCase() == serviceUUID) {
          for (BluetoothCharacteristic characteristic
              in service.characteristics) {
            if (characteristic.uuid.toString().toLowerCase() ==
                characteristicUUID) {
              print("Подписываемся на notify");

              // Сохраняем характеристику для чтения данных
              _dataCharacteristic = characteristic;
              // Не запускаем автоматически - будет запущено при входе на нужный экран
              print("Характеристика найдена и сохранена");
              return;
            }
          }
        }
      }
    } catch (e) {
      print("Ошибка сервисов: $e");
    }
  }

  /// 🎬 Начать поток данных (notify)
  Future<void> _startDataStream(BluetoothCharacteristic characteristic) async {
    await _valueSubscription?.cancel();
    _valueSubscription = null;
    _isStreamingData = true;

    try {
      await characteristic.setNotifyValue(true);
      _valueSubscription = characteristic.lastValueStream.listen(
        (value) {
          if (!_isStreamingData || value.isEmpty) return;

          final str = utf8.decode(value, allowMalformed: true).trim();
          if (str.isEmpty) return;

          print("Получено notify: $str");
          _handleIncomingData(str);
        },
        onError: (error) {
          print("Ошибка notify характеристики: $error");
        },
      );
    } catch (e) {
      print("Ошибка запуска notify: $e");
    }
  }

  /// ⏸️ Приостановить поток данных
  void pauseDataStream() {
    print("Приостановка потока данных");
    _isStreamingData = false;
    _valueSubscription?.cancel();
    _valueSubscription = null;
    _dataCharacteristic?.setNotifyValue(false).catchError((error) {
      print("Ошибка отключения notify: $error");
      return false;
    });
    _stopQueueProcessor();
  }

  /// ▶️ Возобновить поток данных
  Future<void> resumeDataStream() async {
    print("Возобновление потока данных");
    if (_dataCharacteristic != null) {
      _droppedDataCount = 0; // Reset counter
      await _startDataStream(_dataCharacteristic!);
      _startQueueProcessor(); // Start queue processor
    } else {
      print("Характеристика не найдена, невозможно возобновить поток");
    }
  }

  /// 📥 Обработка входящих данных
  /// Формат: "Angle: 40.1 40.2 EMG: 1000 1242 4523 41343 12321"
  void _handleIncomingData(String stringData) {
    if (!_isStreamingData) return;

    final parsedData = _parseArduinoData(stringData);

    // Add to queue instead of immediate callback
    if (_dataQueue.length < _maxQueueSize) {
      _dataQueue.add(parsedData);
    } else {
      // Queue full - drop oldest data and add new
      print("⚠️ Queue full (${_maxQueueSize}), dropping oldest data");
      _droppedDataCount++;
      _dataQueue.removeFirst();
      _dataQueue.add(parsedData);
    }
  }

  /// 🔄 Process queued data at controlled rate
  void _startQueueProcessor() {
    _queueProcessorTimer?.cancel();

    // Process queue every 50ms (20 Hz processing rate)
    _queueProcessorTimer =
        Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!_isStreamingData) {
        timer.cancel();
        return;
      }

      // Adaptive draining: process more items when backlog grows.
      final itemsToProcess = min(_dataQueue.length, _calculateDrainBatchSize());

      for (int i = 0; i < itemsToProcess; i++) {
        if (_dataQueue.isNotEmpty) {
          final data = _dataQueue.removeFirst();
          onNewData(
            angleValues: data['angle'] ?? [],
            emgValues: data['emg'] ?? [],
          );
        }
      }

      // Monitor queue health
      if (_dataQueue.length > 50) {
        print("⚠️ Queue backlog: ${_dataQueue.length} items");
      }

      if (_droppedDataCount > 0 && _droppedDataCount % 10 == 0) {
        print("⚠️ Total dropped data packets: $_droppedDataCount");
      }
    });
  }

  int _calculateDrainBatchSize() {
    final queueLength = _dataQueue.length;
    if (queueLength >= 80) return 12;
    if (queueLength >= 50) return 8;
    if (queueLength >= 20) return 5;
    if (queueLength >= 5) return 3;
    return 1;
  }

  /// 🧹 Stop queue processor
  void _stopQueueProcessor() {
    _queueProcessorTimer?.cancel();
    _queueProcessorTimer = null;
    _dataQueue.clear();
  }

  /// Парсит строку формата:
  /// "Angle: 40.1 40.2 EMG 1000 1242 4523 Time: 123456"
  /// (двоеточия у EMG/Time могут отсутствовать)
  Map<String, List<double>> _parseArduinoData(String data) {
    try {
      List<double> angleValues = [];
      List<double> emgValues = [];

      // Ищем позиции ключевых слов
      final angleIndex = data.indexOf('Angle:');
      final emgMatch =
          RegExp(r'\bEMG:?\b', caseSensitive: false).firstMatch(data);
      final timeMatch =
          RegExp(r'\bTime:?\b', caseSensitive: false).firstMatch(data);
      final emgIndex = emgMatch?.start ?? -1;
      final timeIndex = timeMatch?.start ?? -1;

      if (angleIndex != -1) {
        // Извлекаем строку между "Angle:" и "EMG" (или до "Time"/конца)
        final angleEnd = emgIndex != -1
            ? emgIndex
            : (timeIndex != -1 ? timeIndex : data.length);
        final angleString = data.substring(angleIndex + 6, angleEnd).trim();
        angleValues = _parseStringToDoubleList(angleString);
      }

      if (emgIndex != -1) {
        // Извлекаем строку после "EMG[:]" до "Time" (или до конца)
        final emgTokenLength = emgMatch?.group(0)?.length ?? 3;
        final emgStart = emgIndex + emgTokenLength;
        final emgEnd =
            timeIndex != -1 && timeIndex > emgStart ? timeIndex : data.length;
        final emgString = data.substring(emgStart, emgEnd).trim();
        emgValues = _parseStringToDoubleList(emgString);
      }
      print(emgValues.map((e) => e * 10).toList());
      return {
        'angle': angleValues,
        'emg': emgValues.map((e) => e * 10).toList(),
      };
    } catch (e) {
      print("Ошибка парсинга данных: $e");
      return {
        'angle': [],
        'emg': [],
      };
    }
  }

  List<double> _parseStringToDoubleList(String data) {
    try {
      return data
          .split(' ')
          .map((e) => double.tryParse(e.trim()))
          .whereType<double>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 🧹 Освобождение ресурсов
  Future<void> dispose() async {
    stopScan();
    pauseDataStream();
    _stopQueueProcessor();
    await _valueSubscription?.cancel();
    await _targetDevice?.disconnect();
  }
}
