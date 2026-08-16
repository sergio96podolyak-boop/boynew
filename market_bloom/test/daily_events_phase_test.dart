import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/game/daily_event_game_controller.dart';
import 'package:pomarket/game/daily_event_models.dart';
import 'package:pomarket/game/game_models.dart';
import 'package:pomarket/services/app_settings.dart';
import 'package:pomarket/services/game_storage.dart';
import 'package:pomarket/services/monetization_service.dart';
import 'package:pomarket/ui/widgets/daily_event_banner.dart';

const _neutralEvent = DailyEventDefinition(
  id: 'neutral',
  type: MarketEventType.none,
  title: 'Neutral',
  description: 'Test baseline',
  effectSummary: 'No modifiers',
  modifiers: DailyEventModifiers(),
);

void main() {
  test('daily event rotation is deterministic by local calendar day', () {
    final first = DailyEventCatalog.forDate(DateTime(2026, 8, 14));
    final repeated = DailyEventCatalog.forDate(DateTime(2026, 8, 14, 23, 59));
    final next = DailyEventCatalog.forDate(DateTime(2026, 8, 15));

    expect(repeated.id, first.id);
    expect(next.id, isNot(first.id));
    expect(DailyEventCatalog.dateKey(DateTime(2026, 8, 14, 18)), '2026-08-14');
  });

  test('flash sale modifies existing price and customer cadence seams', () {
    const event = DailyEventDefinition(
      id: 'test_flash',
      type: MarketEventType.flashSale,
      title: 'Flash',
      description: 'Test',
      effectSummary: 'Test',
      modifiers: DailyEventModifiers(
        customerSpawnIntervalMultiplier: .5,
        salePriceMultiplier: 1.5,
      ),
    );
    final baseline = _controller(forcedEvent: _neutralEvent);
    final eventGame = _controller(forcedEvent: event);

    expect(eventGame.itemPrice, (baseline.itemPrice * 1.5).round());
    expect(
      eventGame.customerSpawnInterval,
      closeTo(baseline.customerSpawnInterval * .5, .001),
    );
    expect(eventGame.activeMarketEvent, MarketEventType.flashSale);
  });

  test('daily modifiers affect bakery delivery and department order cost', () async {
    const event = DailyEventDefinition(
      id: 'test_inspector',
      type: MarketEventType.inspectorVisit,
      title: 'Inspector',
      description: 'Test',
      effectSummary: 'Test',
      modifiers: DailyEventModifiers(
        bakeryProductionMultiplier: .5,
        deliveryDelayMultiplier: .5,
        stockOrderCostMultiplier: .5,
      ),
    );
    final baseline = _controller(forcedEvent: _neutralEvent);
    final eventGame = _controller(forcedEvent: event);
    await baseline.initialize();
    await eventGame.initialize();

    expect(
      eventGame.bakeryProductionSeconds,
      closeTo(baseline.bakeryProductionSeconds * .5, .001),
    );
    expect(
      eventGame.effectiveInventoryOrderDelay.inMilliseconds,
      (baseline.effectiveInventoryOrderDelay.inMilliseconds * .5).round(),
    );
    expect(
      eventGame.adjustedDepartmentOrderCost(DepartmentType.generalGoods),
      GameBalance.quickRestockCost ~/ 2,
    );

    eventGame.coins = 100;
    final delivery = eventGame.placeDepartmentOrder(DepartmentType.generalGoods);
    expect(delivery, isNotNull);
    expect(delivery!.cost, GameBalance.quickRestockCost ~/ 2);
    expect(eventGame.coins, 100 - GameBalance.quickRestockCost ~/ 2);
  });

  test('controller rolls to the next event after the calendar day changes', () {
    var now = DateTime(2026, 8, 14, 23, 59);
    final game = _controller(now: () => now);
    final first = game.dailyEvent.id;

    now = DateTime(2026, 8, 15);
    expect(game.refreshDailyEvent(), isTrue);
    expect(game.dailyEvent.id, isNot(first));
    expect(game.dailyEventDateKey, '2026-08-15');
    expect(game.refreshDailyEvent(), isFalse);
  });

  testWidgets('daily event banner is responsive RTL and reduced-motion safe', (
    tester,
  ) async {
    const layouts = <({Size size, TextDirection direction, bool compact})>[
      (size: Size(390, 844), direction: TextDirection.ltr, compact: false),
      (size: Size(320, 568), direction: TextDirection.rtl, compact: true),
    ];

    for (final layout in layouts) {
      tester.view.physicalSize = layout.size;
      tester.view.devicePixelRatio = 1;
      final game = _controller(forcedEvent: DailyEventCatalog.all.first);

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: Directionality(
              textDirection: layout.direction,
              child: child!,
            ),
          ),
          home: Scaffold(
            body: Column(
              children: [
                DailyEventBanner(
                  game: game,
                  settings: AppSettings(),
                  compact: layout.compact,
                ),
                const Expanded(child: ColoredBox(color: Colors.white)),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('daily-event-banner')), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '${layout.size}');
      await tester.pumpWidget(const SizedBox.shrink());
    }

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

DailyEventGameController _controller({
  DateTime Function()? now,
  DailyEventDefinition? forcedEvent,
}) {
  return DailyEventGameController(
    storage: MemoryGameStorage(),
    monetization: PreviewMonetizationService(),
    now: now,
    forcedEvent: forcedEvent,
  );
}
