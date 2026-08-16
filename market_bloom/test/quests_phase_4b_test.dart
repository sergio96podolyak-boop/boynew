import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/game/game_controller.dart';
import 'package:pomarket/services/app_localizations.dart';
import 'package:pomarket/services/app_localizations_delegate.dart';
import 'package:pomarket/services/game_storage.dart';
import 'package:pomarket/services/monetization_service.dart';
import 'package:pomarket/ui/screens/quests_screen.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    binding.platformDispatcher.clearTextScaleFactorTestValue();
  });

  testWidgets('Phase 4B quests fit all target layouts with RTL and scaling', (
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
          home: QuestsScreen(controller: controller),
        ),
      );
      await tester.pump();
      expect(find.byType(QuestsScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('quest-summary')), findsOneWidget);
      expect(tester.takeException(), isNull);

      final scrollable = find.descendant(
        of: find.byType(QuestsScreen),
        matching: find.byType(Scrollable),
      );
      await tester.fling(scrollable, const Offset(0, -1200), 1200);
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason:
            'Quests at ${layout.size} / ${layout.locale.languageCode} / ${layout.scale}x',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets(
    'available quests expose type title status progress reward and next action',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = await _controller();

      await tester.pumpWidget(
        _app(
          locale: const Locale('en'),
          home: QuestsScreen(controller: controller),
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('quest-summary')), findsOneWidget);
      expect(find.text('Mission overview'), findsOneWidget);
      expect(find.byKey(const ValueKey('quest-card-shift')), findsOneWidget);
      expect(find.byKey(const ValueKey('quest-card-daily')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('quest-card-progression')),
        findsOneWidget,
      );
      expect(find.text('SHIFT MISSION'), findsOneWidget);
      expect(find.text('DAILY MISSION'), findsOneWidget);
      expect(find.text('PROGRESSION MISSION'), findsOneWidget);
      expect(find.text('In progress'), findsWidgets);
      expect(find.text('Next action'), findsNWidgets(3));
      expect(find.byType(LinearProgressIndicator), findsNWidgets(3));
      expect(find.textContaining('Reward'), findsWidgets);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label == 'Quest progress',
          skipOffstage: false,
        ),
        findsNWidgets(3),
      );
      expect(find.byType(FocusTraversalGroup), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('uninitialized quests expose the locked state', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = GameController(
      storage: MemoryGameStorage(),
      monetization: PreviewMonetizationService(),
    );

    await tester.pumpWidget(
      _app(
        locale: const Locale('en'),
        home: QuestsScreen(controller: controller),
      ),
    );
    await tester.pump();

    expect(find.text('Locked'), findsNWidgets(6));
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'completed quest has subtle celebration keyboard CTA and 48px target',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = await _controller();
      controller.shiftSales = controller.shiftMissionTarget;

      await tester.pumpWidget(
        _app(
          locale: const Locale('en'),
          home: QuestsScreen(controller: controller),
        ),
      );
      await tester.pump();

      final shiftCard = find.byKey(const ValueKey('quest-card-shift'));
      final claimButton = find.descendant(
        of: shiftCard,
        matching: find.widgetWithText(FilledButton, 'Claim Reward'),
      );
      await tester.scrollUntilVisible(
        claimButton,
        250,
        scrollable: find.descendant(
          of: find.byType(QuestsScreen),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pump();

      expect(claimButton, findsOneWidget);
      expect(tester.getSize(claimButton).height, greaterThanOrEqualTo(44));
      expect(
        find.descendant(of: claimButton, matching: find.byType(Focus)),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: shiftCard,
          matching: find.text('Ready to claim'),
        ),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: shiftCard,
          matching: find.byIcon(Icons.auto_awesome_rounded),
        ),
        findsOneWidget,
      );

      final coinsBefore = controller.coins;
      await tester.tap(claimButton);
      await tester.pump(const Duration(milliseconds: 100));

      expect(controller.shiftMissionClaimed, isTrue);
      expect(controller.coins, coinsBefore + 20);
      expect(
        find.descendant(of: shiftCard, matching: find.text('Claimed')),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Phase 4B quests preserve reduced motion behavior', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = await _controller();
    controller.shiftSales = controller.shiftMissionTarget;

    await tester.pumpWidget(
      _app(
        locale: const Locale('he'),
        disableAnimations: true,
        home: QuestsScreen(controller: controller),
      ),
    );
    await tester.pump();

    expect(find.byType(QuestsScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('quest-summary')), findsOneWidget);
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
