import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const _deviceIdKey = 'detective_daily_device_id';

class DeviceIdService {
  Future<String> getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final generated = const Uuid().v4();
    await prefs.setString(_deviceIdKey, generated);
    return generated;
  }
}
