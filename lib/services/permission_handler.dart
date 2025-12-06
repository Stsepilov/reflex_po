import 'package:permission_handler/permission_handler.dart';

Future<bool> checkBlePermissions() async {
  // Android 12+ (API 31+)
  if (await Permission.bluetoothScan.isDenied ||
      await Permission.bluetoothConnect.isDenied) {
    final scan = await Permission.bluetoothScan.request();
    final connect = await Permission.bluetoothConnect.request();

    if (scan.isDenied || connect.isDenied) {
      print("BLE permissions denied");
      return false;
    }
  }

  // Для устройств до Android 12
  if (await Permission.location.isDenied) {
    final loc = await Permission.location.request();
    if (loc.isDenied) {
      print("Location permission denied");
      return false;
    }
  }

  return true;
}
