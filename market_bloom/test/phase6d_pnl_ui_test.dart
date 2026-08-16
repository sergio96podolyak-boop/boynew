import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/game/game_models.dart';
import 'package:pomarket/services/app_localizations.dart';
import 'package:pomarket/services/app_localizations_delegate.dart';
import 'package:pomarket/ui/widgets/shift_pnl_summary.dart';

void main() {
  testWidgets('Shift Summary displays settled payroll and operating costs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final ledger = ShiftLedger(grossRevenue: 50, stockOrderCosts: 20)
      ..recordOperatingCost(5, type: ShiftOperatingCostType.payroll)
      ..recordOperatingCost(2);
    final summary = ShiftSummary(
      shiftNumber: 1,
      sales: 6,
      revenue: 50,
      missedSales: 0,
      satisfaction: 1,
      xp: 12,
      stockRemaining: 4,
      ledger: ledger,
    );

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
        home: Scaffold(
          body: ShiftPnlSummary(
            summary: summary,
            cashBalance: 123,
            onContinue: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    final scrollable = find.descendant(
      of: find.byType(ShiftPnlSummary),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('shift-pnl-payroll')),
      350,
      scrollable: scrollable,
    );
    await tester.pump();

    final payroll = find.byKey(const ValueKey('shift-pnl-payroll'));
    final operating = find.byKey(
      const ValueKey('shift-pnl-operating-costs'),
    );
    expect(find.descendant(of: payroll, matching: find.text('5')), findsOneWidget);
    expect(find.descendant(of: operating, matching: find.text('2')), findsOneWidget);
    expect(find.text('Not active'), findsNothing);
    expect(find.text('Net profit +23'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
