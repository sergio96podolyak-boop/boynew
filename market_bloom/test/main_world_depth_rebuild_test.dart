import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/game/game_controller.dart';
import 'package:pomarket/game/game_models.dart';
import 'package:pomarket/services/game_storage.dart';
import 'package:pomarket/services/monetization_service.dart';
import 'package:pomarket/ui/market_painter.dart';

void main() {
  test('character behind and in front of shelf sort physically', () {
    final shelfY = MarketWorldProjection.depthFor(GameController.shelfZone);
    final entries = <WorldDepthEntry>[
      WorldDepthEntry(
        id: 'character-front',
        anchorY: MarketWorldProjection.depthFor(
          GameController.shelfZone + const Offset(0, .05),
        ),
        plane: WorldRenderPlane.mobileEntity,
        stableOrder: 1,
      ),
      WorldDepthEntry(
        id: 'shelf',
        anchorY: shelfY,
        plane: WorldRenderPlane.fixture,
        stableOrder: 1,
      ),
      WorldDepthEntry(
        id: 'character-behind',
        anchorY: MarketWorldProjection.depthFor(
          GameController.shelfZone - const Offset(0, .05),
        ),
        plane: WorldRenderPlane.mobileEntity,
        stableOrder: 1,
      ),
    ]..sort(WorldDepthEntry.compare);
    expect(entries.map((entry) => entry.id), <String>[
      'character-behind',
      'shelf',
      'character-front',
    ]);
  });

  test('foreground shelf lip can mask equal-depth entities deterministically', () {
    const source = <WorldDepthEntry>[
      WorldDepthEntry(
        id: 'shelf-body',
        anchorY: .55,
        plane: WorldRenderPlane.fixture,
        stableOrder: 1,
      ),
      WorldDepthEntry(
        id: 'character',
        anchorY: .55,
        plane: WorldRenderPlane.mobileEntity,
        stableOrder: 2,
      ),
      WorldDepthEntry(
        id: 'shelf-lip',
        anchorY: .55,
        plane: WorldRenderPlane.foregroundFixture,
        stableOrder: 3,
      ),
    ];
    final sorted = source.toList()..sort(WorldDepthEntry.compare);
    expect(sorted.map((entry) => entry.id), <String>[
      'shelf-body',
      'character',
      'shelf-lip',
    ]);
  });

  test('checkout and storage use the same contact-point rule', () {
    final checkout = WorldDepthEntry(
      id: 'checkout',
      anchorY: MarketWorldProjection.depthFor(GameController.checkoutZone),
      plane: WorldRenderPlane.fixture,
      stableOrder: 1,
    );
    final cashier = WorldDepthEntry(
      id: 'cashier',
      anchorY: MarketWorldProjection.depthFor(
        GameController.checkoutZone + const Offset(0, .035),
      ),
      plane: WorldRenderPlane.mobileEntity,
      stableOrder: 2,
    );
    final storage = WorldDepthEntry(
      id: 'storage',
      anchorY: MarketWorldProjection.depthFor(GameController.stockZone),
      plane: WorldRenderPlane.fixture,
      stableOrder: 1,
    );
    final stockerBehind = WorldDepthEntry(
      id: 'stocker-behind',
      anchorY: MarketWorldProjection.depthFor(
        GameController.stockZone - const Offset(0, .04),
      ),
      plane: WorldRenderPlane.mobileEntity,
      stableOrder: 2,
    );
    expect(WorldDepthEntry.compare(checkout, cashier), lessThan(0));
    expect(WorldDepthEntry.compare(stockerBehind, storage), lessThan(0));
  });

  test('equal-depth ordering is stable across input order', () {
    const source = <WorldDepthEntry>[
      WorldDepthEntry(
        id: 'foreground',
        anchorY: .5,
        plane: WorldRenderPlane.foregroundFixture,
        stableOrder: 4,
      ),
      WorldDepthEntry(
        id: 'character',
        anchorY: .5,
        plane: WorldRenderPlane.mobileEntity,
        stableOrder: 3,
      ),
      WorldDepthEntry(
        id: 'fixture-b',
        anchorY: .5,
        plane: WorldRenderPlane.fixture,
        stableOrder: 2,
      ),
      WorldDepthEntry(
        id: 'fixture-a',
        anchorY: .5,
        plane: WorldRenderPlane.fixture,
        stableOrder: 1,
      ),
    ];
    final first = source.toList()..sort(WorldDepthEntry.compare);
    final second = source.reversed.toList()..sort(WorldDepthEntry.compare);
    expect(first.map((entry) => entry.id), second.map((entry) => entry.id));
    expect(first.map((entry) => entry.id), <String>[
      'fixture-a',
      'fixture-b',
      'character',
      'foreground',
    ]);
  });

  test('responsive floor plan retains connected departments', () {
    for (final size in _targetSizes) {
      expect(MarketWorldComposition.supports(size), isTrue, reason: '$size');
      expect(
        MarketWorldComposition.scaleFor(size),
        inInclusiveRange(.48, 1.08),
      );
      final layout = MarketWorldLayout.forSize(size);
      for (final region in MarketFloorRegion.values) {
        expect(layout.region(region).width, greaterThan(0), reason: '$size');
        expect(layout.region(region).height, greaterThan(0), reason: '$size');
      }
      expect(layout.wall.bottom, lessThanOrEqualTo(layout.welcome.top));
      expect(layout.storage.top, equals(layout.bakery.top));
      expect(layout.storage.right, equals(layout.bakery.left));
      expect(layout.mainAisle.overlaps(layout.crossAisle), isTrue);
      expect(layout.market.contains(layout.storage.bottomRight), isTrue);
      expect(layout.market.contains(layout.bakery.bottomRight), isTrue);
    }
    expect(
      MarketWorldComposition.densityFor(320),
      lessThan(MarketWorldComposition.densityFor(390)),
    );
    expect(
      MarketWorldComposition.densityFor(390),
      lessThan(MarketWorldComposition.densityFor(768)),
    );
  });

  test('projection preserves front-to-back department order', () {
    final entrance = MarketWorldProjection.visualPosition(GameController.entrance);
    final checkout = MarketWorldProjection.visualPosition(GameController.checkoutZone);
    final shelf = MarketWorldProjection.visualPosition(GameController.shelfZone);
    final storage = MarketWorldProjection.visualPosition(GameController.stockZone);
    final bakery = MarketWorldProjection.visualPosition(GameController.bakeryZone);
    expect(entrance.dy, lessThan(checkout.dy));
    expect(checkout.dy, lessThan(shelf.dy));
    expect(shelf.dy, lessThan(storage.dy));
    expect((storage.dx - bakery.dx).abs(), greaterThan(.35));
  });

  test('MarketPainter is the declared active world renderer', () {
    expect(activeMarketWorldRenderer, 'MarketPainter');
  });

  for (final size in _targetSizes) {
    testWidgets('rebuilt world paints without overflow or render errors at $size', (
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
      expect(
        find.byWidgetPredicate(
          (widget) => widget is CustomPaint && widget.painter is MarketPainter,
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
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
