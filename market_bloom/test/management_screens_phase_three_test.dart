import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/game/economy_calculator.dart';
import 'package:pomarket/game/game_controller.dart';
import 'package:pomarket/game/game_models.dart';
import 'package:pomarket/services/app_localizations.dart';
import 'package:pomarket/services/app_localizations_delegate.dart';
import 'package:pomarket/services/game_storage.dart';
import 'package:pomarket/services/monetization_service.dart';
import 'package:pomarket/ui/screens/departments_screen.dart';
import 'package:pomarket/ui/screens/inventory_screen.dart';
import 'package:pomarket/ui/screens/staff_screen.dart';
import 'package:pomarket/ui/theme/po_system.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    binding.platformDispatcher.localeTestValue = const Locale('en');
  });

  tearDown(() {
    binding.platformDispatcher.clearLocaleTestValue();
    binding.platformDispatcher.clearTextScaleFactorTestValue();
  });

  testWidgets(
    'phase three management screens fit desktop tablet mobile and RTL',
    (tester) async {
      final layouts = <({Size size, Locale locale, double textScale})>[
        (size: const Size(1366, 900), locale: const Locale('en'), textScale: 1),
        (size: const Size(1024, 768), locale: const Locale('en'), textScale: 1),
        (size: const Size(768, 700), locale: const Locale('he'), textScale: 1.15),
        (size: const Size(390, 844), locale: const Locale('he'), textScale: 1.3),
      ];

      for (final layout in layouts) {
        tester.view.physicalSize = layout.size;
        tester.view.devicePixelRatio = 1;
        binding.platformDispatcher.textScaleFactorTestValue = layout.textScale;

        final controller = await _controller();
        for (final screen in <Widget>[
          InventoryScreen(controller: controller),
          DepartmentsScreen(controller: controller),
          StaffScreen(controller: controller),
        ]) {
          await tester.pumpWidget(_app(locale: layout.locale, home: screen));
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
    },
  );

  testWidgets('inventory exposes real cost profit margin demand and reorder', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(768, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = await _controller();
    controller.coins = 500;
    final definition = DepartmentCatalog.find(DepartmentType.generalGoods)!;
    final sellingPrice = controller.departmentItemPrice(definition.type);
    final expectedProfit = EconomyCalculator.estimatedProfitPerItem(
      definition,
      sellingPrice: sellingPrice,
    );
    final expectedMargin = EconomyCalculator.grossMargin(
      definition,
      sellingPrice: sellingPrice,
    );

    await tester.pumpWidget(
      _app(
        locale: const Locale('en'),
        home: InventoryScreen(controller: controller),
      ),
    );
    await tester.pump();

    final card = find.byKey(const ValueKey('inventory-card-generalGoods'));
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.text('Buy cost')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('Value')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('$expectedProfit')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: card,
        matching: find.text('${(expectedMargin * 100).round()}%'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('Demand')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.byType(PoBtn)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('departments show unlock and upgrade impact without legacy profit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = await _controller();
    controller.coins = 5000;

    await tester.pumpWidget(
      _app(
        locale: const Locale('en'),
        home: DepartmentsScreen(controller: controller),
      ),
    );
    await tester.pump();

    final general = find.byKey(
      const ValueKey('department-card-generalGoods'),
    );
    expect(general, findsOneWidget);
    expect(
      find.descendant(of: general, matching: find.text('Order revenue')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: general, matching: find.text('Order profit')),
      findsOneWidget,
    );
    expect(find.textContaining('Next upgrade:'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('department-card-electronics')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('staff cards communicate available working and locked states', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = await _controller();
    controller.debugSetProgress(sales: 48);
    controller.coins = 5000;
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.hireStaff(StaffRole.cashier), isTrue);
    await tester.pump(const Duration(milliseconds: 600));

    await tester.pumpWidget(
      _app(locale: const Locale('en'), home: StaffScreen(controller: controller)),
    );
    await tester.pump();

    final cashier = find.byKey(const ValueKey('staff-card-cashier'));
    final stocker = find.byKey(const ValueKey('staff-card-stocker'));
    expect(cashier, findsOneWidget);
    expect(stocker, findsOneWidget);
    expect(
      find.descendant(of: cashier, matching: find.text('Productivity')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cashier, matching: find.text('Station')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: stocker, matching: find.text('Available')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('management interactions respect reduced motion media setting', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = await _controller();
    controller.debugSetProgress(sales: 48);
    controller.coins = 5000;
    await tester.pump(const Duration(milliseconds: 100));

    await tester.pumpWidget(
      _app(
        locale: const Locale('en'),
        disableAnimations: true,
        home: StaffScreen(controller: controller),
      ),
    );
    await tester.pump();

    final stocker = find.byKey(const ValueKey('staff-card-stocker'));
    await tester.scrollUntilVisible(
      stocker,
      400,
      scrollable: find.descendant(
        of: find.byType(StaffScreen),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pump();
    final hire = find.descendant(
      of: stocker,
      matching: find.widgetWithText(PoBtn, 'Hire — 90'),
    );
    expect(hire, findsOneWidget);
    await tester.tap(hire);
    await tester.pump(const Duration(milliseconds: 600));
    expect(controller.isStaffHired(StaffRole.stocker), isTrue);
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
    builder: (context, child) {
      final media = MediaQuery.of(context);
      return MediaQuery(
        data: media.copyWith(disableAnimations: disableAnimations),
        child: child!,
      );
    },
    home: home,
  );
}
