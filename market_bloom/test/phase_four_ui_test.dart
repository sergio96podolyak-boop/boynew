import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/game/game_controller.dart';
import 'package:pomarket/services/app_localizations.dart';
import 'package:pomarket/services/app_localizations_delegate.dart';
import 'package:pomarket/services/game_storage.dart';
import 'package:pomarket/services/monetization_service.dart';
import 'package:pomarket/ui/screens/achievements_screen.dart';
import 'package:pomarket/ui/screens/quests_screen.dart';
import 'package:pomarket/ui/screens/shop_screen.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    binding.platformDispatcher.clearTextScaleFactorTestValue();
  });

  testWidgets('Phase 4 screens fit target responsive and RTL layouts', (
    tester,
  ) async {
    final layouts = <({Size size, Locale locale, double scale})>[
      (size: const Size(1280, 800), locale: const Locale('en'), scale: 1),
      (size: const Size(1024, 768), locale: const Locale('en'), scale: 1),
      (size: const Size(768, 700), locale: const Locale('he'), scale: 1.15),
      (size: const Size(390, 844), locale: const Locale('ar'), scale: 1.2),
      (size: const Size(320, 568), locale: const Locale('he'), scale: 1.3),
    ];

    for (final layout in layouts) {
      tester.view.physicalSize = layout.size;
      tester.view.devicePixelRatio = 1;
      binding.platformDispatcher.textScaleFactorTestValue = layout.scale;
      final controller = await _controller();

      for (final screen in <Widget>[
        ShopScreen(controller: controller),
        QuestsScreen(controller: controller),
        AchievementsScreen(controller: controller),
      ]) {
        await tester.pumpWidget(
          _localizedApp(locale: layout.locale, home: screen),
        );
        await tester.pump();
        expect(
          tester.takeException(),
          isNull,
          reason:
              '${screen.runtimeType} at ${layout.size} / ${layout.locale.languageCode}',
        );
      }
    }

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('Shop exposes categories, item states and disabled preview buys', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = await _controller();

    await tester.pumpWidget(
      _localizedApp(
        locale: const Locale('en'),
        home: ShopScreen(controller: controller),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('shop-item-noAds')), findsOneWidget);
    expect(find.byKey(const ValueKey('shop-item-coinPack')), findsOneWidget);
    expect(find.text('Permanent Benefits'), findsOneWidget);
    expect(find.text('Locked'), findsWidgets);

    final purchaseButtons = tester.widgetList<FilledButton>(
      find.descendant(
        of: find.byType(ShopScreen),
        matching: find.byType(FilledButton),
      ),
    );
    expect(purchaseButtons, isNotEmpty);
    expect(purchaseButtons.every((button) => button.onPressed == null), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Quests render progress, rewards and clear next actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(768, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = await _controller();

    await tester.pumpWidget(
      _localizedApp(
        locale: const Locale('en'),
        home: QuestsScreen(controller: controller),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('quest-card-shift')), findsOneWidget);
    expect(find.byKey(const ValueKey('quest-card-daily')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('quest-card-progression')),
      findsOneWidget,
    );
    expect(find.textContaining('Reward'), findsWidgets);
    expect(find.byType(LinearProgressIndicator), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Achievements render premium summary tiers and progression cards', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = await _controller();

    await tester.pumpWidget(
      _localizedApp(
        locale: const Locale('en'),
        home: AchievementsScreen(controller: controller),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('achievements-summary')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('achievement-card-first_sale')),
      findsOneWidget,
    );
    expect(find.text('Bronze'), findsWidgets);
    expect(find.text('Locked'), findsWidgets);
    expect(find.text('Next action'), findsWidgets);
    expect(find.textContaining('Badge'), findsWidgets);
    expect(find.byType(LinearProgressIndicator), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Phase 4 cards respect platform reduced motion', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = await _controller();

    await tester.pumpWidget(
      _localizedApp(
        locale: const Locale('en'),
        disableAnimations: true,
        home: AchievementsScreen(controller: controller),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('achievement-card-first_sale')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('achievements-summary')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<GameController> _controller() async {
  final controller = GameController(
    storage: MemoryGameStorage(),
    monetization: PreviewMonetizationService(),
  );
  await controller.initialize();
  return controller;
}

Widget _localizedApp({
  required Locale locale,
  required Widget home,
  bool disableAnimations = false,
}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      AppLocalizationsDelegate(),
    ],
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(disableAnimations: disableAnimations),
      child: child!,
    ),
    home: home,
  );
}
