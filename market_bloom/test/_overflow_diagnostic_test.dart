import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/game/game_controller.dart';
import 'package:pomarket/services/app_localizations.dart';
import 'package:pomarket/services/app_localizations_delegate.dart';
import 'package:pomarket/services/game_storage.dart';
import 'package:pomarket/services/monetization_service.dart';
import 'package:pomarket/ui/screens/achievements_screen.dart';
import 'package:pomarket/ui/screens/departments_screen.dart';
import 'package:pomarket/ui/screens/inventory_screen.dart';
import 'package:pomarket/ui/screens/quests_screen.dart';
import 'package:pomarket/ui/screens/shop_screen.dart';
import 'package:pomarket/ui/screens/staff_screen.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    binding.platformDispatcher.clearTextScaleFactorTestValue();
  });

  testWidgets('management cards stay responsive while scrolling', (
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
      final controller = GameController(
        storage: MemoryGameStorage(),
        monetization: PreviewMonetizationService(),
      );
      await controller.initialize();
      controller.debugSetProgress(sales: 200);
      controller.coins = 100000;
      await tester.pump(const Duration(milliseconds: 100));

      for (final screen in <Widget>[
        InventoryScreen(controller: controller),
        DepartmentsScreen(controller: controller),
        StaffScreen(controller: controller),
        ShopScreen(controller: controller),
        QuestsScreen(controller: controller),
        AchievementsScreen(controller: controller),
      ]) {
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
            home: screen,
          ),
        );
        await tester.pump();
        expect(
          tester.takeException(),
          isNull,
          reason: '${screen.runtimeType} initial ${layout.size}',
        );

        final scrollable = find.descendant(
          of: find.byWidget(screen),
          matching: find.byType(Scrollable),
        );
        if (scrollable.evaluate().isNotEmpty) {
          for (var index = 0; index < 20; index++) {
            await tester.drag(scrollable.first, const Offset(0, -350));
            await tester.pump();
            expect(
              tester.takeException(),
              isNull,
              reason:
                  '${screen.runtimeType} scroll $index ${layout.size} ${layout.locale.languageCode}',
            );
          }
        }
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    }

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
