import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/game/game_controller.dart';
import 'package:pomarket/game/game_models.dart';
import 'package:pomarket/services/game_storage.dart';
import 'package:pomarket/services/monetization_service.dart';
import 'package:pomarket/ui/market_painter.dart';

void main() {
  test('Step 3 keeps the established depth contacts intact', () {
    expect(MarketDepthModel.shelfRows, const <double>[.445, .535, .625]);
    expect(MarketDepthModel.checkoutRearOffset, .055);
    expect(MarketDepthModel.checkoutForegroundOffset, .025);
    expect(MarketDepthModel.storageRearDepth, .875);
    expect(MarketDepthModel.bakeryRearDepth, .875);
    expect(MarketDepthModel.bakeryForegroundDepth, .935);
  });

  test('compact layouts reduce secondary fixture density only', () {
    expect(
      MarketWorldComposition.densityFor(320),
      lessThan(MarketWorldComposition.densityFor(390)),
    );
    expect(
      MarketWorldComposition.densityFor(390),
      lessThan(MarketWorldComposition.densityFor(768)),
    );
    for (final size in _targetSizes) {
      expect(MarketWorldComposition.supports(size), isTrue);
      final layout = MarketWorldLayout.forSize(size);
      expect(layout.mainAisle.overlaps(layout.crossAisle), isTrue);
      expect(layout.market.contains(layout.storage.bottomRight), isTrue);
      expect(layout.market.contains(layout.bakery.bottomRight), isTrue);
    }
  });

  for (final size in _targetSizes) {
    testWidgets('integrated fixture world paints cleanly at $size', (tester) async {
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
            body: SizedBox.expand(child: CustomPaint(painter: _painter(game))),
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
