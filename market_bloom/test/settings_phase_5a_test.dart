import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/game/game_controller.dart';
import 'package:pomarket/services/app_localizations.dart';
import 'package:pomarket/services/app_localizations_delegate.dart';
import 'package:pomarket/services/app_settings.dart';
import 'package:pomarket/services/game_storage.dart';
import 'package:pomarket/services/monetization_service.dart';
import 'package:pomarket/ui/screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(binding.platformDispatcher.clearTextScaleFactorTestValue);

  testWidgets('Phase 5A settings fit responsive RTL target layouts', (
    tester,
  ) async {
    final layouts = <({Size size, String language, double scale})>[
      (size: const Size(1280, 800), language: 'en', scale: 1),
      (size: const Size(1024, 768), language: 'en', scale: 1),
      (size: const Size(768, 700), language: 'he', scale: 1.15),
      (size: const Size(390, 844), language: 'he', scale: 1.2),
      (size: const Size(320, 568), language: 'ar', scale: 1.3),
    ];

    for (final layout in layouts) {
      tester.view.physicalSize = layout.size;
      tester.view.devicePixelRatio = 1;
      binding.platformDispatcher.textScaleFactorTestValue = layout.scale;
      final settings = await _settings(language: layout.language);
      final controller = await _controller();
      await tester.pumpWidget(_app(
        settings: settings,
        home: SettingsScreen(controller: controller, settings: settings),
      ));
      await tester.pump();

      expect(find.byKey(const ValueKey('settings-section-audio')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.fling(_scrollable(), const Offset(0, -4000), 1800);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('settings-section-about')), findsOneWidget);
      expect(
        tester.takeException(),
        isNull,
        reason:
            'Settings overflowed at ${layout.size}, ${layout.language}, ${layout.scale}x',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('settings expose only real existing sections and state', (
    tester,
  ) async {
    _phone(tester);
    final settings = await _settings();
    final controller = await _controller();
    await tester.pumpWidget(_app(
      settings: settings,
      home: SettingsScreen(controller: controller, settings: settings),
    ));
    await tester.pump();

    for (final key in <String>[
      'settings-section-audio',
      'settings-section-gameplay',
      'settings-section-preferences',
      'settings-section-data',
      'settings-section-about',
      'settings-sound-toggle',
      'settings-control-mode',
      'settings-language',
      'settings-reduced-motion-toggle',
      'settings-local-save',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('settings-section-privacy')), findsNothing);
    expect(find.textContaining('Cloud saves'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('existing audio gameplay language and motion behavior remains wired', (
    tester,
  ) async {
    _phone(tester);
    final preferences = _MemoryPreferences();
    final settings = AppSettings(preferences: preferences);
    await settings.load();
    final controller = await _controller();
    await tester.pumpWidget(_app(
      settings: settings,
      home: SettingsScreen(controller: controller, settings: settings),
    ));
    await tester.pump();

    final soundTile = find.byKey(const ValueKey('settings-sound-toggle'));
    await tester.tap(find.descendant(of: soundTile, matching: find.byType(Switch)));
    await tester.pump(const Duration(milliseconds: 200));
    expect(settings.soundEnabled, isFalse);
    expect(controller.muted, isTrue);
    expect(find.descendant(of: soundTile, matching: find.text('Muted')), findsOneWidget);

    final controlTile = find.byKey(const ValueKey('settings-control-mode'));
    await tester.ensureVisible(controlTile);
    await tester.pump();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Floating Joystick'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(settings.controlMode, ControlMode.joystick);

    final languageTile = find.byKey(const ValueKey('settings-language'));
    await tester.ensureVisible(languageTile);
    await tester.pump();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Hebrew'));
    await tester.pumpAndSettle();
    expect(settings.language?.languageCode, 'he');
    expect(await preferences.getString('pomarket.settings.language'), 'he');
    expect(
      Directionality.of(tester.element(find.byType(SettingsScreen))),
      TextDirection.rtl,
    );

    final motionTile = find.byKey(const ValueKey('settings-reduced-motion-toggle'));
    await tester.ensureVisible(motionTile);
    await tester.pump();
    await tester.tap(find.descendant(of: motionTile, matching: find.byType(Switch)));
    await tester.pump(const Duration(milliseconds: 200));
    expect(settings.reducedMotion, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('controls meet tap target focus semantics and reduced motion', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = await _settings();
    final controller = await _controller();
    await tester.pumpWidget(_app(
      settings: settings,
      disableAnimations: true,
      home: SettingsScreen(controller: controller, settings: settings),
    ));
    await tester.pump();

    final soundSwitch = find.descendant(
      of: find.byKey(const ValueKey('settings-sound-toggle')),
      matching: find.byType(Switch),
    );
    expect(tester.getSize(soundSwitch).height, greaterThanOrEqualTo(44));
    expect(find.descendant(of: soundSwitch, matching: find.byType(Focus)), findsWidgets);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('settings-sound-toggle'))).label,
      isNotEmpty,
    );
    expect(tester.takeException(), isNull);
  });
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Finder _scrollable() => find.descendant(
  of: find.byType(SettingsScreen),
  matching: find.byType(Scrollable),
);

Future<GameController> _controller() async {
  final controller = GameController(
    storage: MemoryGameStorage(),
    monetization: PreviewMonetizationService(),
  );
  await controller.initialize();
  return controller;
}

Future<AppSettings> _settings({String language = 'en'}) async {
  final settings = AppSettings(preferences: _MemoryPreferences());
  await settings.load();
  await settings.setLanguage(Locale(language));
  return settings;
}

Widget _app({
  required AppSettings settings,
  required Widget home,
  bool disableAnimations = false,
}) => AnimatedBuilder(
  animation: settings,
  builder: (context, _) => MaterialApp(
    locale: settings.language,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      AppLocalizationsDelegate(),
    ],
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: disableAnimations),
      child: child!,
    ),
    home: home,
  ),
);

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
  Future<void> setDouble(String key, double value) async => _values[key] = value;
  @override
  Future<void> setInt(String key, int value) async => _values[key] = value;
  @override
  Future<void> setString(String key, String value) async => _values[key] = value;
  @override
  Future<void> setStringList(String key, List<String> value) async => _values[key] = value;
  @override
  Future<void> clear({Set<String>? allowList}) async => _values.clear();
  @override
  Future<Set<String>> getKeys({Set<String>? allowList}) async => _values.keys.toSet();
  // ignore: annotate_overrides
  Future<void> reload() async {}
  @override
  Future<Map<String, Object?>> getAll({Set<String>? allowList}) async =>
      Map<String, Object?>.from(_values);
}
