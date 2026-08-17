import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/game/game_controller.dart';
import 'package:pomarket/services/app_localizations.dart';
import 'package:pomarket/services/app_localizations_delegate.dart';
import 'package:pomarket/services/game_storage.dart';
import 'package:pomarket/services/monetization_service.dart';
import 'package:pomarket/ui/screens/upgrades_screen.dart';
import 'package:pomarket/ui/widgets/management_ui.dart';
import 'package:pomarket/ui/theme/po_system.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    binding.platformDispatcher.clearTextScaleFactorTestValue();
  });

  testWidgets('final upgrades design fits responsive RTL and text scaling', (
    tester,
  ) async {
    const layouts = <({Size size, Locale locale, double scale})>[
      (size: Size(1280, 800), locale: Locale('en'), scale: 1),
      (size: Size(768, 700), locale: Locale('he'), scale: 1.15),
      (size: Size(390, 844), locale: Locale('ar'), scale: 1.2),
      (size: Size(320, 568), locale: Locale('en'), scale: 1.3),
    ];

    for (final layout in layouts) {
      tester.view.physicalSize = layout.size;
      tester.view.devicePixelRatio = 1;
      binding.platformDispatcher.textScaleFactorTestValue = layout.scale;
      final controller = GameController(
        storage: MemoryGameStorage(),
        monetization: PreviewMonetizationService(),
      );
      await controller.initialize();

      await tester.pumpWidget(
        MaterialApp(
          locale: layout.locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            AppLocalizationsDelegate(),
          ],
          home: UpgradesScreen(controller: controller),
        ),
      );
      await tester.pump();

      expect(find.byType(ManagementHero), findsOneWidget);
      final scrollable = find.byKey(const ValueKey('upgrades-scroll-view'));
      await tester.drag(scrollable, const Offset(0, -260));
      await tester.pump();
      expect(find.byKey(const ValueKey('upgrade-card-bag')), findsOneWidget);
      expect(find.byKey(const ValueKey('upgrade-buy-bag')), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '${layout.size}');
      await tester.pumpWidget(const SizedBox.shrink());
    }

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('upgrade disabled state explains the required next action', (
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
    controller.coins = 0;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          AppLocalizationsDelegate(),
        ],
        home: UpgradesScreen(controller: controller),
      ),
    );
    await tester.pump();
    await tester.drag(
      find.byKey(const ValueKey('upgrades-scroll-view')),
      const Offset(0, -260),
    );
    await tester.pump();

    expect(find.textContaining('more coins'), findsWidgets);
    final button = tester.widget<PoBtn>(
      find.byKey(const ValueKey('upgrade-buy-bag')),
    );
    expect(button.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
}
