import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/services/game_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

base class _SlowPlatform extends SharedPreferencesAsyncPlatform {
  @override
  Future<void> setString(
    String key,
    String value,
    SharedPreferencesOptions options,
  ) async {}

  @override
  Future<void> setBool(String key, bool value, SharedPreferencesOptions options) async {}

  @override
  Future<void> setDouble(String key, double value, SharedPreferencesOptions options) async {}

  @override
  Future<void> setInt(String key, int value, SharedPreferencesOptions options) async {}

  @override
  Future<void> setStringList(
    String key,
    List<String> value,
    SharedPreferencesOptions options,
  ) async {}

  @override
  Future<String?> getString(String key, SharedPreferencesOptions options) async {
    await Future.delayed(const Duration(seconds: 5));
    return null;
  }

  @override
  Future<bool?> getBool(String key, SharedPreferencesOptions options) async => null;

  @override
  Future<double?> getDouble(String key, SharedPreferencesOptions options) async => null;

  @override
  Future<int?> getInt(String key, SharedPreferencesOptions options) async => null;

  @override
  Future<List<String>?> getStringList(
    String key,
    SharedPreferencesOptions options,
  ) async => null;

  @override
  Future<void> clear(
    ClearPreferencesParameters parameters,
    SharedPreferencesOptions options,
  ) async {}

  @override
  Future<Map<String, Object>> getPreferences(
    GetPreferencesParameters parameters,
    SharedPreferencesOptions options,
  ) async => <String, Object>{};

  @override
  Future<Set<String>> getKeys(
    GetPreferencesParameters parameters,
    SharedPreferencesOptions options,
  ) async => <String>{};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance = _SlowPlatform();
  });

  test('load falls back to null when SharedPreferences stalls', () async {
    final storage = SharedPreferencesGameStorage(
      preferences: SharedPreferencesAsync(),
    );

    expect(await storage.load(), isNull);
  });
}
