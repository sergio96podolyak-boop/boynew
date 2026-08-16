import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../game/game_controller.dart';
import '../game/game_models.dart';
import 'market_art_assets.dart';

abstract final class VerticalSliceRenderSettings {
  static bool reducedMotion = false;
}

enum VerticalSliceLayer {
  background,
  architecture,
  floor,
  permanentFixtures,
  merchandise,
  props,
  characters,
  foreground,
  indicators,
}

abstract final class VerticalSliceComposition {
  static const layers = <VerticalSliceLayer>[
    VerticalSliceLayer.background,
    VerticalSliceLayer.architecture,
    VerticalSliceLayer.floor,
    VerticalSliceLayer.permanentFixtures,
    VerticalSliceLayer.merchandise,
    VerticalSliceLayer.props,
    VerticalSliceLayer.characters,
    VerticalSliceLayer.foreground,
    VerticalSliceLayer.indicators,
  ];

  static double densityFor(double width) => width <= 330
      ? .38
      : width <= 420
      ? .58
      : width <= 500
      ? .80
      : 1;

  static bool get validDepthOrder =>
      layers.indexOf(VerticalSliceLayer.permanentFixtures) <
          layers.indexOf(VerticalSliceLayer.characters) &&
      layers.indexOf(VerticalSliceLayer.characters) <
          layers.indexOf(VerticalSliceLayer.indicators);
}

/// Single board-local renderer for the playable supermarket.
class VerticalSliceWorldPainter extends CustomPainter {
  VerticalSliceWorldPainter({
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
  static const _darkForest = Color(0xFF14382E);
  static const _cream = Color(0xFFFFF5DD);
  static const _blue = Color(0xFF5079B8);
  static const _coral = Color(0xFFC95770);
  static const _gold = Color(0xFFE4A43A);
  static const _teal = Color(0xFF369E89);
  static const _slate = Color(0xFF60777D);

  @override
  void paint(Canvas canvas, Size size) {
    if (game.pendingShiftSummary != null || size.isEmpty) return;
    final market = marketRect(size);
    if (market.width < 120 || market.height < 150) return;

    final scale = (market.width / 520).clamp(.55, 1.05);
    final density = VerticalSliceComposition.densityFor(market.width);
    final room = RRect.fromRectAndRadius(market, Radius.circular(27 * scale));

    _drawRoomShadow(canvas, room, scale);
    canvas.save();
    canvas.clipRRect(room);
    _drawArchitecture(canvas, market, scale, density);
    _drawFloor(canvas, market, scale, density);
    _drawZoneIdentity(canvas, market, scale, density);

    final scene = <_WorldItem>[];
    _addFixtureClusters(scene, canvas, market, scale, density);
    _addCharacters(scene, canvas, market, scale);
    scene.sort((left, right) => left.depth.compareTo(right.depth));
    for (final item in scene) {
      item.draw();
    }

    _drawAtmosphere(canvas, market, scale);
    _drawIndicators(canvas, market, scale);
    canvas.restore();

    _paint
      ..shader = null
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 * scale
      ..color = _forest;
    canvas.drawRRect(room, _paint);
  }

  /// The canvas is already the real market-board; no screen dimensions or HUD
  /// heights are reconstructed.
  Rect marketRect(Size size) => Rect.fromLTWH(
    8,
    6,
    max(0, size.width - 16),
    max(0, size.height - 12),
  );

  Offset _point(Rect rect, Offset position) => Offset(
    rect.left + rect.width * position.dx,
    rect.top + rect.height * position.dy,
  );

  void _drawRoomShadow(Canvas canvas, RRect room, double scale) {
    _paint
      ..shader = null
      ..style = PaintingStyle.fill
      ..color = const Color(0x3D20332A);
    canvas.drawRRect(room.shift(Offset(0, 8 * scale)), _paint);
  }

  void _drawArchitecture(
    Canvas canvas,
    Rect market,
    double scale,
    double density,
  ) {
    _paint.shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[Color(0xFFFFF6E4), Color(0xFFE6C792)],
    ).createShader(market);
    canvas.drawRect(market, _paint);
    _paint.shader = null;

    final wall = Rect.fromLTWH(
      market.left,
      market.top,
      market.width,
      market.height * .205,
    );
    _paint.shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[Color(0xFFFFFAED), Color(0xFFE2C79A)],
    ).createShader(wall);
    canvas.drawRect(wall, _paint);
    _paint.shader = null;

    _paint
      ..style = PaintingStyle.fill
      ..color = const Color(0x19315F4A);
    final panelCount = density < .55 ? 4 : 8;
    for (var index = 1; index < panelCount; index++) {
      final x = wall.left + wall.width * index / panelCount;
      canvas.drawRect(
        Rect.fromLTWH(x, wall.top + 5 * scale, .8 * scale, wall.height - 12 * scale),
        _paint,
      );
    }

    _paint.color = _darkForest;
    canvas.drawRect(
      Rect.fromLTWH(wall.left, wall.bottom - 8 * scale, wall.width, 8 * scale),
      _paint,
    );

    _drawBrand(canvas, market, scale);
    _drawCeilingLights(canvas, market, scale, density);
  }

  void _drawBrand(Canvas canvas, Rect market, double scale) {
    final sign = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: _point(market, const Offset(.5, .09)),
        width: 166 * scale,
        height: 32 * scale,
      ),
      Radius.circular(11 * scale),
    );
    _paint
      ..style = PaintingStyle.fill
      ..color = const Color(0x3020332A);
    canvas.drawRRect(sign.shift(Offset(0, 3 * scale)), _paint);
    _paint.shader = const LinearGradient(
      colors: <Color>[Color(0xFF3C7E61), Color(0xFF245442)],
    ).createShader(sign.outerRect);
    canvas.drawRRect(sign, _paint);
    _paint.shader = null;
    _paint.color = const Color(0xFFFFD56E);
    canvas.drawCircle(sign.center - Offset(60 * scale, 0), 5.5 * scale, _paint);
    _text(
      canvas,
      'PoMARKET',
      sign.center + Offset(6 * scale, 0),
      13.5 * scale,
      Colors.white,
      FontWeight.w900,
    );
  }

  void _drawCeilingLights(
    Canvas canvas,
    Rect market,
    double scale,
    double density,
  ) {
    final positions = density < .55
        ? const <double>[.26, .74]
        : const <double>[.14, .36, .64, .86];
    for (final x in positions) {
      final center = _point(market, Offset(x, .17));
      _paint
        ..style = PaintingStyle.fill
        ..color = const Color(0xFFFFE4A2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: center,
            width: 30 * scale,
            height: 4 * scale,
          ),
          Radius.circular(2 * scale),
        ),
        _paint,
      );
    }
  }

  void _drawFloor(Canvas canvas, Rect market, double scale, double density) {
    final floor = Rect.fromLTRB(
      market.left,
      market.top + market.height * .205,
      market.right,
      market.bottom,
    );
    _paint.shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[Color(0xFFE9D3A7), Color(0xFFD2A766)],
    ).createShader(floor);
    canvas.drawRect(floor, _paint);
    _paint.shader = null;

    // Restrained tile variation, with perspective compressed toward the wall.
    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = .55 * scale
      ..color = const Color(0x15315F4A);
    final rowCount = density < .55 ? 7 : 10;
    for (var row = 1; row < rowCount; row++) {
      final t = row / rowCount;
      final y = floor.top + floor.height * pow(t, .82);
      canvas.drawLine(
        Offset(floor.left + 12 * scale, y),
        Offset(floor.right - 12 * scale, y),
        _paint,
      );
    }
    if (density >= .58) {
      for (var x = floor.left + 48 * scale; x < floor.right; x += 48 * scale) {
        canvas.drawLine(
          Offset(x, floor.top + 4 * scale),
          Offset(x, floor.bottom),
          _paint,
        );
      }
    }

    // Narrow circulation paths rather than debug-like zone rectangles.
    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18 * scale
      ..strokeCap = StrokeCap.round
      ..color = const Color(0x17FFF9EC);
    canvas.drawLine(
      _point(market, const Offset(.50, .27)),
      _point(market, const Offset(.50, .91)),
      _paint,
    );
    canvas.drawLine(
      _point(market, const Offset(.18, .63)),
      _point(market, const Offset(.82, .63)),
      _paint,
    );
  }

  void _drawZoneIdentity(
    Canvas canvas,
    Rect market,
    double scale,
    double density,
  ) {
    final compact = density < .62;
    _sectionSign(
      canvas,
      _point(market, GameController.shelfZone) + Offset(0, -81 * scale),
      departmentLabels[DepartmentType.generalGoods] ?? shelfLabel,
      _blue,
      scale,
      compact: compact,
    );
    _sectionSign(
      canvas,
      _point(market, GameController.checkoutZone) + Offset(-8 * scale, -76 * scale),
      checkoutLabel,
      _coral,
      scale,
      compact: compact,
    );
    _sectionSign(
      canvas,
      _point(market, GameController.bakeryZone) + Offset(0, -74 * scale),
      game.bakeryUnlocked ? bakeryLabel : bakeryLockedLabel,
      _gold,
      scale,
      compact: compact,
    );
    if (!compact) {
      _sectionSign(
        canvas,
        _point(market, GameController.stockZone) + Offset(0, -70 * scale),
        storageLabel,
        _slate,
        scale,
      );
    }
  }

  void _sectionSign(
    Canvas canvas,
    Offset center,
    String value,
    Color color,
    double scale, {
    bool compact = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: Colors.white,
          fontSize: (compact ? 6.8 : 7.7) * scale,
          fontWeight: FontWeight.w900,
          letterSpacing: .16 * scale,
        ),
      ),
      textDirection: textDirection,
      textAlign: TextAlign.center,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: (compact ? 94 : 130) * scale);
    final sign = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center,
        width: painter.width + (compact ? 12 : 17) * scale,
        height: painter.height + (compact ? 6 : 8) * scale,
      ),
      Radius.circular(8 * scale),
    );
    _paint
      ..style = PaintingStyle.fill
      ..color = const Color(0x3020332A);
    canvas.drawRRect(sign.shift(Offset(0, 2 * scale)), _paint);
    _paint.color = color;
    canvas.drawRRect(sign, _paint);
    painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2));
  }

  void _addFixtureClusters(
    List<_WorldItem> scene,
    Canvas canvas,
    Rect market,
    double scale,
    double density,
  ) {
    _addEntrance(scene, canvas, market, scale, density);
    _addShelf(scene, canvas, market, scale, density);
    _addStorage(scene, canvas, market, scale, density);
    _addCheckouts(scene, canvas, market, scale);
    _addBakery(scene, canvas, market, scale, density);
    _addSecondaryDepartments(scene, canvas, market, scale, density);
    _addRetainedProps(scene, canvas, market, scale, density);
  }

  void _addEntrance(
    List<_WorldItem> scene,
    Canvas canvas,
    Rect market,
    double scale,
    double density,
  ) {
    final ground = _point(market, GameController.entrance) + Offset(0, 88 * scale);
    scene.add(
      _WorldItem(.25, () {
        _drawFixtureFootprint(canvas, ground, 126 * scale, 20 * scale, _teal, .10);
        _drawSprite(
          canvas,
          MarketArtAssets.v2EntrancePath,
          ground,
          145 * scale,
          shadow: .20,
        );
        if (density >= .55) {
          _drawCorral(canvas, ground + Offset(-66 * scale, 5 * scale), scale);
        }
      }),
    );
    _addSprite(
      scene,
      canvas,
      market,
      MarketArtAssets.v2CartBasketsPath,
      const Offset(.16, .25),
      84 * scale,
      .34,
      dy: 29 * scale,
      shadow: .18,
    );
  }

  void _drawCorral(Canvas canvas, Offset center, double scale) {
    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * scale
      ..strokeCap = StrokeCap.round
      ..color = const Color(0x77315F4A);
    for (var index = 0; index < 3; index++) {
      final x = center.dx + index * 12 * scale;
      canvas.drawLine(
        Offset(x, center.dy - 13 * scale),
        Offset(x, center.dy + 13 * scale),
        _paint,
      );
    }
    canvas.drawLine(
      center + Offset(0, 10 * scale),
      center + Offset(24 * scale, 10 * scale),
      _paint,
    );
  }

  void _addShelf(
    List<_WorldItem> scene,
    Canvas canvas,
    Rect market,
    double scale,
    double density,
  ) {
    final ground = _point(market, GameController.shelfZone) + Offset(0, 62 * scale);
    scene.add(
      _WorldItem(GameController.shelfZone.dy + .10, () {
        _drawFixtureFootprint(canvas, ground, 150 * scale, 22 * scale, _blue, .10);
        _drawSprite(
          canvas,
          MarketArtAssets.v2ShelfPath,
          ground,
          170 * scale,
          shadow: .29,
        );
        _drawShelfProducts(canvas, ground, scale);
        if (density >= .55) {
          _drawPriceStand(canvas, ground + Offset(74 * scale, -13 * scale), scale);
        }
      }),
    );
    _addSprite(
      scene,
      canvas,
      market,
      MarketArtAssets.v2PromoEndcapPath,
      const Offset(.54, .48),
      96 * scale,
      .58,
      dy: 37 * scale,
      shadow: .21,
    );
    if (density > .55) {
      _addSprite(
        scene,
        canvas,
        market,
        MarketArtAssets.v2CoolerPath,
        const Offset(.16, .40),
        108 * scale,
        .47,
        dy: 41 * scale,
        shadow: .22,
      );
    }
  }

  void _drawShelfProducts(Canvas canvas, Offset ground, double scale) {
    final stock = game.departmentStock(DepartmentType.generalGoods);
    final capacity = max(1, game.departmentCapacity(DepartmentType.generalGoods));
    final ratio = (stock / capacity).clamp(0.0, 1.0);
    const rowCount = 3;
    const slots = 7;
    final filled = (ratio * rowCount * slots).ceil();
    final colors = <Color>[
      const Color(0xFFF3C34F),
      const Color(0xFF5BA6D7),
      const Color(0xFFE66B78),
      const Color(0xFF55B88A),
      const Color(0xFF9A78D0),
    ];

    for (var row = 0; row < rowCount; row++) {
      final railY = ground.dy - (103 - row * 30) * scale;
      _paint
        ..style = PaintingStyle.fill
        ..color = const Color(0xD9F8EAC7);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(ground.dx, railY + 11 * scale),
            width: 112 * scale,
            height: 4 * scale,
          ),
          Radius.circular(2 * scale),
        ),
        _paint,
      );
      for (var slot = 0; slot < slots; slot++) {
        final index = row * slots + slot;
        if (index >= filled) continue;
        final width = (8.5 + index % 3) * scale;
        final height = (13 + (index + row) % 2 * 4) * scale;
        final center = Offset(
          ground.dx + (-47 + slot * 15.7) * scale,
          railY + 7 * scale - height / 2,
        );
        _paint.color = colors[(index + row) % colors.length];
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: center, width: width, height: height),
            Radius.circular(2 * scale),
          ),
          _paint,
        );
        _paint.color = const Color(0xA0FFFFFF);
        canvas.drawRect(
          Rect.fromCenter(
            center: center + Offset(0, 1.5 * scale),
            width: width * .45,
            height: 2 * scale,
          ),
          _paint,
        );
      }
    }

    _paint.color = ratio <= .34
        ? const Color(0xFFE65E70)
        : const Color(0xFFF5D06C);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: ground + Offset(0, -10 * scale),
          width: 116 * scale,
          height: 6 * scale,
        ),
        Radius.circular(2 * scale),
      ),
      _paint,
    );
  }

  void _drawPriceStand(Canvas canvas, Offset center, double scale) {
    _paint
      ..style = PaintingStyle.fill
      ..color = _forest;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: 18 * scale, height: 24 * scale),
        Radius.circular(4 * scale),
      ),
      _paint,
    );
    _paint.color = const Color(0xFFFFE39A);
    canvas.drawRect(
      Rect.fromCenter(
        center: center - Offset(0, 4 * scale),
        width: 10 * scale,
        height: 6 * scale,
      ),
      _paint,
    );
  }

  void _addStorage(
    List<_WorldItem> scene,
    Canvas canvas,
    Rect market,
    double scale,
    double density,
  ) {
    final zone = GameController.stockZone;
    final ground = _point(market, zone) + Offset(0, 55 * scale);
    scene.add(
      _WorldItem(zone.dy + .10, () {
        _drawFixtureFootprint(canvas, ground, 138 * scale, 23 * scale, _slate, .11);
        _drawWorkArea(canvas, ground, scale, density);
        _drawSprite(
          canvas,
          MarketArtAssets.v2StoragePath,
          ground,
          151 * scale,
          shadow: .27,
        );
      }),
    );
  }

  void _drawWorkArea(
    Canvas canvas,
    Offset ground,
    double scale,
    double density,
  ) {
    _paint
      ..style = PaintingStyle.fill
      ..color = const Color(0xB68C6039);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: ground + Offset(-54 * scale, -5 * scale),
          width: 45 * scale,
          height: 12 * scale,
        ),
        Radius.circular(3 * scale),
      ),
      _paint,
    );
    if (density < .55) return;
    for (final spec in <(double, double, double, double)>[
      (-61, -20, 20, 18),
      (-43, -17, 18, 15),
      (55, -13, 22, 19),
    ]) {
      _paint.color = const Color(0xFFD39B58);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: ground + Offset(spec.$1 * scale, spec.$2 * scale),
            width: spec.$3 * scale,
            height: spec.$4 * scale,
          ),
          Radius.circular(3 * scale),
        ),
        _paint,
      );
      _paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8 * scale
        ..color = const Color(0x775F4028);
      canvas.drawLine(
        ground + Offset((spec.$1 - spec.$3 / 2) * scale, spec.$2 * scale),
        ground + Offset((spec.$1 + spec.$3 / 2) * scale, spec.$2 * scale),
        _paint,
      );
    }
  }

  void _addCheckouts(
    List<_WorldItem> scene,
    Canvas canvas,
    Rect market,
    double scale,
  ) {
    for (final station in game.checkoutStations) {
      if (!station.unlocked) continue;
      final primary = station.id == GameController.primaryCheckoutStationId;
      final zone = game.checkoutStationZone(station.id);
      final ground = _point(market, zone) +
          Offset(0, (primary ? 52 : 40) * scale);
      scene.add(
        _WorldItem(zone.dy + .10, () {
          _drawFixtureFootprint(
            canvas,
            ground,
            (primary ? 122 : 92) * scale,
            20 * scale,
            _coral,
            station.active ? .10 : .05,
          );
          _drawSprite(
            canvas,
            MarketArtAssets.v2CheckoutPath,
            ground,
            (primary ? 135 : 101) * scale,
            alpha: station.active ? 1 : .55,
            shadow: station.active ? .28 : .12,
          );
          _drawCheckoutHardware(canvas, ground, scale, primary);
          _drawQueueDivider(canvas, ground, scale, primary);
        }),
      );
    }
  }

  void _drawCheckoutHardware(
    Canvas canvas,
    Offset ground,
    double scale,
    bool primary,
  ) {
    final factor = primary ? 1.0 : .78;
    _paint
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF313B48);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: ground + Offset(21 * factor * scale, -75 * factor * scale),
          width: 18 * factor * scale,
          height: 13 * factor * scale,
        ),
        Radius.circular(3 * scale),
      ),
      _paint,
    );
    _paint.color = const Color(0xFF78D4B3);
    canvas.drawRect(
      Rect.fromCenter(
        center: ground + Offset(21 * factor * scale, -76 * factor * scale),
        width: 11 * factor * scale,
        height: 6 * factor * scale,
      ),
      _paint,
    );
    _paint.color = const Color(0xFFFFF0D0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: ground + Offset(-37 * factor * scale, -29 * factor * scale),
          width: 28 * factor * scale,
          height: 15 * factor * scale,
        ),
        Radius.circular(4 * scale),
      ),
      _paint,
    );
  }

  void _drawQueueDivider(
    Canvas canvas,
    Offset ground,
    double scale,
    bool primary,
  ) {
    final factor = primary ? 1.0 : .8;
    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * scale
      ..strokeCap = StrokeCap.round
      ..color = const Color(0x80315F4A);
    final x = ground.dx - 46 * factor * scale;
    canvas.drawLine(
      Offset(x, ground.dy - 4 * scale),
      Offset(x, ground.dy + 48 * factor * scale),
      _paint,
    );
    _paint
      ..style = PaintingStyle.fill
      ..color = _darkForest;
    for (final dy in <double>[-4, 22, 48]) {
      canvas.drawCircle(
        Offset(x, ground.dy + dy * factor * scale),
        3 * scale,
        _paint,
      );
    }
  }

  void _addBakery(
    List<_WorldItem> scene,
    Canvas canvas,
    Rect market,
    double scale,
    double density,
  ) {
    final zone = GameController.bakeryZone;
    final ground = _point(market, zone) + Offset(0, 56 * scale);
    if (!game.bakeryUnlocked) {
      scene.add(
        _WorldItem(zone.dy + .08, () {
          _drawFixtureFootprint(canvas, ground, 92 * scale, 17 * scale, _gold, .07);
          _paint
            ..style = PaintingStyle.fill
            ..color = const Color(0xC8D1B98D);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                center: ground - Offset(0, 19 * scale),
                width: 82 * scale,
                height: 31 * scale,
              ),
              Radius.circular(10 * scale),
            ),
            _paint,
          );
          _paint.color = _darkForest;
          canvas.drawCircle(ground - Offset(0, 19 * scale), 9 * scale, _paint);
          _text(
            canvas,
            'L${GameBalance.bakeryUnlockLevel}',
            ground - Offset(0, 19 * scale),
            6.6 * scale,
            Colors.white,
            FontWeight.w900,
          );
        }),
      );
      return;
    }

    scene.add(
      _WorldItem(zone.dy + .10, () {
        _drawFixtureFootprint(canvas, ground, 145 * scale, 23 * scale, _gold, .13);
        _drawBakeryWarmth(canvas, ground, scale);
        _drawSprite(
          canvas,
          MarketArtAssets.v2BakeryPath,
          ground,
          160 * scale,
          shadow: .29,
        );
        _drawBakeryTrays(canvas, ground, scale, density);
      }),
    );
  }

  void _drawBakeryWarmth(Canvas canvas, Offset ground, double scale) {
    final glow = Rect.fromCircle(
      center: ground - Offset(0, 48 * scale),
      radius: 70 * scale,
    );
    _paint.shader = const RadialGradient(
      colors: <Color>[Color(0x2AFFC75C), Color(0x00FFC75C)],
    ).createShader(glow);
    canvas.drawOval(glow, _paint);
    _paint.shader = null;
  }

  void _drawBakeryTrays(
    Canvas canvas,
    Offset ground,
    double scale,
    double density,
  ) {
    final count = density < .55 ? 3 : 5;
    for (var index = 0; index < count; index++) {
      _paint
        ..style = PaintingStyle.fill
        ..color = index < game.bakeryReadyStock
            ? const Color(0xFFE5A23C)
            : const Color(0xFF9A8060);
      canvas.drawOval(
        Rect.fromCenter(
          center: ground + Offset((-32 + index * 16) * scale, -28 * scale),
          width: 12 * scale,
          height: 7 * scale,
        ),
        _paint,
      );
    }
  }

  void _addSecondaryDepartments(
    List<_WorldItem> scene,
    Canvas canvas,
    Rect market,
    double scale,
    double density,
  ) {
    for (final definition in DepartmentCatalog.all) {
      if (definition.type == DepartmentType.generalGoods ||
          definition.type == DepartmentType.bakery ||
          !game.isDepartmentUnlocked(definition.type)) {
        continue;
      }
      final center = _point(market, definition.displayZone) + Offset(0, 19 * scale);
      scene.add(
        _WorldItem(definition.displayZone.dy + .07, () {
          _drawFixtureFootprint(canvas, center, 48 * scale, 10 * scale,
              definition.color, .09);
          _paint
            ..style = PaintingStyle.fill
            ..color = definition.color;
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                center: center - Offset(0, 13 * scale),
                width: (density < .55 ? 40 : 50) * scale,
                height: (density < .55 ? 26 : 33) * scale,
              ),
              Radius.circular(8 * scale),
            ),
            _paint,
          );
          _paint.color = _cream;
          for (var index = 0; index < 3; index++) {
            canvas.drawCircle(
              center + Offset((-12 + index * 12) * scale, -18 * scale),
              4 * scale,
              _paint,
            );
          }
        }),
      );
    }
  }

  void _addRetainedProps(
    List<_WorldItem> scene,
    Canvas canvas,
    Rect market,
    double scale,
    double density,
  ) {
    if (density <= .78) return;
    _addSprite(
      scene,
      canvas,
      market,
      MarketArtAssets.cleaningCartPath,
      const Offset(.57, .88),
      59 * scale,
      .94,
      dy: 17 * scale,
      shadow: .14,
    );
    _addSprite(
      scene,
      canvas,
      market,
      MarketArtAssets.deliveryBoxesPath,
      const Offset(.30, .87),
      54 * scale,
      .92,
      dy: 17 * scale,
      shadow: .14,
    );
  }

  void _drawFixtureFootprint(
    Canvas canvas,
    Offset ground,
    double width,
    double height,
    Color color,
    double alpha,
  ) {
    _paint
      ..shader = null
      ..style = PaintingStyle.fill
      ..color = color.withValues(alpha: alpha);
    canvas.drawOval(
      Rect.fromCenter(
        center: ground + Offset(0, height * .12),
        width: width,
        height: height,
      ),
      _paint,
    );
  }

  void _addSprite(
    List<_WorldItem> scene,
    Canvas canvas,
    Rect market,
    String path,
    Offset position,
    double height,
    double depth, {
    double dy = 0,
    double alpha = 1,
    double shadow = .16,
  }) {
    scene.add(
      _WorldItem(
        depth,
        () => _drawSprite(
          canvas,
          path,
          _point(market, position) + Offset(0, dy),
          height,
          alpha: alpha,
          shadow: shadow,
        ),
      ),
    );
  }

  void _addCharacters(
    List<_WorldItem> scene,
    Canvas canvas,
    Rect market,
    double scale,
  ) {
    for (final customer in game.customers) {
      scene.add(
        _WorldItem(
          customer.position.dy + .08,
          () => _drawCustomer(canvas, market, customer, scale),
        ),
      );
    }
    for (final role in StaffRole.values) {
      if (!game.isStaffHired(role)) continue;
      for (var index = 0; index < game.staffWorkerCount(role); index++) {
        final position = _staffPosition(role, index);
        if (position == null) continue;
        scene.add(
          _WorldItem(
            position.dy + .085,
            () => _drawStaff(canvas, market, role, position, scale),
          ),
        );
      }
    }
    scene.add(
      _WorldItem(
        game.playerPosition.dy + .13,
        () => _drawPlayer(canvas, market, scale),
      ),
    );
  }

  void _drawCustomer(
    Canvas canvas,
    Rect market,
    MarketCustomer customer,
    double scale,
  ) {
    final moving = customer.phase != CustomerPhase.paying &&
        !(customer.phase == CustomerPhase.shopping && customer.phaseTime > .66);
    final wave = _reducedMotion
        ? 0.0
        : sin(game.totalPlaySeconds * (moving ? 7.5 : 2.2) + customer.id);
    final ground = _point(market, customer.position) +
        Offset(0, 24 * scale + wave * (moving ? .8 : .25) * scale);
    _drawSprite(
      canvas,
      MarketArtAssets.customerPaths[customer.id.abs() % 4],
      ground,
      69 * scale,
      shadow: .18,
      rotation: moving ? wave * .008 : 0,
      tint: const Color(0xFFFFF3DD),
    );
  }

  void _drawStaff(
    Canvas canvas,
    Rect market,
    StaffRole role,
    Offset position,
    double scale,
  ) {
    final status = game.staffStatus(role);
    final active = status != StaffStatus.idle &&
        status != StaffStatus.waitingForShelf &&
        status != StaffStatus.waitingForStock;
    final bob = _reducedMotion || !active
        ? 0.0
        : sin(game.totalPlaySeconds * 6.5 + role.index) * .55 * scale;
    final ground = _point(market, position) + Offset(0, 26 * scale + bob);
    _drawSprite(
      canvas,
      MarketArtAssets.staffPaths[role.index],
      ground,
      74 * scale,
      shadow: .19,
      tint: role == StaffRole.baker
          ? const Color(0xFFFFE8BA)
          : const Color(0xFFF2FFF7),
    );
  }

  Offset? _staffPosition(StaffRole role, int index) {
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
      StaffRole.cashier => _cashierPosition(index),
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

  Offset? _cashierPosition(int index) {
    final stations = game.checkoutStations
        .where((station) => station.unlocked && station.active)
        .toList();
    if (index >= stations.length) return null;
    return game.checkoutStationZone(stations[index].id) + const Offset(.075, .035);
  }

  void _drawPlayer(Canvas canvas, Rect market, double scale) {
    final walking = game.movement.distance > .05;
    final frame = game.carried > 0
        ? 3
        : !walking
        ? 0
        : _reducedMotion
        ? 1
        : 1 + ((game.totalPlaySeconds * 8).floor() % 2);
    final wave = _reducedMotion
        ? 0.0
        : sin(game.totalPlaySeconds * (walking ? 10.5 : 2));
    final ground = _point(market, game.playerPosition) +
        Offset(0, 31 * scale + wave * (walking ? 1 : .28) * scale);
    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * scale
      ..color = const Color(0x9938B879);
    canvas.drawOval(
      Rect.fromCenter(
        center: ground + Offset(0, 1 * scale),
        width: 58 * scale,
        height: 18 * scale,
      ),
      _paint,
    );
    _drawSprite(
      canvas,
      MarketArtAssets.playerPaths[frame],
      ground,
      91 * scale,
      shadow: .23,
      tint: const Color(0xFFFFEFD2),
    );
  }

  void _drawAtmosphere(Canvas canvas, Rect market, double scale) {
    _paint.shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[Color(0x10FFFFFF), Color(0x00000000)],
    ).createShader(
      Rect.fromLTWH(market.left, market.top, market.width, market.height * .48),
    );
    _paint.style = PaintingStyle.fill;
    canvas.drawRect(market, _paint);
    _paint.shader = null;
  }

  void _drawIndicators(Canvas canvas, Rect market, double scale) {
    for (final station in game.checkoutStations) {
      if (!station.unlocked) continue;
      final center = _point(market, game.checkoutStationZone(station.id));
      _paint
        ..style = PaintingStyle.fill
        ..color = !station.active
            ? const Color(0xFF84949C)
            : game.checkoutStationIsOperational(station.id)
            ? const Color(0xFF35D391)
            : const Color(0xFFF6A623);
      canvas.drawCircle(center + Offset(44 * scale, -36 * scale), 4 * scale, _paint);
    }

    final target = game.movementTarget;
    if (target != null) {
      final center = _point(market, target);
      final pulse = _reducedMotion
          ? 10 * scale
          : (10 + sin(game.totalPlaySeconds * 6) * 2) * scale;
      _paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * scale
        ..color = const Color(0x9938B879);
      canvas.drawCircle(center, pulse, _paint);
      _paint
        ..style = PaintingStyle.fill
        ..color = const Color(0xFF38B879);
      canvas.drawCircle(center, 3 * scale, _paint);
    }

    final ratio = game.departmentStock(DepartmentType.generalGoods) /
        max(1, game.departmentCapacity(DepartmentType.generalGoods));
    final active = game.carriedDepartment == DepartmentType.generalGoods &&
        game.carried > 0 &&
        (game.playerPosition - GameController.shelfZone).distance <= .14;
    if (active || ratio <= .34) {
      _paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = (active ? 2.1 : 1.5) * scale
        ..color = (ratio <= .34
                ? const Color(0xFFFF6B7D)
                : const Color(0xFF45D39A))
            .withValues(alpha: .60);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: _point(market, GameController.shelfZone) + Offset(0, 12 * scale),
            width: 165 * scale,
            height: 124 * scale,
          ),
          Radius.circular(20 * scale),
        ),
        _paint,
      );
    }

    for (final effect in game.floatingEffects) {
      _text(
        canvas,
        effect.text,
        _point(market, _reducedMotion ? effect.position : effect.currentPosition),
        effect.fontSize * scale,
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
    double alpha = 1,
    double shadow = .16,
    double rotation = 0,
    Color tint = const Color(0xFFFFFBF3),
  }) {
    final image = MarketArtAssets.image(path);
    final source = MarketArtAssets.sourceRect(path);
    if (image == null || source == null || source.height <= 0) return;
    final factor = height / source.height;
    final width = source.width * factor;

    _shadowPaint.color = const Color(0xFF23372E).withValues(alpha: shadow * alpha);
    canvas.drawOval(
      Rect.fromCenter(
        center: ground + Offset(width * .025, height * .012),
        width: width * .73,
        height: max(5, height * .095),
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
    FontWeight weight,
  ) {
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
    )..layout();
    painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2));
  }

  @override
  bool shouldRepaint(covariant VerticalSliceWorldPainter oldDelegate) =>
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

class _WorldItem {
  const _WorldItem(this.depth, this.draw);
  final double depth;
  final VoidCallback draw;
}
