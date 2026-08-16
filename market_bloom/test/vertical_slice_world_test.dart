import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/game/game_controller.dart';
import 'package:pomarket/game/game_models.dart';
import 'package:pomarket/services/game_storage.dart';
import 'package:pomarket/services/monetization_service.dart';
import 'package:pomarket/ui/market_art_assets.dart';
import 'package:pomarket/ui/vertical_slice_world_painter.dart';

void main() {
  test('vertical slice uses explicit coherent depth order', () {
    expect(VerticalSliceComposition.validDepthOrder, isTrue);
    expect(VerticalSliceComposition.layers, hasLength(9));
  });

  testWidgets('world geometry is derived only from the board canvas size', (
    tester,
  ) async {
    final game = GameController(
      storage: MemoryGameStorage(),
      monetization: PreviewMonetizationService(),
    );
    await game.initialize();
    final painter = VerticalSliceWorldPainter(
      game: game,
      storageLabel: 'Storage',
      shelfLabel: 'Shelf',
      checkoutLabel: 'Checkout',
      bakeryLabel: 'Bakery',
      bakeryReadyLabel: 'Ready',
      bakeryLockedLabel: 'Level 3',
      departmentLabels: const <DepartmentType, String>{
        DepartmentType.generalGoods: 'General',
      },
      textDirection: TextDirection.ltr,
      reducedMotion: true,
    );

    expect(
      painter.marketRect(const Size(320, 480)),
      const Rect.fromLTWH(8, 6, 304, 468),
    );
    expect(
      painter.marketRect(const Size(560, 700)),
      const Rect.fromLTWH(8, 6, 544, 688),
    );
  });

  test('active runtime manifest contains only renderable world assets', () {
    expect(MarketArtAssets.mainWorldV2Paths, hasLength(8));
    expect(MarketArtAssets.retainedEnvironmentPaths, hasLength(2));
    expect(MarketArtAssets.activeRuntimePaths, hasLength(25));
    expect(
      MarketArtAssets.activeRuntimePaths.toSet(),
      hasLength(MarketArtAssets.activeRuntimePaths.length),
    );
    expect(
      MarketArtAssets.activeRuntimePaths,
      isNot(contains(MarketArtAssets.mainShelfPath)),
    );
    expect(
      MarketArtAssets.activeRuntimePaths,
      isNot(contains(MarketArtAssets.entrancePath)),
    );
    for (final path in MarketArtAssets.commercialFixturePaths) {
      expect(MarketArtAssets.activeRuntimePaths, isNot(contains(path)));
    }
  });
}
