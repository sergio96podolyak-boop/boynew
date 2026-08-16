import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/game/game_controller.dart';
import 'package:pomarket/game/game_models.dart';
import 'package:pomarket/services/game_storage.dart';
import 'package:pomarket/services/monetization_service.dart';
import 'package:pomarket/ui/market_art_assets.dart';
import 'package:pomarket/ui/market_painter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('phase 2 uses the five modular fixtures while retaining V3 art', () {
    final source = File('lib/ui/market_painter.dart').readAsStringSync();
    expect(MarketArtAssets.activeRuntimePaths, containsAll(MarketArtAssets.mainWorldModularPaths));
    expect(MarketArtAssets.activeRuntimePaths, containsAll(MarketArtAssets.mainWorldV2Paths));
    expect(_occurrences(source, 'path: MarketArtAssets.modularLongShelfPath'), 3);
    expect(_occurrences(source, 'path: MarketArtAssets.modularShortShelfPath'), 2);
    expect(_occurrences(source, 'path: MarketArtAssets.modularAlternateEndcapPath'), 2);
    expect(_occurrences(source, 'MarketArtAssets.modularCoolerBankPath'), 1);
    expect(_occurrences(source, 'MarketArtAssets.modularCheckoutRegisterPath'), 1);
  });

  test('render-only aisle model exposes three parallel shelf rows', () {
    expect(MarketDepthModel.shelfRows, <double>[.445, .535, .625]);
    final behind = MarketDepthModel.resolveShelfKeepOut(
      const Offset(.30, .535),
      interacting: false,
    );
    final front = MarketDepthModel.resolveShelfKeepOut(
      const Offset(.30, .535),
      interacting: true,
    );
    expect(behind.dy, lessThan(.535));
    expect(front.dy, greaterThan(.535));
  });

  testWidgets('modular world paints with two unlocked checkout stations', (tester) async {
    tester.view.physicalSize = const Size(390, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final game = GameController(
      storage: MemoryGameStorage(),
      monetization: PreviewMonetizationService(),
    );
    await game.initialize();
    game.coins = 10000;
    expect(game.buyUpgrade(UpgradeType.checkout), isTrue);
    expect(game.checkoutStations.where((station) => station.unlocked), hasLength(2));
    await MarketArtAssets.load();

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
  });
}

int _occurrences(String source, String pattern) => pattern.allMatches(source).length;

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
