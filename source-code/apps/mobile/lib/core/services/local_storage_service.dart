import 'package:lumenpass_core/lumenpass_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences-backed key-value store for non-sensitive app settings.
class LocalStorageService implements KeyValueStore {
  SharedPreferences? _prefs;

  Future<SharedPreferences> get _instance async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  @override
  Future<String?> read(String key) async {
    final prefs = await _instance;
    return prefs.getString(key);
  }

  @override
  Future<void> write(String key, String? value) async {
    final prefs = await _instance;
    if (value == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, value);
    }
  }

  @override
  Future<void> delete(String key) async {
    final prefs = await _instance;
    await prefs.remove(key);
  }
}
