import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/game/game_controller.dart';
import 'package:pomarket/services/app_localizations.dart';
import 'package:pomarket/services/app_localizations_delegate.dart';
import 'package:pomarket/services/game_storage.dart';
import 'package:pomarket/services/monetization_service.dart';
import 'package:pomarket/ui/screens/departments_screen.dart';

void main() {
  testWidgets('Departments shows net per-item profit after stock cost', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = GameController(
      storage: MemoryGameStorage(),
      monetization: PreviewMonetizationService(),
    );
    await controller.initialize();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          AppLocalizationsDelegate(),
        ],
        home: DepartmentsScreen(controller: controller),
      ),
    );
    await tester.pump();

    // General Goods sells for 6; an order of 6 costs 20, so the conservative
    // whole-coin profit shown per item is floor((36 - 20) / 6) = 2.
    final card = find.byKey(const ValueKey('department-card-generalGoods'));
    expect(find.descendant(of: card, matching: find.text('Profit')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('2')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('6')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
