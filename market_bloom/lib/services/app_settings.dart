import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ControlMode { directTouch, joystick, leftJoystick }

enum PrivacyConsentStatus { required, accepted, rejected, customized }

class PrivacyConsentSnapshot {
  const PrivacyConsentSnapshot({
    required this.status,
    required this.analyticsEnabled,
    required this.crashReportingEnabled,
    required this.adsEnabled,
  });

  final PrivacyConsentStatus status;
  final bool analyticsEnabled;
  final bool crashReportingEnabled;
  final bool adsEnabled;

  bool get hasDecision => status != PrivacyConsentStatus.required;
}

/// Persisted settings and the single privacy-consent source of truth.
class AppSettings extends ChangeNotifier {
  factory AppSettings({SharedPreferencesAsync? preferences}) {
    return AppSettings._(preferences);
  }

  AppSettings._(this._preferences);

  static const privacyConsentSchemaVersion = 1;
  static const _storageTimeout = Duration(seconds: 2);
  static const _languageKey = 'pomarket.settings.language';
  static const _systemLanguageCode = 'system';
  static const _soundKey = 'pomarket.settings.sound';
  static const _reducedMotionKey = 'pomarket.settings.reducedMotion';
  static const _controlModeKey = 'pomarket.settings.controlMode';
  static const _legacyAnalyticsKey = 'pomarket.settings.analyticsEnabled';
  static const _privacyVersionKey = 'pomarket.privacy.version';
  static const _privacyStatusKey = 'pomarket.privacy.status';
  static const _privacyAnalyticsKey = 'pomarket.privacy.analytics';
  static const _privacyCrashKey = 'pomarket.privacy.crashReporting';
  static const _privacyAdsKey = 'pomarket.privacy.ads';

  SharedPreferencesAsync? _preferences;
  SharedPreferencesAsync get _prefs =>
      _preferences ??= SharedPreferencesAsync();

  Locale? _language;
  bool? _soundEnabled;
  bool? _reducedMotion;
  String? _controlMode;
  PrivacyConsentSnapshot _privacy = const PrivacyConsentSnapshot(
    status: PrivacyConsentStatus.required,
    analyticsEnabled: false,
    crashReportingEnabled: false,
    adsEnabled: false,
  );
  bool _loaded = false;

  Locale? get language => _language;
  bool get followsSystemLanguage => _loaded && _language == null;
  bool get soundEnabled => _soundEnabled ?? true;
  bool get reducedMotion => _reducedMotion ?? false;
  ControlMode get controlMode => ControlMode.values.firstWhere(
    (value) => value.name == (_controlMode ?? 'directTouch'),
    orElse: () => ControlMode.directTouch,
  );
  bool get isLoaded => _loaded;

  PrivacyConsentSnapshot get privacyConsent => _privacy;
  PrivacyConsentStatus get privacyConsentStatus => _privacy.status;
  bool get requiresPrivacyConsent => !_privacy.hasDecision;
  bool get analyticsEnabled =>
      _privacy.hasDecision && _privacy.analyticsEnabled;
  bool get crashReportingEnabled =>
      _privacy.hasDecision && _privacy.crashReportingEnabled;
  bool get adsEnabled => _privacy.hasDecision && _privacy.adsEnabled;

  Future<T> _bounded<T>(Future<T> operation) =>
      operation.timeout(_storageTimeout);

  Future<void> load() async {
    try {
      final languageCode = await _bounded(_prefs.getString(_languageKey));
      if (languageCode == _systemLanguageCode) {
        _language = null;
      } else if (languageCode == 'en' ||
          languageCode == 'he' ||
          languageCode == 'ar') {
        _language = Locale(languageCode!);
      } else {
        _language = const Locale('en');
        await _bounded(_prefs.setString(_languageKey, 'en'));
      }
      _soundEnabled = await _bounded(_prefs.getBool(_soundKey)) ?? true;
      _reducedMotion =
          await _bounded(_prefs.getBool(_reducedMotionKey)) ?? false;
      _controlMode = await _bounded(_prefs.getString(_controlModeKey));
    } on Object {
      _language ??= const Locale('en');
      _soundEnabled ??= true;
      _reducedMotion ??= false;
    }
    await _loadPrivacyConsent();
    _loaded = true;
    notifyListeners();
  }

  Future<void> _loadPrivacyConsent() async {
    try {
      final version = await _bounded(_prefs.getInt(_privacyVersionKey));
      final statusName = await _bounded(_prefs.getString(_privacyStatusKey));
      if (version == privacyConsentSchemaVersion && statusName != null) {
        final status = PrivacyConsentStatus.values.firstWhere(
          (value) => value.name == statusName,
          orElse: () => PrivacyConsentStatus.required,
        );
        _privacy = PrivacyConsentSnapshot(
          status: status,
          analyticsEnabled:
              await _bounded(_prefs.getBool(_privacyAnalyticsKey)) ?? false,
          crashReportingEnabled:
              await _bounded(_prefs.getBool(_privacyCrashKey)) ?? false,
          adsEnabled: await _bounded(_prefs.getBool(_privacyAdsKey)) ?? false,
        );
        return;
      }
      if (await _bounded(_prefs.containsKey(_legacyAnalyticsKey))) {
        final analytics =
            await _bounded(_prefs.getBool(_legacyAnalyticsKey)) ?? false;
        _privacy = PrivacyConsentSnapshot(
          status: analytics
              ? PrivacyConsentStatus.customized
              : PrivacyConsentStatus.rejected,
          analyticsEnabled: analytics,
          crashReportingEnabled: analytics,
          adsEnabled: false,
        );
        await _persistPrivacy();
      } else {
        _privacy = const PrivacyConsentSnapshot(
          status: PrivacyConsentStatus.required,
          analyticsEnabled: false,
          crashReportingEnabled: false,
          adsEnabled: false,
        );
      }
    } on Object {
      _privacy = const PrivacyConsentSnapshot(
        status: PrivacyConsentStatus.required,
        analyticsEnabled: false,
        crashReportingEnabled: false,
        adsEnabled: false,
      );
    }
  }

  Future<void> acceptAllPrivacy() => setPrivacyChoices(
    analytics: true,
    crashReporting: true,
    ads: true,
  );

  Future<void> rejectAllPrivacy() => setPrivacyChoices(
    analytics: false,
    crashReporting: false,
    ads: false,
  );

  Future<void> setPrivacyChoices({
    required bool analytics,
    required bool crashReporting,
    required bool ads,
  }) async {
    final status = analytics && crashReporting && ads
        ? PrivacyConsentStatus.accepted
        : !analytics && !crashReporting && !ads
        ? PrivacyConsentStatus.rejected
        : PrivacyConsentStatus.customized;
    _privacy = PrivacyConsentSnapshot(
      status: status,
      analyticsEnabled: analytics,
      crashReportingEnabled: crashReporting,
      adsEnabled: ads,
    );
    try {
      await _persistPrivacy();
    } on Object {
      // In-memory consent remains valid for this session.
    }
    notifyListeners();
  }

  Future<void> _persistPrivacy() async {
    // The schema version is the commit marker. Removing it first means an
    // interrupted write is migrated conservatively instead of trusted as a
    // complete current-schema consent record.
    await _bounded(_prefs.remove(_privacyVersionKey));
    await _bounded(_prefs.setString(_privacyStatusKey, _privacy.status.name));
    await _bounded(
      _prefs.setBool(_privacyAnalyticsKey, _privacy.analyticsEnabled),
    );
    await _bounded(
      _prefs.setBool(_privacyCrashKey, _privacy.crashReportingEnabled),
    );
    await _bounded(_prefs.setBool(_privacyAdsKey, _privacy.adsEnabled));
    await _bounded(
      _prefs.setBool(_legacyAnalyticsKey, _privacy.analyticsEnabled),
    );
    await _bounded(
      _prefs.setInt(_privacyVersionKey, privacyConsentSchemaVersion),
    );
  }

  Future<void> setAnalyticsEnabled(bool value) => setPrivacyChoices(
    analytics: value,
    crashReporting: _privacy.crashReportingEnabled,
    ads: _privacy.adsEnabled,
  );

  Future<void> setLanguage(Locale? locale) async {
    try {
      await _bounded(
        _prefs.setString(
          _languageKey,
          locale == null ? _systemLanguageCode : locale.languageCode,
        ),
      );
    } on Object {
      // Settings persistence is best-effort.
    }
    _language = locale;
    notifyListeners();
  }

  Future<void> setSoundEnabled(bool value) async {
    try {
      await _bounded(_prefs.setBool(_soundKey, value));
    } on Object {
      // Settings persistence is best-effort.
    }
    _soundEnabled = value;
    notifyListeners();
  }

  Future<void> setReducedMotion(bool value) async {
    try {
      await _bounded(_prefs.setBool(_reducedMotionKey, value));
    } on Object {
      // Settings persistence is best-effort.
    }
    _reducedMotion = value;
    notifyListeners();
  }

  Future<void> setControlMode(ControlMode mode) async {
    try {
      await _bounded(_prefs.setString(_controlModeKey, mode.name));
    } on Object {
      // Settings persistence is best-effort.
    }
    _controlMode = mode.name;
    notifyListeners();
  }

  TextDirection get textDirection =>
      _language != null &&
          (_language!.languageCode == 'ar' || _language!.languageCode == 'he')
      ? TextDirection.rtl
      : TextDirection.ltr;
}
