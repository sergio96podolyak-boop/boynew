import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/services/analytics/analytics_backend.dart';
import 'package:pomarket/services/analytics/analytics_event.dart';
import 'package:pomarket/services/analytics/analytics_service.dart';
import 'package:pomarket/services/app_settings.dart';
import 'package:pomarket/services/crash_reporting/crash_reporter.dart';
import 'package:pomarket/services/monetization_service.dart';
import 'package:pomarket/services/privacy/privacy_runtime_coordinator.dart';
import 'package:pomarket/ui/widgets/privacy_consent_layer.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('first launch requires consent with every optional service disabled', () async {
    final settings = AppSettings(preferences: _MemoryPreferences());
    await settings.load();
    expect(settings.privacyConsentStatus, PrivacyConsentStatus.required);
    expect(settings.requiresPrivacyConsent, isTrue);
    expect(settings.analyticsEnabled, isFalse);
    expect(settings.crashReportingEnabled, isFalse);
    expect(settings.adsEnabled, isFalse);
  });

  test('accept reject and customized choices are deterministic', () async {
    final settings = AppSettings(preferences: _MemoryPreferences());
    await settings.load();
    await settings.acceptAllPrivacy();
    expect(settings.privacyConsentStatus, PrivacyConsentStatus.accepted);
    expect(settings.analyticsEnabled, isTrue);
    expect(settings.crashReportingEnabled, isTrue);
    expect(settings.adsEnabled, isTrue);
    await settings.rejectAllPrivacy();
    expect(settings.privacyConsentStatus, PrivacyConsentStatus.rejected);
    expect(settings.analyticsEnabled, isFalse);
    await settings.setPrivacyChoices(
      analytics: true,
      crashReporting: false,
      ads: false,
    );
    expect(settings.privacyConsentStatus, PrivacyConsentStatus.customized);
    expect(settings.analyticsEnabled, isTrue);
    expect(settings.crashReportingEnabled, isFalse);
  });

  test('privacy choices persist across restarts', () async {
    final preferences = _MemoryPreferences();
    final settings = AppSettings(preferences: preferences);
    await settings.load();
    await settings.setPrivacyChoices(
      analytics: true,
      crashReporting: false,
      ads: true,
    );
    final restored = AppSettings(preferences: preferences);
    await restored.load();
    expect(restored.privacyConsentStatus, PrivacyConsentStatus.customized);
    expect(restored.analyticsEnabled, isTrue);
    expect(restored.crashReportingEnabled, isFalse);
    expect(restored.adsEnabled, isTrue);
  });

  test('legacy analytics opt-in migrates without enabling ads', () async {
    final preferences = _MemoryPreferences();
    await preferences.setBool('pomarket.settings.analyticsEnabled', true);
    final settings = AppSettings(preferences: preferences);
    await settings.load();
    expect(settings.privacyConsentStatus, PrivacyConsentStatus.customized);
    expect(settings.analyticsEnabled, isTrue);
    expect(settings.crashReportingEnabled, isTrue);
    expect(settings.adsEnabled, isFalse);
  });

  test('analytics remains gated by the unified privacy choice', () async {
    final settings = AppSettings(preferences: _MemoryPreferences());
    await settings.load();
    final backend = _AnalyticsBackend();
    final analytics = AnalyticsService(
      backend: backend,
      hasConsent: () => settings.analyticsEnabled,
    );
    analytics.track(AnalyticsEventName.appSessionStarted);
    await _flush();
    expect(backend.events, isEmpty);
    await settings.setPrivacyChoices(
      analytics: true,
      crashReporting: false,
      ads: false,
    );
    analytics.track(AnalyticsEventName.appSessionStarted);
    await _flush();
    expect(backend.events, hasLength(1));
  });

  test('runtime coordinator applies crash and ad choices without blocking gameplay', () async {
    final settings = AppSettings(preferences: _MemoryPreferences());
    await settings.load();
    final crash = _ConsentCrashReporter();
    final monetization = _ConsentMonetizationService();
    final coordinator = PrivacyRuntimeCoordinator(
      settings: settings,
      crashReporter: crash,
      monetization: monetization,
    )..start();
    await _flush();
    expect(monetization.initializeCalls, 0);
    expect(crash.values.last, isFalse);
    await settings.acceptAllPrivacy();
    await _flush();
    expect(monetization.initializeCalls, 1);
    expect(crash.values.last, isTrue);
    await settings.setPrivacyChoices(
      analytics: false,
      crashReporting: false,
      ads: false,
    );
    await _flush();
    expect(crash.values.last, isFalse);
    expect(monetization.refreshCalls, greaterThan(0));
    coordinator.dispose();
  });

  test('settings load failure safely falls back to required consent', () async {
    final settings = AppSettings(preferences: _ThrowingPreferences());
    await settings.load();
    expect(settings.isLoaded, isTrue);
    expect(settings.requiresPrivacyConsent, isTrue);
    expect(settings.analyticsEnabled, isFalse);
  });

  testWidgets('first-launch consent is responsive accessible RTL and reduced-motion safe', (
    tester,
  ) async {
    final preferences = _MemoryPreferences();
    final settings = AppSettings(preferences: preferences);
    await settings.setLanguage(const Locale('ar'));
    await settings.setReducedMotion(true);
    await settings.load();
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const <Locale>[Locale('en'), Locale('ar')],
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: PrivacyConsentLayer(
          settings: settings,
          child: const Scaffold(body: Text('Core game')),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('privacy-consent-first-launch')), findsOneWidget);
    expect(find.byKey(const ValueKey('privacy-accept-all')), findsOneWidget);
    expect(find.byKey(const ValueKey('privacy-reject-all')), findsOneWidget);
    expect(find.bySemanticsLabel('خيارات الخصوصية'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('privacy-reject-all')));
    await tester.pump();
    expect(settings.privacyConsentStatus, PrivacyConsentStatus.rejected);
    expect(find.text('Core game'), findsOneWidget);

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('privacy settings can be reopened and changed later', (tester) async {
    final settings = AppSettings(preferences: _MemoryPreferences());
    await settings.load();
    await settings.rejectAllPrivacy();

    await tester.pumpWidget(
      MaterialApp(
        home: PrivacySettingsLauncher(
          settings: settings,
          child: const Scaffold(body: Text('Settings content')),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-privacy-settings')));
    await tester.pumpAndSettle();

    final analyticsSwitch = find.byType(Switch).first;
    await tester.ensureVisible(analyticsSwitch);
    await tester.tap(analyticsSwitch);
    final save = find.byKey(const ValueKey('privacy-save-choices'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(settings.analyticsEnabled, isTrue);
    expect(settings.privacyConsentStatus, PrivacyConsentStatus.customized);
  });
}

Future<void> _flush() => Future<void>.delayed(const Duration(milliseconds: 20));

class _AnalyticsBackend implements AnalyticsBackend {
  final List<AnalyticsEvent> events = <AnalyticsEvent>[];
  @override
  bool get isAvailable => true;
  @override
  Future<void> send(AnalyticsEvent event) async => events.add(event);
}

class _ConsentCrashReporter
    implements CrashReporter, ConsentAwareCrashReporter {
  final List<bool> values = <bool>[];
  @override
  bool get isAvailable => values.isNotEmpty && values.last;
  @override
  Future<bool> initialize() async => isAvailable;
  @override
  Future<void> record(CrashReport report) async {}
  @override
  Future<void> updateConsent(bool enabled) async => values.add(enabled);
}

class _ConsentMonetizationService
    implements MonetizationService, ConsentAwareMonetizationService {
  int initializeCalls = 0;
  int refreshCalls = 0;
  @override
  Future<void> initialize() async => initializeCalls++;
  @override
  Future<void> refreshConsent() async => refreshCalls++;
  @override
  bool get interstitialAdsAvailable => false;
  @override
  bool get isPreview => false;
  @override
  bool get rewardedAdsAvailable => false;
  @override
  bool get storeAvailable => false;
  @override
  void dispose() {}
  @override
  String? priceFor(StoreProduct product) => null;
  @override
  Future<StorePurchaseResult> purchase(StoreProduct product) async =>
      StorePurchaseResult.failed(product);
  @override
  Future<List<StorePurchaseResult>> restorePurchases() async => const [];
  @override
  Future<bool> showInterstitial(InterstitialPlacement placement) async => false;
  @override
  Future<bool> showRewardedAd(RewardPlacement placement) async => false;
}

class _MemoryPreferences implements SharedPreferencesAsync {
  final Map<String, Object> values = <String, Object>{};
  @override
  Future<bool?> getBool(String key) async => values[key] as bool?;
  @override
  Future<double> getDouble(String key) async => values[key] as double? ?? 0;
  @override
  Future<int> getInt(String key) async => values[key] as int? ?? 0;
  @override
  Future<String?> getString(String key) async => values[key] as String?;
  @override
  Future<List<String>> getStringList(String key) async =>
      (values[key] as List<String>?) ?? <String>[];
  @override
  Future<bool> containsKey(String key) async => values.containsKey(key);
  @override
  Future<void> remove(String key) async => values.remove(key);
  @override
  Future<void> setBool(String key, bool value) async => values[key] = value;
  @override
  Future<void> setDouble(String key, double value) async => values[key] = value;
  @override
  Future<void> setInt(String key, int value) async => values[key] = value;
  @override
  Future<void> setString(String key, String value) async => values[key] = value;
  @override
  Future<void> setStringList(String key, List<String> value) async =>
      values[key] = value;
  @override
  Future<void> clear({Set<String>? allowList}) async => values.clear();
  @override
  Future<Set<String>> getKeys({Set<String>? allowList}) async => values.keys.toSet();
  @override
  Future<Map<String, Object?>> getAll({Set<String>? allowList}) async =>
      Map<String, Object?>.from(values);
  // ignore: annotate_overrides
  Future<void> reload() async {}
}

class _ThrowingPreferences extends _MemoryPreferences {
  Never _fail() => throw StateError('offline storage');
  @override
  Future<bool?> getBool(String key) async => _fail();
  @override
  Future<int> getInt(String key) async => _fail();
  @override
  Future<String?> getString(String key) async => _fail();
  @override
  Future<bool> containsKey(String key) async => _fail();
  @override
  Future<void> setBool(String key, bool value) async => _fail();
  @override
  Future<void> setInt(String key, int value) async => _fail();
  @override
  Future<void> setString(String key, String value) async => _fail();
}
