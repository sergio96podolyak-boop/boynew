import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/game/game_controller.dart';
import 'package:pomarket/game/meta_models.dart';
import 'package:pomarket/services/app_localizations.dart';
import 'package:pomarket/services/app_localizations_delegate.dart';
import 'package:pomarket/services/game_storage.dart';
import 'package:pomarket/services/monetization_service.dart';
import 'package:pomarket/ui/screens/achievements_screen.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    binding.platformDispatcher.clearTextScaleFactorTestValue();
  });

  testWidgets('Phase 4C achievements fit responsive RTL target layouts', (
    tester,
  ) async {
    final layouts = <({Size size, Locale locale, double scale})>[
      (size: const Size(1280, 800), locale: const Locale('en'), scale: 1),
      (size: const Size(1024, 768), locale: const Locale('en'), scale: 1),
      (size: const Size(768, 700), locale: const Locale('he'), scale: 1.15),
      (size: const Size(390, 844), locale: const Locale('he'), scale: 1.2),
      (size: const Size(320, 568), locale: const Locale('ar'), scale: 1.3),
    ];

    for (final layout in layouts) {
      tester.view.physicalSize = layout.size;
      tester.view.devicePixelRatio = 1;
      binding.platformDispatcher.textScaleFactorTestValue = layout.scale;
      final controller = await _controller();

      await tester.pumpWidget(
        _app(
          locale: layout.locale,
          home: AchievementsScreen(controller: controller),
        ),
      );
      await tester.pump();

      expect(find.byType(AchievementsScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('achievements-summary')), findsOneWidget);
      expect(tester.takeException(), isNull);

      final scrollable = _scrollable();
      await tester.fling(scrollable, const Offset(0, -1800), 1400);
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason:
            'Achievements at ${layout.size} / ${layout.locale.languageCode} / ${layout.scale}x',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('achievement collection exposes tiers cards rewards and actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(768, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = await _controller();

    await tester.pumpWidget(
      _app(
        locale: const Locale('en'),
        home: AchievementsScreen(controller: controller),
      ),
    );
    await tester.pump();

    expect(find.text('Bronze'), findsWidgets);
    expect(
      find.byKey(const ValueKey('achievement-card-first_sale')),
      findsOneWidget,
    );
    expect(find.textContaining('Badge'), findsWidgets);
    expect(find.text('Next action'), findsWidgets);
    expect(find.byType(LinearProgressIndicator), findsWidgets);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Achievement progress',
      ),
      findsWidgets,
    );

    await tester.fling(_scrollable(), const Offset(0, -4000), 1800);
    await tester.pumpAndSettle();

    expect(find.text('Platinum'), findsWidgets);
    expect(
      find.byKey(const ValueKey('achievement-card-market_mogul')),
      findsOneWidget,
    );
    expect(find.textContaining('Badge'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('locked available and completed states remain distinct', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = await _controller();
    controller.stockedTotal = 5;
    controller.debugSetProgress(sales: 1);
    controller.debugReconcileState();

    expect(
      controller.progressFor(AchievementCatalog.find('first_sale')!).isUnlocked,
      isTrue,
    );
    expect(
      controller
          .progressFor(AchievementCatalog.find('shelf_starter')!)
          .currentValue,
      5,
    );

    await tester.pumpWidget(
      _app(
        locale: const Locale('en'),
        home: AchievementsScreen(controller: controller),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final completedCard = find.byKey(
      const ValueKey('achievement-card-first_sale'),
    );
    final availableCard = find.byKey(
      const ValueKey('achievement-card-shelf_starter'),
    );

    expect(
      find.descendant(of: completedCard, matching: find.text('Completed')),
      findsWidgets,
    );
    expect(
      find.descendant(of: availableCard, matching: find.text('In progress')),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: completedCard,
        matching: find.byIcon(Icons.auto_awesome_rounded),
      ),
      findsWidgets,
    );
    expect(tester.getSize(completedCard).height, greaterThanOrEqualTo(44));
    expect(
      find.descendant(of: completedCard, matching: find.byType(Focus)),
      findsWidgets,
    );

    await tester.fling(_scrollable(), const Offset(0, -2300), 1600);
    await tester.pumpAndSettle();
    final lockedCard = find.byKey(
      const ValueKey('achievement-card-upgrade_pro'),
    );
    expect(lockedCard, findsOneWidget);
    expect(
      find.descendant(of: lockedCard, matching: find.text('Locked')),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Phase 4C achievements respect reduced motion', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = await _controller();
    controller.debugSetProgress(sales: 1);
    controller.debugReconcileState();

    await tester.pumpWidget(
      _app(
        locale: const Locale('he'),
        disableAnimations: true,
        home: AchievementsScreen(controller: controller),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(AchievementsScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('achievements-summary')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Finder _scrollable() => find.descendant(
  of: find.byType(AchievementsScreen),
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

Widget _app({
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
