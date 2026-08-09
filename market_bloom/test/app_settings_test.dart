import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:pomarket/services/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('fresh settings migrate to English and persist it', () async {
    final preferences = _MemoryPreferences();
    final settings = AppSettings(preferences: preferences);

    await settings.load();

    expect(settings.language?.languageCode, 'en');
    expect(await preferences.getString('pomarket.settings.language'), 'en');
    expect(settings.textDirection, TextDirection.ltr);
  });

  test('explicit Hebrew and Arabic choices persist across reloads', () async {
    final preferences = _MemoryPreferences();
    final settings = AppSettings(preferences: preferences);

    await settings.setLanguage(const Locale('he'));
    final hebrew = AppSettings(preferences: preferences);
    await hebrew.load();
    expect(hebrew.language?.languageCode, 'he');
    expect(hebrew.textDirection, TextDirection.rtl);

    await settings.setLanguage(const Locale('ar'));
    final arabic = AppSettings(preferences: preferences);
    await arabic.load();
    expect(arabic.language?.languageCode, 'ar');
    expect(arabic.textDirection, TextDirection.rtl);
  });

  test('explicit System language remains a system choice', () async {
    final preferences = _MemoryPreferences();
    final settings = AppSettings(preferences: preferences);

    await settings.setLanguage(null);
    final restored = AppSettings(preferences: preferences);
    await restored.load();

    expect(restored.language, isNull);
    expect(restored.followsSystemLanguage, isTrue);
  });

  test('migration does not overwrite a meaningful saved choice', () async {
    final preferences = _MemoryPreferences();
    await preferences.setString('pomarket.settings.language', 'he');
    final settings = AppSettings(preferences: preferences);

    await settings.load();

    expect(settings.language?.languageCode, 'he');
    expect(await preferences.getString('pomarket.settings.language'), 'he');
  });
}

class _MemoryPreferences implements SharedPreferencesAsync {
  final Map<String, Object> _values = <String, Object>{};

  @override
  Future<bool> getBool(String key) async => _values[key] as bool? ?? true;

  @override
  Future<double> getDouble(String key) async => _values[key] as double? ?? 0;

  @override
  Future<int> getInt(String key) async => _values[key] as int? ?? 0;

  @override
  Future<String?> getString(String key) async => _values[key] as String?;

  @override
  Future<List<String>> getStringList(String key) async =>
      (_values[key] as List<String>?) ?? <String>[];

  @override
  Future<bool> containsKey(String key) async => _values.containsKey(key);

  @override
  Future<void> remove(String key) async => _values.remove(key);

  @override
  Future<void> setBool(String key, bool value) async => _values[key] = value;

  @override
  Future<void> setDouble(String key, double value) async =>
      _values[key] = value;

  @override
  Future<void> setInt(String key, int value) async => _values[key] = value;

  @override
  Future<void> setString(String key, String value) async =>
      _values[key] = value;

  @override
  Future<void> setStringList(String key, List<String> value) async =>
      _values[key] = value;

  @override
  Future<void> clear({Set<String>? allowList}) async => _values.clear();

  @override
  Future<Set<String>> getKeys({Set<String>? allowList}) async =>
      _values.keys.toSet();

  // ignore: annotate_overrides
  Future<void> reload() async {}

  @override
  Future<Map<String, Object?>> getAll({Set<String>? allowList}) async =>
      Map<String, Object?>.from(_values);
}
