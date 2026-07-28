import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/game/game_controller.dart';
import 'package:pomarket/main.dart';
import 'package:pomarket/services/game_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pomarket/services/app_settings.dart';
import 'package:pomarket/services/monetization_service.dart';
import 'package:pomarket/ui/splash_screen.dart';

AppSettings _testSettings() {
  return AppSettings(preferences: _MockSharedPrefs());
}

class _MockSharedPrefs implements SharedPreferencesAsync {
  final _store = <String, Object>{};

  @override
  Future<bool> getBool(String key) async => _store[key] as bool? ?? true;

  @override
  Future<double> getDouble(String key) async => _store[key] as double? ?? 0;

  @override
  Future<int> getInt(String key) async => _store[key] as int? ?? 0;

  @override
  Future<String> getString(String key) async => _store[key] as String? ?? '';

  @override
  Future<List<String>> getStringList(String key) async =>
      (_store[key] as List<String>?) ?? [];

  @override
  Future<bool> containsKey(String key) async => _store.containsKey(key);

  @override
  Future<void> remove(String key) async => _store.remove(key);

  @override
  Future<void> setBool(String key, bool value) async => _store[key] = value;

  @override
  Future<void> setDouble(String key, double value) async => _store[key] = value;

  @override
  Future<void> setInt(String key, int value) async => _store[key] = value;

  @override
  Future<void> setString(String key, String value) async => _store[key] = value;

  @override
  Future<void> setStringList(String key, List<String> value) async =>
      _store[key] = value;

  @override
  Future<void> clear({Set<String>? allowList}) async => _store.clear();

  @override
  Future<Set<String>> getKeys({Set<String>? allowList}) async =>
      _store.keys.toSet();

  // ignore: annotate_overrides
  Future<void> reload() async {}

  @override
  Future<Map<String, Object?>> getAll({Set<String>? allowList}) async =>
      Map.from(_store);
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    binding.platformDispatcher.localeTestValue = const Locale('en');
  });

  tearDown(() {
    binding.platformDispatcher.clearLocaleTestValue();
  });

  testWidgets('renders the playable market and opens upgrades', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = GameController(
      storage: MemoryGameStorage(),
      monetization: PreviewMonetizationService(),
    );
    await controller.initialize();
    controller.completeOnboarding();
    controller.acknowledgeDailyBonus();

    await tester.pumpWidget(
      PoMarketApp(
        controller: controller,
        settings: _testSettings(),
        showSplash: false,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('POMARKET'), findsOneWidget);
    expect(find.text('Your mini market'), findsOneWidget);
    expect(find.text('UPGRADES'), findsOneWidget);
    expect(find.text('Stock 5 products on the shelf'), findsOneWidget);

    await tester.tap(find.text('UPGRADES'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Upgrade Your Business'), findsOneWidget);
    expect(find.text('Bigger Bag'), findsOneWidget);
  });

  testWidgets('shows the branded opening screen before entering the game', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = GameController(
      storage: MemoryGameStorage(),
      monetization: PreviewMonetizationService(),
    );
    await controller.initialize();

    await tester.pumpWidget(
      PoMarketApp(
        controller: controller,
        settings: _testSettings(),
        splashDuration: Duration.zero,
      ),
    );
    await tester.pump();

    expect(find.text('PoMarket'), findsOneWidget);
    expect(find.text('BUILD. STOCK. GROW.'), findsOneWidget);
    expect(find.text('OPENING YOUR STORE'), findsOneWidget);
  });

  testWidgets('renders PoMarket brand after splash', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = GameController(
      storage: MemoryGameStorage(),
      monetization: PreviewMonetizationService(),
    );
    await controller.initialize();
    controller.completeOnboarding();
    controller.acknowledgeDailyBonus();

    await tester.pumpWidget(
      PoMarketApp(
        controller: controller,
        settings: _testSettings(),
        showSplash: false,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('POMARKET'), findsOneWidget);
    expect(find.text('Your mini market'), findsOneWidget);
  });

  testWidgets('waits for startup readiness and completes exactly once', (
    tester,
  ) async {
    final readiness = Completer<void>();
    var completions = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: PoMarketSplash(
          minimumDuration: const Duration(milliseconds: 40),
          readiness: readiness.future,
          onComplete: () => completions++,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(completions, 0);

    readiness.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(completions, 1);
  });

  testWidgets('fits the branded opening screen on a compact phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: PoMarketSplash(
          minimumDuration: const Duration(seconds: 1),
          onComplete: () {},
        ),
      ),
    );

    expect(find.text('PoMarket'), findsOneWidget);
    expect(find.text('BUILD. STOCK. GROW.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('first visit tutorial fits a compact phone', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = GameController(
      storage: MemoryGameStorage(),
      monetization: PreviewMonetizationService(),
    );
    await controller.initialize();

    await tester.pumpWidget(
      PoMarketApp(
        controller: controller,
        settings: _testSettings(),
        showSplash: false,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('WELCOME TO POMARKET'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('GOT IT \u2014 NEXT'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.text('Keep Shelves Full'), findsOneWidget);
    await tester.tap(find.text('GOT IT \u2014 NEXT'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.text('Sell, Earn & Grow'), findsOneWidget);
    expect(find.text('START PLAYING'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('daily bonus fits a compact phone', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = GameController(
      storage: MemoryGameStorage(),
      monetization: PreviewMonetizationService(),
    );
    await controller.initialize();
    controller.completeOnboarding();

    await tester.pumpWidget(
      PoMarketApp(
        controller: controller,
        settings: _testSettings(),
        showSplash: false,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('DAILY BONUS'), findsOneWidget);
    expect(find.text('1 DAY STREAK!'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('business hub is thumb-friendly at 320 pixels wide', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = GameController(
      storage: MemoryGameStorage(),
      monetization: PreviewMonetizationService(),
    );
    await controller.initialize();
    controller.completeOnboarding();
    controller.acknowledgeDailyBonus();

    await tester.pumpWidget(
      PoMarketApp(
        controller: controller,
        settings: _testSettings(),
        showSplash: false,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('HUB'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Business Hub'), findsOneWidget);
    expect(find.text('ACHIEVEMENTS'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final tabs = DefaultTabController.of(
      tester.element(find.text('Business Hub')),
    );
    tabs.animateTo(1, duration: Duration.zero);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('PLAY TIME'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'NavigationRail renders with MaterialLocalizations on wide viewports',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = GameController(
        storage: MemoryGameStorage(),
        monetization: PreviewMonetizationService(),
      );
      await controller.initialize();
      controller.completeOnboarding();
      controller.acknowledgeDailyBonus();

      await tester.pumpWidget(
        PoMarketApp(
          controller: controller,
          settings: _testSettings(),
          showSplash: false,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(
        MaterialLocalizations.of(tester.element(find.byType(NavigationRail))),
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('NavigationRail renders with MaterialLocalizations in English', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final settings = AppSettings(preferences: _MockSharedPrefs());
    await settings.load();
    await settings.setLanguage(const Locale('en'));

    final controller = GameController(
      storage: MemoryGameStorage(),
      monetization: PreviewMonetizationService(),
    );
    await controller.initialize();
    controller.completeOnboarding();
    controller.acknowledgeDailyBonus();

    await tester.pumpWidget(
      PoMarketApp(
        controller: controller,
        settings: settings,
        showSplash: false,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('Market'), findsOneWidget);
    expect(find.text('Upgrades'), findsOneWidget);
    expect(
      MaterialLocalizations.of(tester.element(find.byType(NavigationRail))),
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('NavigationRail renders with MaterialLocalizations in Hebrew', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final settings = AppSettings(preferences: _MockSharedPrefs());
    await settings.load();
    await settings.setLanguage(const Locale('he'));

    final controller = GameController(
      storage: MemoryGameStorage(),
      monetization: PreviewMonetizationService(),
    );
    await controller.initialize();
    controller.completeOnboarding();
    controller.acknowledgeDailyBonus();

    await tester.pumpWidget(
      PoMarketApp(
        controller: controller,
        settings: settings,
        showSplash: false,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('שוק'), findsOneWidget);
    expect(find.text('שדרוגים'), findsOneWidget);
    expect(
      MaterialLocalizations.of(tester.element(find.byType(NavigationRail))),
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('NavigationRail renders with MaterialLocalizations in Arabic', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final settings = AppSettings(preferences: _MockSharedPrefs());
    await settings.load();
    await settings.setLanguage(const Locale('ar'));

    final controller = GameController(
      storage: MemoryGameStorage(),
      monetization: PreviewMonetizationService(),
    );
    await controller.initialize();
    controller.completeOnboarding();
    controller.acknowledgeDailyBonus();

    await tester.pumpWidget(
      PoMarketApp(
        controller: controller,
        settings: settings,
        showSplash: false,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('السوق'), findsOneWidget);
    expect(find.text('التحديثات'), findsOneWidget);
    expect(
      MaterialLocalizations.of(tester.element(find.byType(NavigationRail))),
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });
}
