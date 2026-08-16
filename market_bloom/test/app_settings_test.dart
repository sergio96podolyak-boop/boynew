import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
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

  test('reduced motion defaults off, notifies, and persists', () async {
    final preferences = _MemoryPreferences();
    final settings = AppSettings(preferences: preferences);
    var notifications = 0;
    settings.addListener(() => notifications++);

    await settings.load();
    expect(settings.reducedMotion, isFalse);

    await settings.setReducedMotion(true);
    expect(settings.reducedMotion, isTrue);
    expect(notifications, 2);

    final restored = AppSettings(preferences: preferences);
    await restored.load();
    expect(restored.reducedMotion, isTrue);

    await restored.setReducedMotion(false);
    final disabledAgain = AppSettings(preferences: preferences);
    await disabledAgain.load();
    expect(disabledAgain.reducedMotion, isFalse);
  });

  test('analytics is opt-in and consent persists', () async {
    final preferences = _MemoryPreferences();
    final settings = AppSettings(preferences: preferences);

    await settings.load();
    expect(settings.analyticsEnabled, isFalse);

    await settings.setAnalyticsEnabled(true);
    final restored = AppSettings(preferences: preferences);
    await restored.load();
    expect(restored.analyticsEnabled, isTrue);

    await restored.setAnalyticsEnabled(false);
    final revoked = AppSettings(preferences: preferences);
    await revoked.load();
    expect(revoked.analyticsEnabled, isFalse);
  });

  test('sound and control mode persist through the existing settings service', () async {
    final preferences = _MemoryPreferences();
    final settings = AppSettings(preferences: preferences);
    await settings.load();

    expect(settings.soundEnabled, isTrue);
    expect(settings.controlMode, ControlMode.directTouch);

    await settings.setSoundEnabled(false);
    await settings.setControlMode(ControlMode.leftJoystick);

    final restored = AppSettings(preferences: preferences);
    await restored.load();
    expect(restored.soundEnabled, isFalse);
    expect(restored.controlMode, ControlMode.leftJoystick);
    expect(await preferences.getBool('pomarket.settings.sound'), isFalse);
    expect(
      await preferences.getString('pomarket.settings.controlMode'),
      ControlMode.leftJoystick.name,
    );
  });
}

class _MemoryPreferences implements SharedPreferencesAsync {
  final Map<String, Object> _values = <String, Object>{};

  @override
  Future<bool?> getBool(String key) async => _values[key] as bool?;
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
  Future<void> setString(String key, String value) async => _values[key] = value;
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
