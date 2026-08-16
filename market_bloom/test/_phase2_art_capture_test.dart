import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/game/game_controller.dart';
import 'package:pomarket/game/game_models.dart';
import 'package:pomarket/services/game_storage.dart';
import 'package:pomarket/services/monetization_service.dart';
import 'package:pomarket/ui/market_art_assets.dart';
import 'package:pomarket/ui/market_painter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture phase 2 mobile art validation views', (tester) async {
    const size = Size(390, 650);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final game = GameController(
      storage: MemoryGameStorage(),
      monetization: PreviewMonetizationService(),
    );
    await game.initialize();
    game.coins = 10000;
    game.buyUpgrade(UpgradeType.checkout);
    await MarketArtAssets.load();

    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: ColoredBox(
          color: Colors.white,
          child: RepaintBoundary(
            key: boundaryKey,
            child: SizedBox.fromSize(
              size: size,
              child: CustomPaint(painter: _painter(game)),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final boundary = boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final output = Directory('artifacts/phase2_modular')..createSync(recursive: true);
    await _writePng(image, File('${output.path}/main_world.png'));

    final layout = MarketWorldLayout.forSize(size);
    await _writeCrop(
      image,
      layout.retail.inflate(8).intersect(Offset.zero & size),
      File('${output.path}/general_goods.png'),
    );
    await _writeCrop(
      image,
      layout.checkout.inflate(8).intersect(Offset.zero & size),
      File('${output.path}/checkout.png'),
    );
    image.dispose();
  });
}

Future<void> _writeCrop(ui.Image source, Rect sourceRect, File file) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final target = Rect.fromLTWH(0, 0, sourceRect.width, sourceRect.height);
  canvas.drawImageRect(source, sourceRect, target, Paint());
  final image = await recorder.endRecording().toImage(
    sourceRect.width.ceil(),
    sourceRect.height.ceil(),
  );
  await _writePng(image, file);
  image.dispose();
}

Future<void> _writePng(ui.Image image, File file) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  file.writeAsBytesSync(data!.buffer.asUint8List(), flush: true);
}

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
