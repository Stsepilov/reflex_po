import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:reflex_po/services/permission_handler.dart';

typedef OnNewDataCallback = void Function(List<double> newValues);

class BleService {
  final OnNewDataCallback onNewData;
  final String targetDeviceName;
  final int _bufferSize = 7;
  final Duration _bufferTimeout = Duration(milliseconds: 105);
  List<double> _currentBuffer = [];
  Timer? _bufferTimer;
  final VoidCallback? onConnected;
  static const String serviceUUID =
      "4fafc201-1fb5-459e-8fcc-c5c9c331914b";

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
          for (BluetoothCharacteristic characteristic in service.characteristics) {

            if (characteristic.uuid.toString().toLowerCase() == characteristicUUID) {
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
  void _handleIncomingData(String stringData) {
    final numbers = _parseStringToDoubleList(stringData);
    onNewData(numbers);
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
