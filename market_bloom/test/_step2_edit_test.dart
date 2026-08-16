import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/game/game_controller.dart';
import 'package:pomarket/game/game_models.dart';
import 'package:pomarket/services/game_storage.dart';
import 'package:pomarket/services/monetization_service.dart';
import 'package:pomarket/ui/market_painter.dart';

void main() {
  test('player in front of shelf sorts after the foreground lip', () {
    final row = MarketDepthModel.shelfRows[1];
    final resolved = MarketDepthModel.resolveShelfKeepOut(
      Offset(.35, row),
      interacting: true,
    );
    expect(
      MarketDepthModel.shelfRelationship(resolved),
      ShelfVisualRelationship.front,
    );

    final entries = <WorldDepthEntry>[
      WorldDepthEntry(
        id: 'player',
        anchorY: resolved.dy,
        plane: WorldRenderPlane.mobileEntity,
        stableOrder: 3,
      ),
      WorldDepthEntry(
        id: 'shelf-body',
        anchorY: row,
        plane: WorldRenderPlane.fixture,
        stableOrder: 1,
      ),
      WorldDepthEntry(
        id: 'shelf-lip',
        anchorY: row + MarketDepthModel.shelfForegroundOffset,
        plane: WorldRenderPlane.foregroundFixture,
        stableOrder: 2,
      ),
    ]..sort(WorldDepthEntry.compare);
    expect(entries.map((entry) => entry.id), <String>[
      'shelf-body',
      'shelf-lip',
      'player',
    ]);
  });

  test('customer behind shelf is occluded while beside shelf stays clear', () {
    final row = MarketDepthModel.shelfRows.first;
    final behind = MarketDepthModel.resolveShelfKeepOut(
      Offset(.30, row - .01),
      interacting: false,
    );
    expect(
      MarketDepthModel.shelfRelationship(behind),
      ShelfVisualRelationship.behind,
    );
    expect(behind.dy, lessThan(row));

    const beside = Offset(.72, .455);
    expect(
      MarketDepthModel.resolveShelfKeepOut(beside, interacting: false),
      beside,
    );
    expect(
      MarketDepthModel.shelfRelationship(beside),
      ShelfVisualRelationship.beside,
    );
  });

  test('cashier and paying customer remain between checkout rear and front', () {
    const station = Offset(.80, .50);
    final rear = MarketDepthModel.checkoutRearDepth(station);
    final cashier = station.dy + MarketDepthModel.cashierDepthOffset;
    final payingCustomer =
        station.dy + MarketDepthModel.payingCustomerDepthOffset;
    final front = MarketDepthModel.checkoutFrontDepth(station);

    expect(rear, lessThan(cashier));
    expect(cashier, lessThan(front));
    expect(rear, lessThan(payingCustomer));
    expect(payingCustomer, lessThan(front));
    expect(MarketDepthModel.queueStartDepth, greaterThan(front));
  });

  test('storage characters remain between rear bay and foreground rail', () {
    expect(
      MarketDepthModel.storageRearDepth,
      lessThan(MarketDepthModel.storageWorkerDepth),
    );
    expect(
      MarketDepthModel.storageWorkerDepth,
      lessThan(MarketDepthModel.storageInteractionDepth),
    );
    expect(MarketDepthModel.storageInteractionDepth, lessThan(.965));
  });

  test('bakery interaction is between rear counter and foreground front', () {
    expect(
      MarketDepthModel.bakeryRearDepth,
      lessThan(MarketDepthModel.bakeryWorkerDepth),
    );
    expect(
      MarketDepthModel.bakeryWorkerDepth,
      lessThan(MarketDepthModel.bakeryInteractionDepth),
    );
    expect(
      MarketDepthModel.bakeryInteractionDepth,
      lessThan(MarketDepthModel.bakeryForegroundDepth),
    );
  });

  test('equal contact points have deterministic plane and stable ordering', () {
    const source = <WorldDepthEntry>[
      WorldDepthEntry(
        id: 'front',
        anchorY: .60,
        plane: WorldRenderPlane.foregroundFixture,
        stableOrder: 4,
      ),
      WorldDepthEntry(
        id: 'actor',
        anchorY: .60,
        plane: WorldRenderPlane.mobileEntity,
        stableOrder: 3,
      ),
      WorldDepthEntry(
        id: 'fixture-b',
        anchorY: .60,
        plane: WorldRenderPlane.fixture,
        stableOrder: 2,
      ),
      WorldDepthEntry(
        id: 'fixture-a',
        anchorY: .60,
        plane: WorldRenderPlane.fixture,
        stableOrder: 1,
      ),
    ];
    final forward = source.toList()..sort(WorldDepthEntry.compare);
    final reversed = source.reversed.toList()..sort(WorldDepthEntry.compare);
    expect(forward.map((entry) => entry.id), reversed.map((entry) => entry.id));
    expect(forward.map((entry) => entry.id), <String>[
      'fixture-a',
      'fixture-b',
      'actor',
      'front',
    ]);
  });

  for (final size in _targetSizes) {
    testWidgets('grounded depth world has no render exception or overflow at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final game = GameController(
        storage: MemoryGameStorage(),
        monetization: PreviewMonetizationService(),
      );
      await game.initialize();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
              child: CustomPaint(painter: _painter(game)),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is CustomPaint && widget.painter is MarketPainter,
        ),
        findsOneWidget,
      );
    });
  }
}

const _targetSizes = <Size>[
  Size(320, 568),
  Size(390, 844),
  Size(768, 700),
  Size(1024, 768),
  Size(1280, 800),
];

MarketPainter _painter(GameController game) => MarketPainter(
  game: game,
  storageLabel: 'STORAGE',
  shelfLabel: 'GENERAL GOODS',
  checkoutLabel: 'CHECKOUT',
  bakeryLabel: 'BAKERY',
  bakeryReadyLabel: 'READY',
  bakeryLockedLabel: 'LEVEL 3',
  departmentLabels: const <DepartmentType, String>{
    DepartmentType.generalGoods: 'GENERAL GOODS',
    DepartmentType.bakery: 'BAKERY',
  },
  textDirection: TextDirection.ltr,
  reducedMotion: true,
);
