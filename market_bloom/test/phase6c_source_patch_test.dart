import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/game/game_controller.dart';
import 'package:pomarket/game/game_models.dart';
import 'package:pomarket/services/app_localizations.dart';
import 'package:pomarket/services/app_localizations_delegate.dart';
import 'package:pomarket/services/app_settings.dart';
import 'package:pomarket/services/game_storage.dart';
import 'package:pomarket/services/monetization_service.dart';
import 'package:pomarket/ui/game_screen.dart';
import 'package:pomarket/ui/widgets/shift_pnl_summary.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(binding.platformDispatcher.clearTextScaleFactorTestValue);

  testWidgets('positive net profit is prominent with revenue and bonuses', (
    tester,
  ) async {
    _setSize(tester, const Size(390, 844));
    final summary = _summary(
      ledger: ShiftLedger(
        grossRevenue: 120,
        stockOrderCosts: 40,
        bonuses: 15,
        missedSalesEstimate: 9,
      ),
    );

    await tester.pumpWidget(_app(summary: summary, cashBalance: 430));
    await tester.pump();

    expect(find.text('Net profit +95'), findsOneWidget);
    expect(find.text('120'), findsWidgets);
    expect(find.text('15'), findsWidgets);
    expect(find.text('9'), findsWidgets);
    expect(find.textContaining('430 coins'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('negative net profit remains visible as a loss', (tester) async {
    _setSize(tester, const Size(390, 844));
    final summary = _summary(
      ledger: ShiftLedger(
        grossRevenue: 30,
        stockOrderCosts: 80,
        bonuses: 0,
      ),
    );

    await tester.pumpWidget(_app(summary: summary, cashBalance: 210));
    await tester.pump();

    expect(find.text('Net profit -50'), findsOneWidget);
    await _scrollTo(tester, find.byKey(const ValueKey('shift-pnl-insight')));
    expect(find.textContaining('recorded a loss'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('zero payroll and operating costs are explicitly inactive', (
    tester,
  ) async {
    _setSize(tester, const Size(390, 844));
    await tester.pumpWidget(
      _app(summary: _summary(ledger: ShiftLedger()), cashBalance: 100),
    );
    await tester.pump();

    await _scrollTo(tester, find.byKey(const ValueKey('shift-pnl-payroll')));
    expect(find.byKey(const ValueKey('shift-pnl-payroll')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('shift-pnl-operating-costs')),
      findsOneWidget,
    );
    expect(find.text('Not active'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('presentation never changes cash or ledger accounting', (
    tester,
  ) async {
    _setSize(tester, const Size(390, 844));
    final ledger = ShiftLedger(grossRevenue: 70, stockOrderCosts: 20);
    final summary = _summary(ledger: ledger);
    const cashBalance = 333;

    await tester.pumpWidget(_app(summary: summary, cashBalance: cashBalance));
    await tester.pump();

    expect(cashBalance, 333);
    expect(summary.ledger.grossRevenue, 70);
    expect(summary.ledger.stockOrderCosts, 20);
    expect(summary.ledger.netProfit, 50);
  });

  testWidgets('legacy empty ledger renders safe zero values', (tester) async {
    _setSize(tester, const Size(390, 844));
    final summary = ShiftSummary(
      shiftNumber: 4,
      sales: 3,
      revenue: 42,
      missedSales: 1,
      satisfaction: 0.8,
      xp: 8,
      stockRemaining: 5,
    );

    await tester.pumpWidget(_app(summary: summary, cashBalance: 77));
    await tester.pump();

    expect(find.text('Net profit 0'), findsOneWidget);
    expect(summary.ledger.netProfit, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('continue action has a keyboard focusable 48px target', (
    tester,
  ) async {
    _setSize(tester, const Size(320, 568));
    var continued = false;
    await tester.pumpWidget(
      _app(
        summary: _summary(ledger: ShiftLedger(grossRevenue: 20)),
        cashBalance: 20,
        onContinue: () => continued = true,
      ),
    );
    await tester.pump();

    final button = find.byKey(const ValueKey('shift-pnl-continue'));
    expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
    expect(find.descendant(of: button, matching: find.byType(Focus)), findsWidgets);
    await tester.tap(button);
    expect(continued, isTrue);
  });

  testWidgets('Shift P&L report fits responsive RTL and text scaling targets', (
    tester,
  ) async {
    final layouts = <({Size size, Locale locale, double scale})>[
      (size: const Size(1280, 800), locale: const Locale('en'), scale: 1),
      (size: const Size(1024, 768), locale: const Locale('en'), scale: 1),
      (size: const Size(768, 700), locale: const Locale('he'), scale: 1.15),
      (size: const Size(390, 844), locale: const Locale('he'), scale: 1.2),
      (size: const Size(320, 568), locale: const Locale('ar'), scale: 1.3),
    ];
    final summary = _summary(
      ledger: ShiftLedger(
        grossRevenue: 180,
        stockOrderCosts: 55,
        bonuses: 12,
        missedSalesEstimate: 24,
      ),
    );

    for (final layout in layouts) {
      tester.view.physicalSize = layout.size;
      tester.view.devicePixelRatio = 1;
      binding.platformDispatcher.textScaleFactorTestValue = layout.scale;
      await tester.pumpWidget(
        _app(
          summary: summary,
          cashBalance: 500,
          locale: layout.locale,
          disableAnimations: true,
        ),
      );
      await tester.pump();
      expect(find.byType(ShiftPnlSummary), findsOneWidget);
      expect(tester.takeException(), isNull);

      final scrollable = find.descendant(
        of: find.byType(ShiftPnlSummary),
        matching: find.byType(Scrollable),
      );
      await tester.fling(scrollable, const Offset(0, -2200), 1600);
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason:
            'Shift P&L overflow at ${layout.size} / ${layout.locale.languageCode} / ${layout.scale}x',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('completed GameScreen shift renders the new P&L summary', (
    tester,
  ) async {
    _setSize(tester, const Size(390, 844));
    final settings = AppSettings(preferences: _MemoryPreferences());
    await settings.load();
    final controller = GameController(
      storage: MemoryGameStorage(),
      monetization: PreviewMonetizationService(),
    );
    await controller.initialize();
    controller.onboardingComplete = true;
    controller.pendingDailyBonus = null;
    controller.pendingShiftSummary = _summary(
      ledger: ShiftLedger(grossRevenue: 90, stockOrderCosts: 20),
    );
    controller.paused = true;

    await tester.pumpWidget(
      _materialApp(
        locale: const Locale('en'),
        home: GameScreen(controller: controller, settings: settings),
      ),
    );
    await tester.pump();

    expect(find.byType(ShiftPnlSummary), findsOneWidget);
    expect(find.text('Net profit +70'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

ShiftSummary _summary({required ShiftLedger ledger}) => ShiftSummary(
  shiftNumber: 2,
  sales: 8,
  revenue: ledger.grossRevenue,
  missedSales: 2,
  satisfaction: 0.87,
  xp: 21,
  stockRemaining: 14,
  ledger: ledger,
);

Widget _app({
  required ShiftSummary summary,
  required int cashBalance,
  Locale locale = const Locale('en'),
  VoidCallback? onContinue,
  bool disableAnimations = false,
}) => _materialApp(
  locale: locale,
  disableAnimations: disableAnimations,
  home: Scaffold(
    body: ShiftPnlSummary(
      summary: summary,
      cashBalance: cashBalance,
      onContinue: onContinue ?? () {},
    ),
  ),
);

Widget _materialApp({
  required Locale locale,
  required Widget home,
  bool disableAnimations = false,
}) => MaterialApp(
  locale: locale,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    AppLocalizationsDelegate(),
  ],
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: disableAnimations),
    child: child!,
  ),
  home: home,
);

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    350,
    scrollable: find.descendant(
      of: find.byType(ShiftPnlSummary),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.pump();
}

void _setSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _MemoryPreferences implements SharedPreferencesAsync {
  final Map<String, Object> _values = <String, Object>{};

  @override
  Future<bool?> getBool(String key) async => _values[key] as bool?;
  @override
  Future<double> getDouble(String key) async => _values[key] as double? ?? 0;
  @override
  Future<int> getInt(String key) async => _values[key] as int? ?? 0;
  @override
  Future<String?> getString(String key) async => _values[key] as String?;
  @override
  Future<List<String>> getStringList(String key) async =>
      (_values[key] as List<String>?) ?? <String>[];
  @override
  Future<bool> containsKey(String key) async => _values.containsKey(key);
  @override
  Future<void> remove(String key) async => _values.remove(key);
  @override
  Future<void> setBool(String key, bool value) async => _values[key] = value;
  @override
  Future<void> setDouble(String key, double value) async => _values[key] = value;
  @override
  Future<void> setInt(String key, int value) async => _values[key] = value;
  @override
  Future<void> setString(String key, String value) async => _values[key] = value;
  @override
  Future<void> setStringList(String key, List<String> value) async =>
      _values[key] = value;
  @override
  Future<void> clear({Set<String>? allowList}) async => _values.clear();
  @override
  Future<Set<String>> getKeys({Set<String>? allowList}) async =>
      _values.keys.toSet();
  // ignore: annotate_overrides
  Future<void> reload() async {}
  @override
  Future<Map<String, Object?>> getAll({Set<String>? allowList}) async =>
      Map<String, Object?>.from(_values);
}
