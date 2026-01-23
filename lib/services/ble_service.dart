import 'dart:async';
import 'dart:convert';
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

              // await characteristic.setNotifyValue(true);
              //
              // _valueSubscription = characteristic.lastValueStream.listen((value) {
              //   if (value.isNotEmpty) {
              //     final str = utf8.decode(value);
              //     print("Получено: $str");
              //     _handleIncomingData(str);
              //   }
              // });
              Timer.periodic(const Duration(milliseconds: 200), (timer) async {
                if (_targetDevice == null) {
                  timer.cancel();
                  return;
                }

                try {
                  List<int> value = await characteristic.read();

                  if (value.isNotEmpty) {
                    final str = utf8.decode(value);
                    print("Получено: $str");
                    _handleIncomingData(str);
                  }
                } catch (e) {
                  print("Ошибка чтения характеристики: $e");
                  timer.cancel();
                }
              });

              return;
            }
          }
        }
      }
    } catch (e) {
      print("Ошибка сервисов: $e");
    }
  }

  /// 📥 Обработка входящих данных
  /// Формат: "Angle: 40.1 40.2 EMG: 1000 1242 4523 41343 12321"
  void _handleIncomingData(String stringData) {
    final parsedData = _parseArduinoData(stringData);
    print("Parsed data: $parsedData");
    onNewData(
      angleValues: parsedData['angle'] ?? [],
      emgValues: parsedData['emg'] ?? [],
    );
  }

  /// Парсит строку формата "Angle: 40.1 40.2 EMG: 1000 1242 4523"
  Map<String, List<double>> _parseArduinoData(String data) {
    try {
      List<double> angleValues = [];
      List<double> emgValues = [];

      print("Parsing data: $data");

      // Ищем позиции ключевых слов
      final angleIndex = data.indexOf('Angle:');
      final emgIndex = data.indexOf('EMG:');

      if (angleIndex != -1) {
        // Извлекаем строку между "Angle:" и "EMG:" (или до конца, если EMG нет)
        final angleEnd = emgIndex != -1 ? emgIndex : data.length;
        final angleString = data.substring(angleIndex + 6, angleEnd).trim();
        angleValues = _parseStringToDoubleList(angleString);
        print("Found Angle values: $angleValues");
      }

      if (emgIndex != -1) {
        // Извлекаем строку после "EMG:" до конца
        final emgString = data.substring(emgIndex + 4).trim();
        emgValues = _parseStringToDoubleList(emgString);
        print("Found EMG values: $emgValues");
      }

      return {
        'angle': angleValues,
        'emg': emgValues,
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
    await _valueSubscription?.cancel();
    await _targetDevice?.disconnect();
  }
}
