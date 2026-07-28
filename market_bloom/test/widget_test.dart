import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/game/game_controller.dart';
import 'package:pomarket/main.dart';
import 'package:pomarket/services/game_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pomarket/services/app_settings.dart';
import 'package:pomarket/services/monetization_service.dart';
import 'package:pomarket/ui/game_screen.dart';
import 'package:pomarket/ui/screens/achievements_screen.dart';
import 'package:pomarket/ui/screens/departments_screen.dart';
import 'package:pomarket/ui/screens/inventory_screen.dart';
import 'package:pomarket/ui/screens/quests_screen.dart';
import 'package:pomarket/ui/screens/settings_screen.dart';
import 'package:pomarket/ui/screens/shop_screen.dart';
import 'package:pomarket/ui/screens/staff_screen.dart';
import 'package:pomarket/ui/screens/upgrades_screen.dart';
import 'package:pomarket/ui/splash_screen.dart';
import 'package:pomarket/ui/widgets/global_hud.dart';

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
    expect(find.text('Stock 5 products on the shelf'), findsOneWidget);

    final upgradesNavigation = find.widgetWithText(IconButton, 'Upgrades');
    expect(upgradesNavigation, findsOneWidget);
    await tester.tap(upgradesNavigation);
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

  testWidgets(
    'tutorial can be skipped, persisted, and replayed from Settings',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final storage = MemoryGameStorage();
      final controller = GameController(
        storage: storage,
        monetization: PreviewMonetizationService(),
      );
      await controller.initialize();
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

      await tester.tap(find.text('SKIP'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(controller.onboardingComplete, isTrue);
      await controller.save();

      final restored = GameController(
        storage: storage,
        monetization: PreviewMonetizationService(),
      );
      await restored.initialize();
      expect(restored.onboardingComplete, isTrue);

      await tester.tap(
        find.widgetWithIcon(IconButton, Icons.settings_rounded).last,
      );
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.byType(SettingsScreen), findsOneWidget);
      await tester.drag(
        find.descendant(
          of: find.byType(SettingsScreen),
          matching: find.byType(ListView),
        ),
        const Offset(0, -600),
      );
      await tester.pump(const Duration(milliseconds: 150));
      await tester.ensureVisible(find.text('REPLAY'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('REPLAY'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('WELCOME TO POMARKET'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Arabic Direct Touch tutorial is RTL and fits a compact phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
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

    await tester.pumpWidget(
      PoMarketApp(
        controller: controller,
        settings: settings,
        showSplash: false,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final tutorialTitle = find.text('تحرك واجمع');
    expect(tutorialTitle, findsOneWidget);
    expect(Directionality.of(tester.element(tutorialTitle)), TextDirection.rtl);
    expect(find.text('تخطي'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Shop and secondary destinations fit at 320 without purchases', (
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
    final startingCoins = controller.coins;
    final startingGems = controller.gems;

    await tester.pumpWidget(
      PoMarketApp(
        controller: controller,
        settings: _testSettings(),
        showSplash: false,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.text('Shop').last);
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Preview mode'), findsOneWidget);
    final shopButtons = tester.widgetList<FilledButton>(
      find.descendant(
        of: find.byType(ShopScreen),
        matching: find.byType(FilledButton),
      ),
    );
    expect(shopButtons, isNotEmpty);
    expect(shopButtons.every((button) => button.onPressed == null), isTrue);
    expect(controller.coins, startingCoins);
    expect(controller.gems, startingGems);

    await tester.tap(find.byTooltip('More'));
    await tester.pump(const Duration(milliseconds: 500));
    final moreSheet = find.byType(BottomSheet);
    expect(moreSheet, findsOneWidget);
    final staffDestination = find.descendant(
      of: moreSheet,
      matching: find.text('Staff'),
    );
    expect(staffDestination, findsOneWidget);
    await tester.ensureVisible(staffDestination);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(staffDestination);
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byType(StaffScreen), findsOneWidget);
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

  testWidgets('persistent HUD is singular and fits at 320 pixels wide', (
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

    expect(find.byType(GlobalHud), findsOneWidget);
    expect(find.text('HUB'), findsNothing);
    expect(find.text('Business Hub'), findsNothing);
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

    final rail = find.byType(NavigationRail);
    expect(rail, findsOneWidget);
    expect(
      find.descendant(of: rail, matching: find.text('Market')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: rail, matching: find.text('Upgrades')),
      findsOneWidget,
    );
    expect(Directionality.of(tester.element(rail)), TextDirection.ltr);
    expect(MaterialLocalizations.of(tester.element(rail)), isNotNull);
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

    final rail = find.byType(NavigationRail);
    expect(rail, findsOneWidget);
    expect(
      find.descendant(of: rail, matching: find.text('שוק')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: rail, matching: find.text('שדרוגים')),
      findsOneWidget,
    );
    expect(Directionality.of(tester.element(rail)), TextDirection.rtl);
    expect(MaterialLocalizations.of(tester.element(rail)), isNotNull);
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

    final rail = find.byType(NavigationRail);
    expect(rail, findsOneWidget);
    expect(
      find.descendant(of: rail, matching: find.text('السوق')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: rail, matching: find.text('التحديثات')),
      findsOneWidget,
    );
    expect(Directionality.of(tester.element(rail)), TextDirection.rtl);
    expect(MaterialLocalizations.of(tester.element(rail)), isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'every destination shares one controller and keeps the persistent HUD',
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
      controller.coins = 432;
      controller.gems = 9;

      await tester.pumpWidget(
        PoMarketApp(
          controller: controller,
          settings: _testSettings(),
          showSplash: false,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final rail = find.byType(NavigationRail);
      expect(find.byType(GlobalHud), findsOneWidget);
      expect(
        tester.widget<GameScreen>(find.byType(GameScreen)).controller,
        same(controller),
      );

      Future<void> open(String label) async {
        await tester.tap(find.descendant(of: rail, matching: find.text(label)));
        await tester.pump(const Duration(milliseconds: 120));
        expect(find.byType(GlobalHud), findsOneWidget);
        expect(find.text('432'), findsOneWidget);
        expect(find.text('9'), findsOneWidget);
      }

      await open('Upgrades');
      expect(
        tester.widget<UpgradesScreen>(find.byType(UpgradesScreen)).controller,
        same(controller),
      );
      await open('Staff');
      expect(
        tester.widget<StaffScreen>(find.byType(StaffScreen)).controller,
        same(controller),
      );
      await open('Departments');
      expect(
        tester
            .widget<DepartmentsScreen>(find.byType(DepartmentsScreen))
            .controller,
        same(controller),
      );
      await open('Inventory');
      expect(
        tester.widget<InventoryScreen>(find.byType(InventoryScreen)).controller,
        same(controller),
      );
      await open('Quests');
      expect(
        tester.widget<QuestsScreen>(find.byType(QuestsScreen)).controller,
        same(controller),
      );
      await open('Achievements');
      expect(
        tester
            .widget<AchievementsScreen>(find.byType(AchievementsScreen))
            .controller,
        same(controller),
      );
      await open('Shop');
      expect(
        tester.widget<ShopScreen>(find.byType(ShopScreen)).controller,
        same(controller),
      );
      await open('Settings');
      expect(
        tester.widget<SettingsScreen>(find.byType(SettingsScreen)).controller,
        same(controller),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Bakery unlock is reflected immediately across navigation', (
    tester,
  ) async {
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
    controller.debugSetProgress(sales: 8);

    await tester.pumpWidget(
      PoMarketApp(
        controller: controller,
        settings: _testSettings(),
        showSplash: false,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final rail = find.byType(NavigationRail);
    await tester.tap(
      find.descendant(of: rail, matching: find.text('Departments')),
    );
    await tester.pump(const Duration(milliseconds: 120));
    expect(controller.bakeryUnlocked, isFalse);
    expect(find.text('Unlocks at level 3'), findsOneWidget);

    controller.debugSetProgress(sales: 16);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(controller.bakeryUnlocked, isTrue);
    final bakeryCard = find.ancestor(
      of: find.text('Bakery'),
      matching: find.byType(Card),
    );
    expect(
      find.descendant(
        of: bakeryCard,
        matching: find.text('Unlocked · Level 1'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Bakery unlocked!'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
