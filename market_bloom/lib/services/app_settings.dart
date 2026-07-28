import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ControlMode { directTouch, joystick, leftJoystick }

/// Persisted user settings for PoMarket.
///
/// Uses the same SharedPreferencesAsync backend as [GameStorage] so settings
/// survive restarts and share the existing storage architecture.
class AppSettings extends ChangeNotifier {
  AppSettings({SharedPreferencesAsync? preferences})
    : _preferences = preferences;

  SharedPreferencesAsync? _preferences;

  SharedPreferencesAsync get _prefs {
    _preferences ??= SharedPreferencesAsync();
    return _preferences!;
  }

  static const _languageKey = 'pomarket.settings.language';
  static const _soundKey = 'pomarket.settings.sound';
  static const _reducedMotionKey = 'pomarket.settings.reducedMotion';
  static const _controlModeKey = 'pomarket.settings.controlMode';

  Locale? _language;
  bool? _soundEnabled;
  bool? _reducedMotion;
  String? _controlMode;

  bool _loaded = false;

  /// The manually selected language, or `null` for system default.
  Locale? get language => _language;

  /// Whether sound effects are enabled (defaults to true).
  bool get soundEnabled => _soundEnabled ?? true;

  /// Whether reduced motion is requested (defaults to false).
  bool get reducedMotion => _reducedMotion ?? false;

  /// The preferred control mode (defaults to directTouch on mobile).
  ControlMode get controlMode {
    final mode = _controlMode ?? 'directTouch';
    return ControlMode.values.firstWhere(
      (e) => e.name == mode,
      orElse: () => ControlMode.directTouch,
    );
  }

  bool get isLoaded => _loaded;

  /// Loads all settings from persistent storage.
  Future<void> load() async {
    final languageCode = await _prefs.getString(_languageKey);
    _language = languageCode != null && languageCode.isNotEmpty
        ? Locale(languageCode)
        : null;
    _soundEnabled = await _prefs.getBool(_soundKey) ?? true;
    _reducedMotion = await _prefs.getBool(_reducedMotionKey) ?? false;
    _controlMode = await _prefs.getString(_controlModeKey);
    _loaded = true;
    notifyListeners();
  }

  /// Sets the language. Pass `null` to use the system default.
  Future<void> setLanguage(Locale? locale) async {
    if (locale == null) {
      await _prefs.remove(_languageKey);
    } else {
      await _prefs.setString(_languageKey, locale.languageCode);
    }
    _language = locale;
    notifyListeners();
  }

  Future<void> setSoundEnabled(bool value) async {
    await _prefs.setBool(_soundKey, value);
    _soundEnabled = value;
    notifyListeners();
  }

  Future<void> setReducedMotion(bool value) async {
    await _prefs.setBool(_reducedMotionKey, value);
    _reducedMotion = value;
    notifyListeners();
  }

  Future<void> setControlMode(ControlMode mode) async {
    await _prefs.setString(_controlModeKey, mode.name);
    _controlMode = mode.name;
    notifyListeners();
  }

  /// Convenience: the effective text direction for the current locale.
  TextDirection get textDirection =>
      _language != null &&
          (_language!.languageCode == 'ar' || _language!.languageCode == 'he')
      ? TextDirection.rtl
      : TextDirection.ltr;
}
