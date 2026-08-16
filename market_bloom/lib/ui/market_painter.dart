import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../game/game_controller.dart';
import '../game/game_models.dart';
import 'market_art_assets.dart';
import 'vertical_slice_world_painter.dart';

const String activeMarketWorldRenderer = 'MarketPainter';

enum WorldRenderPlane { rearFixture, fixture, mobileEntity, foregroundFixture }

@immutable
class WorldDepthEntry {
  const WorldDepthEntry({
    required this.id,
    required this.anchorY,
    required this.plane,
    required this.stableOrder,
  });

  final String id;
  final double anchorY;
  final WorldRenderPlane plane;
  final int stableOrder;

  static int compare(WorldDepthEntry left, WorldDepthEntry right) {
    final depth = left.anchorY.compareTo(right.anchorY);
    if (depth != 0) return depth;
    final plane = left.plane.index.compareTo(right.plane.index);
    if (plane != 0) return plane;
    final stable = left.stableOrder.compareTo(right.stableOrder);
    return stable != 0 ? stable : left.id.compareTo(right.id);
  }
}

enum MarketFloorRegion { welcome, retail, checkout, storage, bakery }

/// Board-local visual floor plan. The rear service departments form the back
/// wall, the retail floor occupies the center, and the entrance opens at the
/// front edge of the store.
@immutable
class MarketWorldLayout {
  const MarketWorldLayout._({
    required this.market,
    required this.wall,
    required this.welcome,
    required this.retail,
    required this.checkout,
    required this.storage,
    required this.bakery,
    required this.mainAisle,
    required this.crossAisle,
    required this.entranceOpening,
    required this.checkoutOpening,
    required this.storageOpening,
    required this.bakeryOpening,
    required this.scale,
    required this.density,
  });

  factory MarketWorldLayout.forSize(Size size) {
    final market = Rect.fromLTWH(
      8,
      6,
      max(0, size.width - 16),
      max(0, size.height - 12),
    );
    final scale = MarketWorldComposition.scaleFor(market.size);
    final density = MarketWorldComposition.densityFor(market.width);
    Rect region(double left, double top, double right, double bottom) =>
        Rect.fromLTRB(
          market.left + market.width * left,
          market.top + market.height * top,
          market.left + market.width * right,
          market.top + market.height * bottom,
        );
    return MarketWorldLayout._(
      market: market,
      wall: region(0, 0, 1, .12),
      storage: region(.025, .12, .43, .32),
      bakery: region(.43, .12, .975, .32),
      retail: region(.025, .32, .70, .80),
      checkout: region(.70, .32, .975, .80),
      welcome: region(.08, .80, .92, .985),
      mainAisle: region(.59, .27, .715, .91),
      crossAisle: region(.025, .69, .975, .80),
      entranceOpening: region(.42, .80, .58, .985),
      checkoutOpening: region(.675, .48, .725, .79),
      storageOpening: region(.275, .29, .405, .35),
      bakeryOpening: region(.50, .29, .69, .35),
      scale: scale,
      density: density,
    );
  }

  final Rect market;
  final Rect wall;
  final Rect welcome;
  final Rect retail;
  final Rect checkout;
  final Rect storage;
  final Rect bakery;
  final Rect mainAisle;
  final Rect crossAisle;
  final Rect entranceOpening;
  final Rect checkoutOpening;
  final Rect storageOpening;
  final Rect bakeryOpening;
  final double scale;
  final double density;

  bool get compact => density < .74;

  Rect region(MarketFloorRegion region) => switch (region) {
    MarketFloorRegion.welcome => welcome,
    MarketFloorRegion.retail => retail,
    MarketFloorRegion.checkout => checkout,
    MarketFloorRegion.storage => storage,
    MarketFloorRegion.bakery => bakery,
  };
}

/// Compatibility projection used by depth diagnostics. The active painter adds
/// department-specific render-only placement without changing simulation data.
abstract final class MarketWorldProjection {
  static const floorTop = .205;
  static const floorBottom = .965;

  static Offset visualPosition(Offset gameplayPosition) {
    final x = (.055 + gameplayPosition.dx * .89).clamp(.055, .945);
    final sourceY = gameplayPosition.dy.clamp(0.0, 1.0);
    final y = sourceY < .20
        ? .205 + sourceY * .43
        : sourceY < .70
        ? .291 + (sourceY - .20) * .83
        : .706 + (sourceY - .70) * .83;
    return Offset(x, y.clamp(floorTop, floorBottom));
  }

  static double depthFor(Offset gameplayPosition) =>
      visualPosition(gameplayPosition).dy;
}

abstract final class MarketWorldComposition {
  static double densityFor(double width) => width <= 330
      ? .48
      : width <= 420
      ? .68
      : width <= 560
      ? .86
      : 1;

  static double scaleFor(Size size) =>
      min(size.width / 500, size.height / 470).clamp(.54, 1.08);

  static bool supports(Size size) => size.width >= 280 && size.height >= 300;
}

enum ShelfVisualRelationship { behind, front, beside }

enum MarketCharacterKind { player, customer, staff }

abstract final class MarketDepthModel {
  static const shelfRows = <double>[.445, .535, .625];
  static const shelfLeft = .075;
  static const shelfRight = .635;
  static const shelfHalfDepth = .028;
  static const shelfRearLaneOffset = .040;
  static const shelfFrontLaneOffset = .045;
  static const shelfForegroundOffset = .034;
  static const checkoutRearOffset = .055;
  static const checkoutForegroundOffset = .025;
  static const storageRearDepth = .875;
  static const bakeryRearDepth = .875;
  static const bakeryForegroundDepth = .935;
  static const cashierDepthOffset = -.018;
  static const payingCustomerDepthOffset = .018;
  static const queueStartDepth = .555;
  static const storageWorkerDepth = .89;
  static const storageInteractionDepth = .915;
  static const bakeryWorkerDepth = .89;
  static const bakeryInteractionDepth = .905;

  static ShelfVisualRelationship shelfRelationship(Offset visual) {
    if (visual.dx < shelfLeft || visual.dx > shelfRight) {
      return ShelfVisualRelationship.beside;
    }
    final row = nearestShelfRow(visual.dy);
    if ((visual.dy - row).abs() > shelfFrontLaneOffset + .0001) {
      return ShelfVisualRelationship.beside;
    }
    return visual.dy < row
        ? ShelfVisualRelationship.behind
        : ShelfVisualRelationship.front;
  }

  static double nearestShelfRow(double y) => shelfRows.reduce(
    (left, right) => (y - left).abs() <= (y - right).abs() ? left : right,
  );

  static Offset resolveShelfKeepOut(
    Offset visual, {
    required bool interacting,
  }) {
    if (visual.dx < shelfLeft || visual.dx > shelfRight) return visual;
    final row = nearestShelfRow(visual.dy);
    if ((visual.dy - row).abs() >= shelfHalfDepth) return visual;
    return Offset(
      visual.dx,
      interacting || visual.dy >= row
          ? row + shelfFrontLaneOffset
          : row - shelfRearLaneOffset,
    );
  }

  static double checkoutRearDepth(Offset station) =>
      station.dy - checkoutRearOffset;
  static double checkoutFrontDepth(Offset station) =>
      station.dy + checkoutForegroundOffset;
}

abstract final class MarketCharacterScale {
  static double heightFor(
    MarketCharacterKind kind,
    MarketWorldLayout layout,
  ) {
    final logicalHeight = switch (kind) {
      MarketCharacterKind.player => layout.compact ? 80.0 : 88.0,
      MarketCharacterKind.customer => layout.compact ? 72.0 : 80.0,
      MarketCharacterKind.staff => layout.compact ? 74.0 : 82.0,
    };
    return logicalHeight * layout.scale;
  }
}

class MarketPainter extends CustomPainter {
  MarketPainter({
    required this.game,
    required this.storageLabel,
    required this.shelfLabel,
    required this.checkoutLabel,
    required this.bakeryLabel,
    required this.bakeryReadyLabel,
    required this.bakeryLockedLabel,
    required this.departmentLabels,
    required this.textDirection,
    bool? reducedMotion,
  }) : _reducedMotionOverride = reducedMotion,
       super(
         repaint: Listenable.merge(<Listenable>[
           game.scene,
           MarketArtAssets.repaintNotifier,
         ]),
       ) {
    unawaited(MarketArtAssets.load());
  }

  final GameController game;
  final String storageLabel;
  final String shelfLabel;
  final String checkoutLabel;
  final String bakeryLabel;
  final String bakeryReadyLabel;
  final String bakeryLockedLabel;
  final Map<DepartmentType, String> departmentLabels;
  final TextDirection textDirection;
  final bool? _reducedMotionOverride;

  bool get _reducedMotion =>
      _reducedMotionOverride ?? VerticalSliceRenderSettings.reducedMotion;

  final Paint _paint = Paint()..isAntiAlias = true;
  final Paint _imagePaint = Paint()
    ..isAntiAlias = true
    ..filterQuality = FilterQuality.high;
  final Paint _shadowPaint = Paint()
    ..isAntiAlias = true
    ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 4);

  static const _forest = Color(0xFF245442);
  static const _deepForest = Color(0xFF12362C);
  static const _cream = Color(0xFFFFF4D8);
  static const _tileLight = Color(0xFFF6E8CD);
  static const _tileDark = Color(0xFFE1C792);
  static const _checkoutRed = Color(0xFFA84E58);
  static const _storageBlue = Color(0xFF526A70);
  static const _bakeryGold = Color(0xFFD59739);
  static const _timber = Color(0xFF82543A);

  @override
  void paint(Canvas canvas, Size size) {
    if (game.pendingShiftSummary != null ||
        !MarketWorldComposition.supports(size)) {
      return;
    }
    final layout = MarketWorldLayout.forSize(size);
    final room = RRect.fromRectAndRadius(
      layout.market,
      Radius.circular(22 * layout.scale),
    );

    _paint
      ..shader = null
      ..style = PaintingStyle.fill
      ..color = const Color(0x3D20332A);
    canvas.drawRRect(room.shift(Offset(0, 7 * layout.scale)), _paint);

    canvas.save();
    canvas.clipRRect(room);
    _drawShell(canvas, layout);
    _drawFloor(canvas, layout);
    _drawRearDepartments(canvas, layout);
    _drawFrontEntranceArchitecture(canvas, layout);

    final scene = <_SceneItem>[];
    _addRearDepartmentFixtures(scene, canvas, layout);
    _addGeneralGoods(scene, canvas, layout);
    _addCheckout(scene, canvas, layout);
    _addEntrance(scene, canvas, layout);
    _addCharacters(scene, canvas, layout);
    scene.sort((left, right) => WorldDepthEntry.compare(left.depth, right.depth));
    for (final item in scene) {
      item.draw();
    }

    _drawForeground(canvas, layout);
    _drawAtmosphere(canvas, layout);
    _drawGameplayFeedback(canvas, layout);
    canvas.restore();

    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 * layout.scale
      ..color = _deepForest;
    canvas.drawRRect(room, _paint);
  }

  Offset _point(Rect rect, Offset normalized) => Offset(
    rect.left + rect.width * normalized.dx,
    rect.top + rect.height * normalized.dy,
  );

  void _add(
    List<_SceneItem> scene, {
    required String id,
    required double depth,
    required WorldRenderPlane plane,
    required int order,
    required VoidCallback draw,
  }) {
    scene.add(
      _SceneItem(
        WorldDepthEntry(
          id: id,
          anchorY: depth,
          plane: plane,
          stableOrder: order,
        ),
        draw,
      ),
    );
  }

  void _drawShell(Canvas canvas, MarketWorldLayout layout) {
    final market = layout.market;
    final scale = layout.scale;
    _paint.shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[Color(0xFFF7F0DD), Color(0xFFD9B576)],
    ).createShader(market);
    canvas.drawRect(market, _paint);
    _paint.shader = null;

    _paint.shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[Color(0xFFFFFEF8), Color(0xFFDBC498)],
    ).createShader(layout.wall);
    canvas.drawRect(layout.wall, _paint);
    _paint.shader = null;

    _paint.color = _deepForest;
    canvas.drawRect(
      Rect.fromLTWH(layout.wall.left, layout.wall.bottom - 7 * scale,
          layout.wall.width, 7 * scale),
      _paint,
    );
    canvas.drawRect(
      Rect.fromLTWH(market.left, layout.wall.bottom, 8 * scale, market.height),
      _paint,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        market.right - 8 * scale,
        layout.wall.bottom,
        8 * scale,
        market.height,
      ),
      _paint,
    );

    final sign = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: _point(market, const Offset(.50, .058)),
        width: min(market.width * .36, 174 * scale),
        height: 29 * scale,
      ),
      Radius.circular(9 * scale),
    );
    _paint.color = const Color(0x3520332A);
    canvas.drawRRect(sign.shift(Offset(0, 3 * scale)), _paint);
    _paint.shader = const LinearGradient(
      colors: <Color>[Color(0xFF3C7D5F), _forest],
    ).createShader(sign.outerRect);
    canvas.drawRRect(sign, _paint);
    _paint.shader = null;
    _paint.color = const Color(0xFFFFD56A);
    canvas.drawCircle(sign.center - Offset(55 * scale, 0), 5 * scale, _paint);
    _text(canvas, 'PoMARKET', sign.center + Offset(5 * scale, 0),
        12.5 * scale, Colors.white, FontWeight.w900);

    final lights = layout.compact
        ? const <double>[.16, .50, .84]
        : const <double>[.10, .30, .50, .70, .90];
    for (final x in lights) {
      final center = _point(market, Offset(x, .105));
      _paint.color = const Color(0xFFFFE6A4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: center, width: 28 * scale, height: 4 * scale),
          Radius.circular(2 * scale),
        ),
        _paint,
      );
    }
  }

  void _drawFloor(Canvas canvas, MarketWorldLayout layout) {
    final scale = layout.scale;
    final salesFloor = Rect.fromLTRB(
      layout.market.left,
      layout.storage.bottom,
      layout.market.right,
      layout.market.bottom,
    );
    _paint.shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[_tileLight, _tileDark],
    ).createShader(salesFloor);
    canvas.drawRect(salesFloor, _paint);
    _paint.shader = null;

    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = .5 * scale
      ..color = const Color(0x1E3D5149);
    final rows = layout.compact ? 10 : 15;
    for (var row = 1; row < rows; row++) {
      final t = row / rows;
      final y = salesFloor.top + salesFloor.height * pow(t, .86);
      canvas.drawLine(
        Offset(salesFloor.left + 7 * scale, y),
        Offset(salesFloor.right - 7 * scale, y),
        _paint,
      );
    }
    final columns = layout.compact ? 7 : 11;
    for (var column = 1; column < columns; column++) {
      final x = salesFloor.left + salesFloor.width * column / columns;
      canvas.drawLine(Offset(x, salesFloor.top), Offset(x, salesFloor.bottom), _paint);
    }

    // Wide, subtle circulation bands unify the store without reading as map
    // overlays or debug rectangles.
    _paint
      ..style = PaintingStyle.fill
      ..color = const Color(0x30FFF9EA);
    canvas.drawRRect(
      RRect.fromRectAndRadius(layout.mainAisle, Radius.circular(6 * scale)),
      _paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(layout.crossAisle, Radius.circular(6 * scale)),
      _paint,
    );

    final checkoutInset = layout.checkout.deflate(5 * scale);
    _paint.color = const Color(0x358D8B84);
    canvas.drawRRect(
      RRect.fromRectAndRadius(checkoutInset, Radius.circular(7 * scale)),
      _paint,
    );

    // Front apron makes the storefront read as the beginning of the journey.
    final apron = Rect.fromLTRB(
      layout.market.left,
      layout.welcome.top,
      layout.market.right,
      layout.market.bottom,
    );
    _paint.shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[Color(0x00FFFFFF), Color(0x405C8D78)],
    ).createShader(apron);
    canvas.drawRect(apron, _paint);
    _paint.shader = null;
    final mat = Rect.fromCenter(
      center: _point(layout.market, const Offset(.50, .90)),
      width: layout.market.width * .22,
      height: 15 * scale,
    );
    _paint.color = const Color(0xC7346654);
    canvas.drawRRect(
      RRect.fromRectAndRadius(mat, Radius.circular(3 * scale)),
      _paint,
    );
  }

  void _drawRearDepartments(Canvas canvas, MarketWorldLayout layout) {
    final scale = layout.scale;
    final storage = layout.storage;
    final bakery = layout.bakery;

    _paint
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFB8BCB7);
    canvas.drawRect(storage, _paint);
    _paint.color = const Color(0xFFF0D49B);
    canvas.drawRect(bakery, _paint);

    // A single installed service facade joins both rear departments.
    final beamTop = storage.bottom - 8 * scale;
    _paint.color = const Color(0xFF40514C);
    canvas.drawRect(
      Rect.fromLTWH(layout.market.left, beamTop, layout.market.width, 10 * scale),
      _paint,
    );
    _paint.color = const Color(0xFF89958F);
    canvas.drawRect(
      Rect.fromLTWH(layout.market.left, beamTop, layout.market.width, 2 * scale),
      _paint,
    );
    _paint.color = const Color(0xFF40514C);
    canvas.drawRect(
      Rect.fromLTWH(storage.right - 3 * scale, storage.top, 6 * scale,
          storage.height),
      _paint,
    );

    _departmentPlaque(
      canvas,
      Offset(storage.left + storage.width * .20, storage.top + 12 * scale),
      storageLabel,
      _storageBlue,
      scale,
    );
    _departmentPlaque(
      canvas,
      Offset(bakery.right - bakery.width * .18, bakery.top + 12 * scale),
      game.bakeryUnlocked ? bakeryLabel : bakeryLockedLabel,
      _bakeryGold,
      scale,
    );

    _paint.color = const Color(0xFF596B66);
    for (final opening in <Rect>[layout.storageOpening, layout.bakeryOpening]) {
      canvas.drawRect(
        Rect.fromLTWH(opening.left - 3 * scale, beamTop, 3 * scale, 17 * scale),
        _paint,
      );
      canvas.drawRect(
        Rect.fromLTWH(opening.right, beamTop, 3 * scale, 17 * scale),
        _paint,
      );
    }
  }

  void _drawFrontEntranceArchitecture(Canvas canvas, MarketWorldLayout layout) {
    final scale = layout.scale;
    final opening = layout.entranceOpening;
    final y = opening.bottom - 8 * scale;
    _paint
      ..style = PaintingStyle.fill
      ..color = _deepForest;
    canvas.drawRect(
      Rect.fromLTWH(layout.market.left, y, opening.left - layout.market.left,
          8 * scale),
      _paint,
    );
    canvas.drawRect(
      Rect.fromLTWH(opening.right, y, layout.market.right - opening.right,
          8 * scale),
      _paint,
    );
    _paint.color = const Color(0xFF52766C);
    canvas.drawRect(
      Rect.fromLTWH(opening.left - 4 * scale, opening.top, 4 * scale,
          opening.height),
      _paint,
    );
    canvas.drawRect(
      Rect.fromLTWH(opening.right, opening.top, 4 * scale, opening.height),
      _paint,
    );
  }

  void _departmentPlaque(
    Canvas canvas,
    Offset center,
    String value,
    Color color,
    double scale,
  ) {
    final width = 66 * scale;
    final plaque = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: width, height: 15 * scale),
      Radius.circular(4 * scale),
    );
    _paint
      ..style = PaintingStyle.fill
      ..color = const Color(0x3020332A);
    canvas.drawRRect(plaque.shift(Offset(0, 2 * scale)), _paint);
    _paint.color = color;
    canvas.drawRRect(plaque, _paint);
    _text(canvas, value, center, 5.8 * scale, _cream, FontWeight.w900,
        maxWidth: width - 7 * scale);
  }

  void _addRearDepartmentFixtures(
    List<_SceneItem> scene,
    Canvas canvas,
    MarketWorldLayout layout,
  ) {
    final scale = layout.scale;
    _add(
      scene,
      id: 'storage-bay',
      depth: .295,
      plane: WorldRenderPlane.rearFixture,
      order: 10,
      draw: () => _drawSprite(
        canvas,
        MarketArtAssets.v2StoragePath,
        _point(layout.market, const Offset(.21, .305)),
        (layout.compact ? 100 : 121) * scale,
        maxWidth: layout.storage.width * .70,
        shadow: .20,
      ),
    );
    _add(
      scene,
      id: 'storage-boxes',
      depth: .325,
      plane: WorldRenderPlane.fixture,
      order: 11,
      draw: () => _drawSprite(
        canvas,
        MarketArtAssets.deliveryBoxesPath,
        _point(layout.market, const Offset(.375, .325)),
        (layout.compact ? 37 : 47) * scale,
        maxWidth: layout.storage.width * .22,
        shadow: .13,
      ),
    );
    _add(
      scene,
      id: 'bakery-backdrop',
      depth: .255,
      plane: WorldRenderPlane.rearFixture,
      order: 15,
      draw: () => _drawBakeryBackdrop(canvas, layout),
    );
    _add(
      scene,
      id: 'bakery-counter',
      depth: .34,
      plane: WorldRenderPlane.fixture,
      order: 17,
      draw: () {
        final ground = _point(layout.market, const Offset(.70, .35));
        _drawSprite(
          canvas,
          MarketArtAssets.v2BakeryPath,
          ground,
          (layout.compact ? 116 : 142) * scale,
          maxWidth: layout.bakery.width * .67,
          alpha: game.bakeryUnlocked ? 1 : .54,
          shadow: game.bakeryUnlocked ? .24 : .13,
        );
        if (!game.bakeryUnlocked) {
          _departmentPlaque(
            canvas,
            ground - Offset(0, 27 * scale),
            bakeryLockedLabel,
            const Color(0xFF675C50),
            scale,
          );
        }
      },
    );
  }

  void _drawBakeryBackdrop(Canvas canvas, MarketWorldLayout layout) {
    final scale = layout.scale;
    final rect = layout.bakery.deflate(10 * scale);
    final display = Rect.fromLTWH(
      rect.left,
      rect.top + 19 * scale,
      rect.width,
      max(24 * scale, rect.height - 31 * scale),
    );
    _paint
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFF7E7CA);
    canvas.drawRRect(
      RRect.fromRectAndRadius(display, Radius.circular(4 * scale)),
      _paint,
    );
    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2 * scale
      ..color = _timber;
    canvas.drawRRect(
      RRect.fromRectAndRadius(display, Radius.circular(4 * scale)),
      _paint,
    );

    final oven = Rect.fromLTWH(
      display.right - 44 * scale,
      display.top + 10 * scale,
      34 * scale,
      display.height - 17 * scale,
    );
    _paint
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF66534A);
    canvas.drawRRect(
      RRect.fromRectAndRadius(oven, Radius.circular(4 * scale)),
      _paint,
    );
    _paint.color = const Color(0xFF293432);
    canvas.drawRect(oven.deflate(6 * scale), _paint);

    for (var row = 0; row < 2; row++) {
      final shelf = Rect.fromCenter(
        center: Offset(
          display.left + display.width * .31,
          display.top + (17 + row * 15) * scale,
        ),
        width: min(display.width * .40, 68 * scale),
        height: 4 * scale,
      );
      _paint.color = _timber;
      canvas.drawRect(shelf, _paint);
      for (var item = 0; item < 4; item++) {
        _paint.color = const Color(0xFFD38C33);
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(
              shelf.left + shelf.width * (item + .5) / 4,
              shelf.top - 3 * scale,
            ),
            width: 10 * scale,
            height: 6 * scale,
          ),
          _paint,
        );
      }
    }
  }

  void _addGeneralGoods(
    List<_SceneItem> scene,
    Canvas canvas,
    MarketWorldLayout layout,
  ) {
    final scale = layout.scale;

    _add(
      scene,
      id: 'cooler-bank-modular',
      depth: .385,
      plane: WorldRenderPlane.rearFixture,
      order: 25,
      draw: () => _drawSprite(
        canvas,
        MarketArtAssets.modularCoolerBankPath,
        _point(layout.market, const Offset(.13, .395)),
        (layout.compact ? 91 : 111) * scale,
        maxWidth: layout.retail.width * .27,
        shadow: .19,
      ),
    );

    final shelfModules = <({
      String id,
      String path,
      double x,
      double y,
      double compactHeight,
      double regularHeight,
      double widthFraction,
    })>[
      (
        id: 'rear-long',
        path: MarketArtAssets.modularLongShelfPath,
        x: .31,
        y: .445,
        compactHeight: 78,
        regularHeight: 96,
        widthFraction: .43,
      ),
      (
        id: 'middle-short',
        path: MarketArtAssets.modularShortShelfPath,
        x: .205,
        y: .535,
        compactHeight: 70,
        regularHeight: 84,
        widthFraction: .22,
      ),
      (
        id: 'middle-long',
        path: MarketArtAssets.modularLongShelfPath,
        x: .455,
        y: .535,
        compactHeight: 76,
        regularHeight: 92,
        widthFraction: .36,
      ),
      (
        id: 'front-long',
        path: MarketArtAssets.modularLongShelfPath,
        x: .285,
        y: .625,
        compactHeight: 79,
        regularHeight: 97,
        widthFraction: .41,
      ),
      (
        id: 'front-short',
        path: MarketArtAssets.modularShortShelfPath,
        x: .535,
        y: .625,
        compactHeight: 69,
        regularHeight: 83,
        widthFraction: .21,
      ),
    ];

    for (var index = 0; index < shelfModules.length; index++) {
      final module = shelfModules[index];
      _add(
        scene,
        id: 'aisle-module-${module.id}',
        depth: module.y,
        plane: WorldRenderPlane.fixture,
        order: 30 + index * 2,
        draw: () => _drawSprite(
          canvas,
          module.path,
          _point(layout.market, Offset(module.x, module.y)),
          (layout.compact ? module.compactHeight : module.regularHeight) * scale,
          maxWidth: layout.retail.width * module.widthFraction,
          shadow: .20,
        ),
      );
    }

    final endcaps = <({
      String id,
      String path,
      double x,
      double y,
      double widthFraction,
    })>[
      (
        id: 'rear-right-standard',
        path: MarketArtAssets.v2PromoEndcapPath,
        x: .555,
        y: .449,
        widthFraction: .095,
      ),
      (
        id: 'middle-left-mirrored',
        path: MarketArtAssets.modularAlternateEndcapPath,
        x: .095,
        y: .539,
        widthFraction: .105,
      ),
      (
        id: 'front-right-mirrored',
        path: MarketArtAssets.modularAlternateEndcapPath,
        x: .625,
        y: .629,
        widthFraction: .105,
      ),
    ];

    for (var index = 0; index < endcaps.length; index++) {
      final endcap = endcaps[index];
      _add(
        scene,
        id: 'aisle-endcap-${endcap.id}',
        depth: endcap.y,
        plane: WorldRenderPlane.fixture,
        order: 50 + index,
        draw: () => _drawSprite(
          canvas,
          endcap.path,
          _point(layout.market, Offset(endcap.x, endcap.y)),
          (layout.compact ? 45 : 54) * scale,
          maxWidth: layout.retail.width * endcap.widthFraction,
          shadow: .15,
        ),
      );
    }
  }

  void _addCheckout(
    List<_SceneItem> scene,
    Canvas canvas,
    MarketWorldLayout layout,
  ) {
    final scale = layout.scale;
    _add(
      scene,
      id: 'checkout-wall',
      depth: .365,
      plane: WorldRenderPlane.rearFixture,
      order: 60,
      draw: () => _drawCheckoutWall(canvas, layout),
    );

    final unlocked = game.checkoutStations
        .where((station) => station.unlocked)
        .toList(growable: false);
    for (var index = 0; index < unlocked.length; index++) {
      final station = unlocked[index];
      final visual = _checkoutStationVisual(station.id);
      _add(
        scene,
        id: 'checkout-${station.id}',
        depth: visual.dy,
        plane: WorldRenderPlane.fixture,
        order: 64 + index,
        draw: () => _drawSprite(
          canvas,
          MarketArtAssets.modularCheckoutRegisterPath,
          _point(layout.market, visual),
          (station.id == GameController.primaryCheckoutStationId
                  ? (layout.compact ? 88 : 101)
                  : (layout.compact ? 78 : 90)) *
              scale,
          maxWidth: layout.checkout.width * .72,
          alpha: station.active ? 1 : .52,
          shadow: station.active ? .22 : .10,
        ),
      );
    }

    _add(
      scene,
      id: 'queue-approach',
      depth: .735,
      plane: WorldRenderPlane.rearFixture,
      order: 72,
      draw: () => _drawQueueApproach(canvas, layout),
    );
    _add(
      scene,
      id: 'basket-return',
      depth: .755,
      plane: WorldRenderPlane.fixture,
      order: 73,
      draw: () => _drawSprite(
        canvas,
        MarketArtAssets.v2CartBasketsPath,
        _point(layout.market, const Offset(.90, .755)),
        (layout.compact ? 31 : 39) * scale,
        maxWidth: layout.checkout.width * .29,
        shadow: .12,
      ),
    );
  }

  Offset _checkoutStationVisual(String id) => switch (id) {
    'checkout-2' => const Offset(.80, .565),
    'checkout-3' => const Offset(.82, .645),
    _ => const Offset(.82, .485),
  };

  void _drawCheckoutWall(Canvas canvas, MarketWorldLayout layout) {
    final scale = layout.scale;
    final wall = Rect.fromLTWH(
      layout.checkout.left + 6 * scale,
      layout.checkout.top + 7 * scale,
      layout.checkout.width - 12 * scale,
      31 * scale,
    );
    _paint
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFF7EADB);
    canvas.drawRRect(
      RRect.fromRectAndRadius(wall, Radius.circular(5 * scale)),
      _paint,
    );
    _paint.color = _checkoutRed;
    canvas.drawRect(
      Rect.fromLTWH(wall.left, wall.bottom - 6 * scale, wall.width, 6 * scale),
      _paint,
    );
    final count = layout.compact ? 2 : 3;
    for (var index = 0; index < count; index++) {
      final center = Offset(
        wall.left + wall.width * (index + .5) / count,
        wall.center.dy - 1 * scale,
      );
      _paint.color = _forest;
      canvas.drawCircle(center, 6.5 * scale, _paint);
      _text(canvas, '${index + 1}', center, 5.8 * scale, Colors.white,
          FontWeight.w900);
    }
  }

  void _drawQueueApproach(Canvas canvas, MarketWorldLayout layout) {
    final scale = layout.scale;
    final lane = Rect.fromLTRB(
      _point(layout.market, const Offset(.735, .55)).dx,
      _point(layout.market, const Offset(.5, .555)).dy,
      _point(layout.market, const Offset(.905, .55)).dx,
      _point(layout.market, const Offset(.5, .745)).dy,
    );
    _paint
      ..style = PaintingStyle.fill
      ..color = const Color(0x295F6D68);
    canvas.drawRRect(
      RRect.fromRectAndRadius(lane, Radius.circular(7 * scale)),
      _paint,
    );
    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 * scale
      ..color = const Color(0x42606B66);
    canvas.drawRRect(
      RRect.fromRectAndRadius(lane.deflate(3 * scale), Radius.circular(5 * scale)),
      _paint,
    );
  }

  void _addEntrance(
    List<_SceneItem> scene,
    Canvas canvas,
    MarketWorldLayout layout,
  ) {
    final scale = layout.scale;
    _add(
      scene,
      id: 'first-aisle-endcap',
      depth: .765,
      plane: WorldRenderPlane.fixture,
      order: 80,
      draw: () => _drawSprite(
        canvas,
        MarketArtAssets.v2PromoEndcapPath,
        _point(layout.market, const Offset(.36, .765)),
        (layout.compact ? 47 : 58) * scale,
        maxWidth: layout.market.width * .11,
        shadow: .15,
      ),
    );
    _add(
      scene,
      id: 'entrance-carts',
      depth: .875,
      plane: WorldRenderPlane.fixture,
      order: 82,
      draw: () => _drawSprite(
        canvas,
        MarketArtAssets.v2CartBasketsPath,
        _point(layout.market, const Offset(.19, .88)),
        (layout.compact ? 51 : 63) * scale,
        maxWidth: layout.market.width * .18,
        shadow: .14,
      ),
    );
    _add(
      scene,
      id: 'storefront-entrance',
      depth: .965,
      plane: WorldRenderPlane.foregroundFixture,
      order: 88,
      draw: () => _drawSprite(
        canvas,
        MarketArtAssets.v2EntrancePath,
        _point(layout.market, const Offset(.50, .975)),
        (layout.compact ? 112 : 136) * scale,
        maxWidth: layout.market.width * .34,
        shadow: .15,
      ),
    );
  }

  void _addCharacters(
    List<_SceneItem> scene,
    Canvas canvas,
    MarketWorldLayout layout,
  ) {
    for (var index = 0; index < game.customers.length; index++) {
      final customer = game.customers[index];
      final visual = _customerVisualPosition(customer);
      _add(
        scene,
        id: 'customer-${customer.id}',
        depth: visual.dy,
        plane: WorldRenderPlane.mobileEntity,
        order: 200 + index,
        draw: () => _drawCustomer(canvas, layout, customer, visual),
      );
    }

    var order = 300;
    for (final role in StaffRole.values) {
      if (!game.isStaffHired(role)) continue;
      for (var index = 0; index < game.staffWorkerCount(role); index++) {
        final gameplay = _staffGameplayPosition(role, index);
        if (gameplay == null) continue;
        final visual = _staffVisualPosition(role, gameplay, index);
        _add(
          scene,
          id: 'staff-${role.name}-$index',
          depth: visual.dy,
          plane: WorldRenderPlane.mobileEntity,
          order: order++,
          draw: () => _drawStaff(canvas, layout, role, visual),
        );
      }
    }

    final visual = _playerVisualPosition(game.playerPosition);
    _add(
      scene,
      id: 'player',
      depth: visual.dy,
      plane: WorldRenderPlane.mobileEntity,
      order: 999,
      draw: () => _drawPlayer(canvas, layout, visual),
    );
  }

  Offset _playerVisualPosition(Offset gameplay) {
    for (final station in game.checkoutStations) {
      if (station.unlocked &&
          (gameplay - game.checkoutStationZone(station.id)).distance <= .15) {
        return _checkoutStationVisual(station.id) + const Offset(.035, -.018);
      }
    }
    if ((gameplay - GameController.stockZone).distance <= .15 ||
        (gameplay - GameController.stockerPickupZone).distance <= .13) {
      return const Offset(.28, .30);
    }
    if ((gameplay - GameController.bakeryZone).distance <= .15) {
      return const Offset(.64, .36);
    }
    if ((gameplay - GameController.entrance).distance <= .15) {
      return const Offset(.50, .84);
    }
    return _openFloorPosition(gameplay, interacting: true);
  }

  Offset _customerVisualPosition(MarketCustomer customer) {
    if (customer.phase == CustomerPhase.checkout ||
        customer.phase == CustomerPhase.paying) {
      final stationId = customer.checkoutStationId ??
          GameController.primaryCheckoutStationId;
      final station = _checkoutStationVisual(stationId);
      final queue = game.checkoutQueueFor(stationId);
      final index = max(0, queue.indexOf(customer));
      if (customer.phase == CustomerPhase.paying) {
        return station + const Offset(-.045, .018);
      }
      return Offset(
        (station.dx - .055).clamp(.735, .86),
        (.575 + index * .052).clamp(.575, .745),
      );
    }
    if (customer.phase == CustomerPhase.entering) {
      final x = .46 + (customer.id.abs() % 3) * .035;
      return Offset(x, .84 - customer.phaseTime.clamp(0, 1) * .12);
    }
    if (customer.phase == CustomerPhase.leaving) {
      return Offset(.54, (.72 + customer.phaseTime * .12).clamp(.72, .91));
    }
    return _openFloorPosition(customer.position, interacting: false);
  }

  Offset _openFloorPosition(Offset gameplay, {required bool interacting}) {
    var visual = Offset(
      (.08 + gameplay.dx * .82).clamp(.08, .90),
      (.35 + gameplay.dy * .48).clamp(.35, .78),
    );
    const rows = MarketDepthModel.shelfRows;
    if (visual.dx <= .68) {
      final nearest = rows.reduce(
        (left, right) =>
            (visual.dy - left).abs() <= (visual.dy - right).abs()
                ? left
                : right,
      );
      if ((visual.dy - nearest).abs() < .029) {
        visual = Offset(
          visual.dx,
          interacting || visual.dy >= nearest ? nearest + .043 : nearest - .038,
        );
      }
    }
    return visual;
  }

  Offset _staffVisualPosition(StaffRole role, Offset gameplay, int index) {
    if (role == StaffRole.cashier) {
      final stations = game.checkoutStations
          .where((station) => station.unlocked && station.active)
          .toList(growable: false);
      final id = index < stations.length
          ? stations[index].id
          : GameController.primaryCheckoutStationId;
      return _checkoutStationVisual(id) + const Offset(.035, -.018);
    }
    return switch (role) {
      StaffRole.stocker => const Offset(.29, .31),
      StaffRole.baker => Offset(.62 + index * .035, .30),
      StaffRole.manager => Offset(.57 + index * .03, .36),
      StaffRole.promoter => Offset(.38 + index * .035, .76),
      StaffRole.cleaner => Offset(_openFloorPosition(gameplay,
              interacting: false)
          .dx, .72),
      _ => _openFloorPosition(gameplay, interacting: false),
    };
  }

  Offset? _staffGameplayPosition(StaffRole role, int index) {
    final offset = Offset((index % 2) * .025, index * .035);
    final status = game.staffStatus(role);
    final cleanerX = _reducedMotion
        ? .52
        : .52 + sin(game.totalPlaySeconds * .7) * .08;
    final courier = _reducedMotion
        ? const Offset(.29, .61)
        : Offset(
            .18 + ((sin(game.totalPlaySeconds * 1.1) + 1) / 2) * .24,
            .61 + cos(game.totalPlaySeconds * 1.1) * .03,
          );
    final base = switch (role) {
      StaffRole.cashier => _cashierGameplayPosition(index),
      StaffRole.stocker => game.stockerPosition,
      StaffRole.cleaner => Offset(cleanerX, .84),
      StaffRole.baker => GameController.bakeryZone + const Offset(-.13, -.01),
      StaffRole.manager => const Offset(.22, .25),
      StaffRole.courier => status == StaffStatus.delivering
          ? courier
          : const Offset(.29, .61),
      StaffRole.promoter => const Offset(.32, .18),
    };
    return base == null ? null : base + offset;
  }

  Offset? _cashierGameplayPosition(int index) {
    final stations = game.checkoutStations
        .where((station) => station.unlocked && station.active)
        .toList(growable: false);
    if (index >= stations.length) return null;
    return game.checkoutStationZone(stations[index].id) +
        const Offset(.075, .035);
  }

  void _drawCustomer(
    Canvas canvas,
    MarketWorldLayout layout,
    MarketCustomer customer,
    Offset visual,
  ) {
    final moving = customer.phase != CustomerPhase.paying &&
        !(customer.phase == CustomerPhase.shopping && customer.phaseTime > .66);
    final sway = _reducedMotion
        ? 0.0
        : sin(game.totalPlaySeconds * (moving ? 7.5 : 2.2) + customer.id);
    _drawSprite(
      canvas,
      MarketArtAssets.customerPaths[customer.id.abs() % 4],
      _point(layout.market, visual),
      MarketCharacterScale.heightFor(MarketCharacterKind.customer, layout),
      shadow: .21,
      rotation: moving ? sway * .008 : 0,
      tint: const Color(0xFFFFF3DD),
    );
  }

  void _drawStaff(
    Canvas canvas,
    MarketWorldLayout layout,
    StaffRole role,
    Offset visual,
  ) {
    _drawSprite(
      canvas,
      MarketArtAssets.staffPaths[role.index],
      _point(layout.market, visual),
      MarketCharacterScale.heightFor(MarketCharacterKind.staff, layout),
      shadow: .22,
      tint: role == StaffRole.baker
          ? const Color(0xFFFFE8BA)
          : const Color(0xFFF2FFF7),
    );
  }

  void _drawPlayer(Canvas canvas, MarketWorldLayout layout, Offset visual) {
    final walking = game.movement.distance > .05;
    final frame = game.carried > 0
        ? 3
        : !walking
        ? 0
        : _reducedMotion
        ? 1
        : 1 + ((game.totalPlaySeconds * 8).floor() % 2);
    _drawSprite(
      canvas,
      MarketArtAssets.playerPaths[frame],
      _point(layout.market, visual),
      MarketCharacterScale.heightFor(MarketCharacterKind.player, layout),
      shadow: .25,
      tint: const Color(0xFFFFEFD2),
    );
  }

  void _drawForeground(Canvas canvas, MarketWorldLayout layout) {
    final scale = layout.scale;
    _paint
      ..style = PaintingStyle.fill
      ..color = _deepForest;
    canvas.drawRect(
      Rect.fromLTWH(layout.market.left, layout.market.bottom - 6 * scale,
          layout.market.width, 6 * scale),
      _paint,
    );
  }

  void _drawAtmosphere(Canvas canvas, MarketWorldLayout layout) {
    _paint.shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[Color(0x12FFFFFF), Color(0x00000000)],
    ).createShader(
      Rect.fromLTWH(layout.market.left, layout.market.top, layout.market.width,
          layout.market.height * .52),
    );
    _paint.style = PaintingStyle.fill;
    canvas.drawRect(layout.market, _paint);
    _paint.shader = null;
  }

  void _drawGameplayFeedback(Canvas canvas, MarketWorldLayout layout) {
    for (final effect in game.floatingEffects) {
      _text(
        canvas,
        effect.text,
        _point(layout.market,
            _reducedMotion ? effect.position : effect.currentPosition),
        effect.fontSize * layout.scale,
        effect.color.withValues(alpha: effect.opacity),
        FontWeight.w900,
      );
    }
  }

  void _drawSprite(
    Canvas canvas,
    String path,
    Offset ground,
    double height, {
    double? maxWidth,
    double alpha = 1,
    double shadow = .16,
    double rotation = 0,
    Color tint = const Color(0xFFFFFBF3),
  }) {
    final image = MarketArtAssets.image(path);
    final source = MarketArtAssets.sourceRect(path);
    if (image == null || source == null || source.height <= 0) return;
    var factor = height / source.height;
    if (maxWidth != null && source.width * factor > maxWidth) {
      factor = maxWidth / source.width;
      height = source.height * factor;
    }
    final width = source.width * factor;

    _shadowPaint.color = const Color(0xFF20332B).withValues(
      alpha: shadow * alpha,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: ground + Offset(width * .02, height * .012),
        width: width * .70,
        height: max(5, height * .085),
      ),
      _shadowPaint,
    );

    _imagePaint
      ..color = Colors.white.withValues(alpha: alpha)
      ..colorFilter = ColorFilter.mode(tint, BlendMode.modulate);
    canvas.save();
    canvas.translate(ground.dx, ground.dy);
    canvas.rotate(rotation);
    canvas.drawImageRect(
      image,
      source,
      Rect.fromLTWH(-width / 2, -height, width, height),
      _imagePaint,
    );
    canvas.restore();
    _imagePaint
      ..color = Colors.white
      ..colorFilter = null;
  }

  void _text(
    Canvas canvas,
    String value,
    Offset center,
    double size,
    Color color,
    FontWeight weight, {
    double? maxWidth,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: weight,
          shadows: const <Shadow>[
            Shadow(color: Color(0x33000000), blurRadius: 2, offset: Offset(0, 1)),
          ],
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: textDirection,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth ?? double.infinity);
    painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2));
  }

  @override
  bool shouldRepaint(covariant MarketPainter oldDelegate) =>
      oldDelegate.game != game ||
      oldDelegate._reducedMotionOverride != _reducedMotionOverride ||
      oldDelegate.storageLabel != storageLabel ||
      oldDelegate.shelfLabel != shelfLabel ||
      oldDelegate.checkoutLabel != checkoutLabel ||
      oldDelegate.bakeryLabel != bakeryLabel ||
      oldDelegate.bakeryLockedLabel != bakeryLockedLabel ||
      oldDelegate.departmentLabels != departmentLabels ||
      oldDelegate.textDirection != textDirection;
}

class _SceneItem {
  const _SceneItem(this.depth, this.draw);

  final WorldDepthEntry depth;
  final VoidCallback draw;
}
