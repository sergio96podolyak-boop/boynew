import 'dart:math';

import 'package:flutter/material.dart';

import '../game/game_controller.dart';
import '../game/game_models.dart';
import '../services/season_theme.dart';

// --- Paints Cache ---
// Storing paints in a map to avoid polluting the class namespace.
// These are static and created only once.
final _p = <String, Paint>{
  'marketShadow': Paint()..color = const Color(0x1F243529),
  'marketGrid': Paint()
    ..color = const Color(0x0A315F4A)
    ..strokeWidth = 0.6,
  'marketDiamond': Paint()
    ..color = const Color(0x06315F4A)
    ..strokeWidth = 0.5,
  'marketBorder': Paint()
    ..color = const Color(0xFF315F4A)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 4,
  'ambientHeaderShadow': Paint()..color = const Color(0x22000000),
  'lightSource': Paint()..color = const Color(0xFFFFE291),
  'planterBox': Paint()..color = const Color(0xFFC77B45),
  'planterLeaf': Paint()..color = const Color(0xFF3A9A68),
  'departmentShadow': Paint()..color = const Color(0x21000000),
  'departmentCanopy': Paint()..color = const Color(0xEFFFFFFF),
  'sparkle': Paint()..color = const Color(0xDDFFF2A8),
  'produceGreen': Paint()..color = const Color(0xFF76C94F),
  'produceRed': Paint()..color = const Color(0xFFEF604F),
  'produceStem': Paint()
    ..color = const Color(0xFF2F7A43)
    ..strokeWidth = 1.4,
  'refrigeratedBox': Paint()..color = const Color(0xFFEAF8FF),
  'refrigeratedLabel': Paint()..color = const Color(0xFF69B8E7),
  'beautyPink': Paint()..color = const Color(0xFFFFE0EA),
  'beautyPurple': Paint()..color = const Color(0xFFF6C4FF),
  'beautyCap': Paint()..color = const Color(0xFF67546C),
  'electronicsBox': Paint()..color = const Color(0xFF26344F),
  'electronicsLed': Paint()..color = const Color(0xFF72E3FF),
  'bakeryLight': Paint()..color = const Color(0xFFFFD27A),
  'bakeryDark': Paint()..color = const Color(0xFFDE9143),
  'entranceDoor': Paint()..color = const Color(0xFF83D3B0),
  'stationBoxShadow': Paint()..color = const Color(0x18000000),
  'stationBoxGrate': Paint()
    ..color = const Color(0x669B6230)
    ..strokeWidth = 3,
  'shelfDividers': Paint()
    ..color = const Color(0xFFEAF1FF)
    ..strokeWidth = 4,
  'shelfProduct1': Paint()..color = const Color(0xFFF6A623),
  'shelfProduct2': Paint()..color = const Color(0xFFE85D75),
  'shelfProduct3': Paint()..color = const Color(0xFF43AA8B),
  'shelfEmpty': Paint()..color = const Color(0x33E85D75),
  'checkoutScreen': Paint()..color = const Color(0xFF3B4054),
  'checkoutScanner': Paint()..color = const Color(0xFFFFD166),
  'queueGuide': Paint()
    ..color = const Color(0x1F315F4A)
    ..strokeWidth = 2,
  'queueCustomerSkin': Paint()..color = const Color(0xFFFFD3B6),
  'expansionShadow': Paint()..color = const Color(0x14000000),
  'expansionUnlocked': Paint()..color = const Color(0xFFFFE7B6),
  'expansionLocked': Paint()..color = const Color(0xFFF0ECE3),
  'expansionUnlockedBorder': Paint()
    ..color = const Color(0xFFF6A623)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2,
  'expansionLockedBorder': Paint()
    ..color = const Color(0xFFAAA59B)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2,
  'expansionHighlight': Paint()..color = Colors.white.withValues(alpha: 0.35),
  'bakeryReady': Paint()..color = const Color(0xFFE09A20),
  'bakeryEmpty': Paint()..color = const Color(0x33A98D62),
  'movementTarget': Paint()..color = const Color(0xFF38B879),
  'movementTargetRing': Paint()
    ..color = const Color(0x6638B879)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2,
  'cashierShadow': Paint()..color = const Color(0x22000000),
  'cashierUniform': Paint()..color = const Color(0xFF315F8F),
  'cashierApron': Paint()..color = const Color(0xFFF6A623),
  'cashierSkin': Paint()..color = const Color(0xFFFFD3B6),
  'cashierHair': Paint()..color = const Color(0xFF473126),
  'cashierEye': Paint()..color = const Color(0xFF382B2A),
  'cashierFeature': Paint()
    ..color = const Color(0xFF382B2A)
    ..strokeWidth = 1.5
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke,
  'staffShadow': Paint()..color = const Color(0x22000000),
  'staffLegs': Paint()
    ..color = const Color(0xFF334052)
    ..strokeWidth = 4.5
    ..strokeCap = StrokeCap.round,
  'staffApron': Paint()..color = const Color(0xEFFFFFFF),
  'staffSkin': Paint()..color = const Color(0xFFFFD3B6),
  'staffEye': Paint()..color = const Color(0xFF382B2A),
  'staffFeature': Paint()
    ..color = const Color(0xFF573B35)
    ..strokeWidth = 1.5
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke,
  'staffStockerBoxLine': Paint()
    ..color = const Color(0xFFB76E00)
    ..strokeWidth = 1.2,
  'staffCleanerMopStick': Paint()
    ..color = const Color(0xFF6B5545)
    ..strokeWidth = 2.4
    ..strokeCap = StrokeCap.round,
  'staffCleanerMopHead': Paint()
    ..color = const Color(0xFF5B8DEF)
    ..strokeWidth = 2
    ..strokeCap = StrokeCap.round,
  'staffBakerHat': Paint()..color = Colors.white,
  'staffManagerClipboard': Paint()..color = const Color(0xFFFFF3D7),
  'staffManagerClipboardLine': Paint()
    ..color = const Color(0xFF8B66D8)
    ..strokeWidth = 1.3,
  'staffCourierHat': Paint()..color = const Color(0xFFFFF3D7),
  'staffPromoterSign': Paint()..color = const Color(0xFFFFD278),
  'staffPromoterSignStick': Paint()
    ..color = const Color(0xFF6B5545)
    ..strokeWidth = 2,
  'staffLevelBadge': Paint()..color = const Color(0xFF315F4A),
  'playerShadow': Paint()..color = const Color(0x25000000),
  'playerLegs': Paint()
    ..color = const Color(0xFF273043)
    ..strokeWidth = 6
    ..strokeCap = StrokeCap.round,
  'playerTorso': Paint()..color = const Color(0xFF38B879),
  'playerTorsoBorder': Paint()
    ..color = const Color(0xFF1F6A46)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2,
  'playerApron': Paint()..color = const Color(0xFFFFF3D7),
  'playerSkin': Paint()..color = const Color(0xFFFFCFAC),
  'playerHair': Paint()..color = const Color(0xFF5A3825),
  'playerEye': Paint()..color = const Color(0xFF273043),
  'playerFeature': Paint()
    ..color = const Color(0xFF56352E)
    ..strokeWidth = 1.8
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke,
  'customerShadow': Paint()..color = const Color(0x22000000),
  'customerBorder': Paint()
    ..color = const Color(0xFF4C3A2F)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6,
  'customerApron': Paint()..color = const Color(0xFFFFF3D7),
  'customerSkin': Paint()..color = const Color(0xFFFFD3B6),
  'customerEye': Paint()..color = const Color(0xFF382B2A),
  'customerFeature': Paint()
    ..color = const Color(0xFF573B35)
    ..strokeWidth = 1.5
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke,
  'customerProduct': Paint()..color = const Color(0xFFF6A623),
  'customerVipBadge': Paint()..color = const Color(0xFFFFD95A),
  'bubbleFill': Paint()..color = Colors.white,
  'interactionGlowActive': Paint()
    ..color = const Color(0x2238B879)
    ..style = PaintingStyle.fill,
  'interactionGlowInactive': Paint()
    ..color = const Color(0x08315F4A)
    ..style = PaintingStyle.fill,
  'interactionRing': Paint()
    ..color = const Color(0x9938B879)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.1,
  'stationLabelBubble': Paint()..color = const Color(0xEFFFFFFF),
};

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
    SeasonTheme? season,
  })  : season = season ?? SeasonManager.current(),
        super(repaint: game.scene);

  final GameController game;
  final SeasonTheme season;
  final String storageLabel;
  final String shelfLabel;
  final String checkoutLabel;
  final String bakeryLabel;
  final String bakeryReadyLabel;
  final String bakeryLockedLabel;
  final Map<DepartmentType, String> departmentLabels;
  final TextDirection textDirection;

  // --- CACHE ---
  final TextPainter _textPainter = TextPainter(textAlign: TextAlign.center);
  final Paint _dynamicPaint = Paint();
  Size? _lastSize;

  // Shaders
  final Map<String, Shader> _shaders = {};
  final Map<DepartmentType, Shader> _departmentShaders = {};
  final Map<DepartmentType, Paint> _departmentEdgePaints = {};
  final Map<int, Paint> _customerHairPaints = {};

  void _updateCachedResources(Size size) {
    if (size == _lastSize) return;
    _lastSize = size;

    _shaders.clear();
    _departmentShaders.clear();
    _departmentEdgePaints.clear();
    _customerHairPaints.clear();
    _p.remove('ambientArrow');
    _p.remove('stockerRoute');

    final market = Rect.fromLTWH(8, 6, size.width - 16, size.height - 12);
    final scale = _sceneScale(market);

    _shaders['marketFloor'] = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFFFFF6E2),
        Color(0xFFF3D8A6),
        Color(0xFFE3BF76),
      ],
    ).createShader(market);

    _shaders['glow'] = const RadialGradient(
      center: Alignment(0.38, 0.16),
      radius: 1.05,
      colors: [Color(0x55FFFFFF), Color(0x00FFFFFF)],
    ).createShader(market);

    _shaders['vignette'] = const RadialGradient(
      center: Alignment(0.5, 0.5),
      radius: 1.2,
      colors: [Color(0x00000000), Color(0x26000000)],
    ).createShader(market);

    final headerRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: _point(market, const Offset(0.5, 0.105)),
        width: 158 * scale,
        height: 28 * scale,
      ),
      Radius.circular(11 * scale),
    );
    _shaders['header'] = const LinearGradient(
      colors: [Color(0xFF163F35), Color(0xFF2E8A63)],
    ).createShader(headerRect.outerRect);

    _shaders['light'] = const RadialGradient(
      colors: [Color(0x66FFF2AF), Color(0x00FFF2AF)],
    ).createShader(market);

    _p['ambientArrow'] = Paint()
      ..color = const Color(0x17315F4A)
      ..strokeWidth = 2 * scale
      ..strokeCap = StrokeCap.round;

    for (final definition in DepartmentCatalog.all) {
      if (definition.type == DepartmentType.generalGoods) continue;

      final center = _point(market, definition.displayZone);
      final bodyRect = Rect.fromCenter(
        center: center,
        width: 72 * scale,
        height: 61 * scale,
      );

      _departmentShaders[definition.type] = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(definition.color, Colors.white, 0.34)!,
          definition.color,
        ],
      ).createShader(bodyRect);

      _departmentEdgePaints[definition.type] = Paint()
        ..color = Color.lerp(definition.color, Colors.black, 0.28)!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2 * scale;
    }
  }

  // --- END CACHE ---

  double get animationTime => game.totalPlaySeconds;

  @override
  void paint(Canvas canvas, Size size) {
    _updateCachedResources(size);

    final market = Rect.fromLTWH(8, 6, size.width - 16, size.height - 12);
    _drawMarket(canvas, market);
    _drawAmbientDetails(canvas, market);
    _drawEntrance(canvas, market);
    _drawStockRoom(canvas, market);
    _drawShelf(canvas, market);
    _drawDepartmentDisplays(canvas, market);
    _drawCheckout(canvas, market);
    _drawExpansion(canvas, market);
    _drawMovementTarget(canvas, market);
    _drawStockerRoute(canvas, market);

    if (game.isStaffHired(StaffRole.cashier)) {
      for (var index = 0;
          index < game.staffWorkerCount(StaffRole.cashier);
          index++) {
        _drawCashier(canvas, market, index);
      }
    }
    for (final role in StaffRole.values) {
      if (role == StaffRole.cashier || !game.isStaffHired(role)) {
        continue;
      }
      for (var index = 0; index < game.staffWorkerCount(role); index++) {
        _drawStaffMember(canvas, market, role, index);
      }
    }
    for (final customer in game.customers) {
      _drawCustomer(canvas, _point(market, customer.position), customer);
    }
    _drawPlayer(canvas, _point(market, game.playerPosition));
    _drawFloatingEffects(canvas, market);
    _drawSeasonalParticles(canvas, market);
  }

  void _drawMarket(Canvas canvas, Rect rect) {
    final shadow = RRect.fromRectAndRadius(
      rect.shift(const Offset(0, 7)),
      const Radius.circular(30),
    );
    canvas.drawRRect(shadow, _p['marketShadow']!);

    final room = RRect.fromRectAndRadius(rect, const Radius.circular(28));
    _dynamicPaint.shader = _shaders['marketFloor'];
    canvas.drawRRect(room, _dynamicPaint);
    _dynamicPaint.shader = null;

    canvas.save();
    canvas.clipRRect(room);

    final gridPaint = _p['marketGrid']!;
    final diamondPaint = _p['marketDiamond']!;

    const tile = 34.0;
    const halfTile = tile / 2;
    for (var x = rect.left; x <= rect.right; x += tile) {
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), gridPaint);
    }
    for (var y = rect.top; y <= rect.bottom; y += tile) {
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), gridPaint);
    }

    for (var y = rect.top + halfTile; y <= rect.bottom; y += tile) {
      final start = Offset(rect.left + halfTile, y);
      final end = Offset(rect.right, y + halfTile);
      if (end.dx <= rect.right + 0.1 && end.dy <= rect.bottom + 0.1) {
        canvas.drawLine(start, end, diamondPaint);
      }
    }
    for (var y = rect.top; y <= rect.bottom - halfTile; y += tile) {
      final start = Offset(rect.left, y + halfTile);
      final end = Offset(rect.right - halfTile, y + tile);
      if (start.dx >= rect.left - 0.1 && end.dx >= rect.left - 0.1) {
        canvas.drawLine(start, end, diamondPaint);
      }
    }

    _dynamicPaint.shader = _shaders['glow'];
    canvas.drawRect(rect, _dynamicPaint);

    _dynamicPaint.shader = _shaders['vignette'];
    canvas.drawRect(rect, _dynamicPaint);
    _dynamicPaint.shader = null;
    canvas.restore();

    canvas.drawRRect(room, _p['marketBorder']!);

    // Seasonal floor tint — a subtle colour wash over the base floor.
    final tintPaint = Paint()
      ..color = season.floorColor.withValues(alpha: 0.18)
      ..blendMode = BlendMode.srcATop;
    canvas.save();
    canvas.clipRRect(room);
    canvas.drawRect(rect, tintPaint);
    canvas.restore();
  }

  void _drawAmbientDetails(Canvas canvas, Rect market) {
    final scale = _sceneScale(market);
    final header = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: _point(market, const Offset(0.5, 0.105)),
        width: 158 * scale,
        height: 28 * scale,
      ),
      Radius.circular(11 * scale),
    );
    canvas.drawRRect(
        header.shift(Offset(0, 3 * scale)), _p['ambientHeaderShadow']!);

    _dynamicPaint.shader = _shaders['header'];
    canvas.drawRRect(header, _dynamicPaint);
    _dynamicPaint.shader = null;

    _text(
      canvas,
      'PoMarket  •  FRESH & FAST',
      header.center,
      color: Colors.white,
      fontSize: 10 * scale,
      weight: FontWeight.w900,
    );

    _dynamicPaint.shader = _shaders['light'];
    final lightSourcePaint = _p['lightSource']!;
    for (final x in [0.16, 0.36, 0.64, 0.84]) {
      final center = _point(market, Offset(x, 0.15));
      canvas.drawCircle(center, 27 * scale, _dynamicPaint);
      canvas.drawCircle(center, 3.5 * scale, lightSourcePaint);
    }
    _dynamicPaint.shader = null;

    final arrowPaint = _p['ambientArrow']!;
    for (var index = 0; index < 5; index++) {
      final y = 0.38 + index * 0.09;
      final center = _point(market, Offset(0.50, y));
      canvas.drawLine(
        center + Offset(-8 * scale, 0),
        center + Offset(8 * scale, 0),
        arrowPaint,
      );
      canvas.drawLine(
        center + Offset(3 * scale, -4 * scale),
        center + Offset(8 * scale, 0),
        arrowPaint,
      );
      canvas.drawLine(
        center + Offset(3 * scale, 4 * scale),
        center + Offset(8 * scale, 0),
        arrowPaint,
      );
    }

    _drawPlanter(canvas, market, const Offset(0.08, 0.16), scale);
    _drawPlanter(canvas, market, const Offset(0.92, 0.16), scale);
  }

  void _drawPlanter(Canvas canvas, Rect market, Offset position, double scale) {
    final center = _point(market, position);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: center + Offset(0, 7 * scale),
          width: 19 * scale,
          height: 14 * scale,
        ),
        Radius.circular(5 * scale),
      ),
      _p['planterBox']!,
    );
    final leafPaint = _p['planterLeaf']!;
    for (final direction in [-1.0, 0.0, 1.0]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: center + Offset(direction * 5 * scale, -3 * scale),
          width: 9 * scale,
          height: 17 * scale,
        ),
        leafPaint,
      );
    }
  }

  void _drawDepartmentDisplays(Canvas canvas, Rect market) {
    for (final definition in DepartmentCatalog.all) {
      if (definition.type == DepartmentType.generalGoods ||
          !game.isDepartmentUnlocked(definition.type)) {
        continue;
      }
      _drawDepartmentDisplay(canvas, market, definition);
    }
  }

  void _drawDepartmentDisplay(
    Canvas canvas,
    Rect market,
    DepartmentDefinition definition,
  ) {
    final center = _point(market, definition.displayZone);
    final scale = _sceneScale(market);
    final width = 72 * scale;
    final height = 61 * scale;
    final stock = game.departmentStock(definition.type);
    final capacity = game.departmentCapacity(definition.type);
    final active =
        (game.playerPosition - definition.displayZone).distance <= 0.13;
    final pulse = (sin(animationTime * 3 + definition.type.index) + 1) / 2;

    if (active) {
      _dynamicPaint.color = definition.color.withValues(alpha: 0.18);
      _dynamicPaint.style = PaintingStyle.fill;
      canvas.drawCircle(center, 41 * scale + pulse * 4 * scale, _dynamicPaint);
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: center + Offset(4 * scale, 5 * scale),
          width: width,
          height: height,
        ),
        Radius.circular(14 * scale),
      ),
      _p['departmentShadow']!,
    );
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: width, height: height),
      Radius.circular(14 * scale),
    );
    _dynamicPaint.shader = _departmentShaders[definition.type];
    canvas.drawRRect(body, _dynamicPaint);
    _dynamicPaint.shader = null;

    final edgePaint = _departmentEdgePaints[definition.type];
    if (edgePaint != null) {
      canvas.drawRRect(body, edgePaint);
    }

    final canopy = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center - Offset(0, 23 * scale),
        width: width * 0.82,
        height: 13 * scale,
      ),
      Radius.circular(6 * scale),
    );
    canvas.drawRRect(canopy, _p['departmentCanopy']!);
    _text(
      canvas,
      definition.emoji,
      center - Offset(0, 22 * scale),
      fontSize: 12 * scale,
    );

    _drawDepartmentProducts(
      canvas: canvas,
      center: center + Offset(0, 5 * scale),
      definition: definition,
      count: min(stock, 8),
      scale: scale,
    );

    if (stock == 0) {
      _text(
        canvas,
        '!',
        center + Offset(0, 7 * scale),
        color: Colors.white,
        fontSize: 20 * scale,
        weight: FontWeight.w900,
      );
    } else if (definition.type == DepartmentType.produce) {
      final sparklePaint = _p['sparkle']!;
      for (var index = 0; index < 3; index++) {
        final sparkle = center +
            Offset(
              (-22 + index * 22) * scale,
              (-8 + sin(animationTime * 2 + index) * 4) * scale,
            );
        canvas.drawCircle(sparkle, (1.2 + pulse) * scale, sparklePaint);
      }
    }

    final label = departmentLabels[definition.type] ?? definition.name;
    _stationLabel(
      canvas,
      center + Offset(0, 43 * scale),
      '$label $stock/$capacity',
    );
  }

  void _drawDepartmentProducts({
    required Canvas canvas,
    required Offset center,
    required DepartmentDefinition definition,
    required int count,
    required double scale,
  }) {
    final stemPaint = _p['produceStem']!;
    final refrigeratedBoxPaint = _p['refrigeratedBox']!;
    final refrigeratedLabelPaint = _p['refrigeratedLabel']!;
    final beautyCapPaint = _p['beautyCap']!;
    final electronicsBoxPaint = _p['electronicsBox']!;
    final electronicsLedPaint = _p['electronicsLed']!;

    for (var index = 0; index < count; index++) {
      final row = index ~/ 4;
      final column = index % 4;
      final productCenter =
          center + Offset((-20 + column * 13) * scale, (-6 + row * 15) * scale);
      switch (definition.type) {
        case DepartmentType.produce:
          canvas.drawCircle(
              productCenter,
              5 * scale,
              index.isEven
                  ? _p['produceGreen']!
                  : _p['produceRed']!);
          canvas.drawLine(
            productCenter - Offset(0, 4 * scale),
            productCenter - Offset(-2 * scale, 8 * scale),
            stemPaint,
          );
          break;
        case DepartmentType.refrigerated:
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                center: productCenter,
                width: 8 * scale,
                height: 12 * scale,
              ),
              Radius.circular(2 * scale),
            ),
            refrigeratedBoxPaint,
          );
          canvas.drawRect(
            Rect.fromCenter(
              center: productCenter - Offset(0, 3 * scale),
              width: 8 * scale,
              height: 3 * scale,
            ),
            refrigeratedLabelPaint,
          );
          break;
        case DepartmentType.beauty:
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                center: productCenter,
                width: 7 * scale,
                height: 13 * scale,
              ),
              Radius.circular(3 * scale),
            ),
            index.isEven ? _p['beautyPink']! : _p['beautyPurple']!,
          );
          canvas.drawRect(
            Rect.fromCenter(
              center: productCenter - Offset(0, 7 * scale),
              width: 4 * scale,
              height: 3 * scale,
            ),
            beautyCapPaint,
          );
          break;
        case DepartmentType.electronics:
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                center: productCenter,
                width: 11 * scale,
                height: 9 * scale,
              ),
              Radius.circular(2 * scale),
            ),
            electronicsBoxPaint,
          );
          canvas.drawCircle(
            productCenter,
            2 * scale,
            electronicsLedPaint,
          );
          break;
        case DepartmentType.bakery:
          canvas.drawOval(
            Rect.fromCenter(
              center: productCenter,
              width: 11 * scale,
              height: 7 * scale,
            ),
            index.isEven ? _p['bakeryLight']! : _p['bakeryDark']!,
          );
          break;
        case DepartmentType.generalGoods:
          break;
      }
    }
  }

  double _sceneScale(Rect market) => (market.width / 520).clamp(0.64, 1.0);

  void _drawEntrance(Canvas canvas, Rect market) {
    final center = _point(market, GameController.entrance);
    final door = Rect.fromCenter(center: center, width: 74, height: 34);
    canvas.drawRRect(
      RRect.fromRectAndRadius(door, const Radius.circular(12)),
      _p['entranceDoor']!,
    );
    _text(
      canvas,
      'ENTRANCE',
      center + const Offset(0, 2),
      color: const Color(0xFF163F2E),
      fontSize: 11,
      weight: FontWeight.w800,
    );
  }

  void _drawStockRoom(Canvas canvas, Rect market) {
    final center = _point(market, GameController.stockZone);
    _interactionGlow(canvas, market, GameController.stockZone, 0.13);

    _drawStationBox(
      canvas: canvas,
      center: center,
      width: 74,
      height: 58,
      depth: 15,
      faceColor: const Color(0xFFE0A45B),
      sideColor: const Color(0xFFB56B2A),
      topColor: const Color(0xFFF2B86A),
      edgeColor: const Color(0xFF9B6230),
      radius: 12,
    );
    final gratePaint = _p['stationBoxGrate']!;
    canvas.drawLine(
      center + const Offset(-26, -15),
      center + const Offset(26, 15),
      gratePaint,
    );
    canvas.drawLine(
      center + const Offset(26, -15),
      center + const Offset(-26, 15),
      gratePaint,
    );
    _stationLabel(canvas, center + const Offset(0, 39), storageLabel);
  }

  void _drawShelf(Canvas canvas, Rect market) {
    final center = _point(market, GameController.shelfZone);
    _interactionGlow(canvas, market, GameController.shelfZone, 0.14);

    _drawStationBox(
      canvas: canvas,
      center: center,
      width: 112,
      height: 86,
      depth: 16,
      faceColor: const Color(0xFF5B8DEF),
      sideColor: const Color(0xFF315EAC),
      topColor: const Color(0xFF7FAAF0),
      edgeColor: const Color(0xFF315EAC),
      radius: 14,
    );
    final dividerPaint = _p['shelfDividers']!;
    for (final dy in [-19.0, 5.0, 29.0]) {
      canvas.drawLine(
        center + Offset(-46, dy),
        center + Offset(46, dy),
        dividerPaint,
      );
    }

    final productPaints = [_p['shelfProduct1']!, _p['shelfProduct2']!, _p['shelfProduct3']!];
    final productCount = min(9, game.shelfStock);
    for (var index = 0; index < productCount; index++) {
      final row = index ~/ 3;
      final column = index % 3;
      final productCenter = center + Offset(-27 + column * 27, -28 + row * 24);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: productCenter, width: 15, height: 17),
          const Radius.circular(4),
        ),
        productPaints[index % 3],
      );
    }
    if (game.shelfStock == 0) {
      canvas.drawRect(
        Rect.fromCenter(
          center: center + const Offset(0, 8),
          width: 58,
          height: 18,
        ),
        _p['shelfEmpty']!,
      );
    }
    _stationLabel(
      canvas,
      center + const Offset(0, 55),
      '$shelfLabel ${game.shelfStock}/${game.shelfCapacity}',
    );
  }

  void _drawCheckout(Canvas canvas, Rect market) {
    final center = _point(market, GameController.checkoutZone);
    _interactionGlow(canvas, market, GameController.checkoutZone, 0.13);

    _drawStationBox(
      canvas: canvas,
      center: center,
      width: 96,
      height: 62,
      depth: 14,
      faceColor: const Color(0xFFE85D75),
      sideColor: const Color(0xFFB83D58),
      topColor: const Color(0xFFF06D8A),
      edgeColor: const Color(0xFF8E3044),
      radius: 14,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: center + const Offset(17, -10),
          width: 30,
          height: 22,
        ),
        const Radius.circular(6),
      ),
      _p['checkoutScreen']!,
    );
    canvas.drawCircle(
      center + const Offset(-24, -7),
      9,
      _p['checkoutScanner']!,
    );
    _drawQueueGuide(canvas, market);
    _stationLabel(canvas, center + const Offset(0, 39), checkoutLabel);
  }

  void _drawQueueGuide(Canvas canvas, Rect market) {
    final checkoutCenter = _point(market, GameController.checkoutZone);
    final queueCustomers = game.checkoutQueue;
    if (queueCustomers.isEmpty) {
      return;
    }

    final laneStart = Offset(checkoutCenter.dx - 118, checkoutCenter.dy + 4);
    final laneEnd = Offset(checkoutCenter.dx - 118, checkoutCenter.dy + 92);
    canvas.drawLine(
      laneStart,
      laneEnd,
      _p['queueGuide']!,
    );

    final customerSkinPaint = _p['queueCustomerSkin']!;
    for (var index = 0; index < min(4, queueCustomers.length); index++) {
      final offset = Offset(laneStart.dx + 6, laneStart.dy + 18 + index * 22);
      _dynamicPaint.color = queueCustomers[index].color.withValues(alpha: 0.95);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: offset, width: 22, height: 22),
          const Radius.circular(8),
        ),
        _dynamicPaint,
      );
      canvas.drawCircle(
        offset + const Offset(0, -5),
        7,
        customerSkinPaint,
      );
    }
  }

  void _drawStationBox({
    required Canvas canvas,
    required Offset center,
    required double width,
    required double height,
    required double depth,
    required Color faceColor,
    required Color sideColor,
    required Color topColor,
    required Color edgeColor,
    required double radius,
  }) {
    final shadowCenter = center + const Offset(6, 7);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: shadowCenter, width: width, height: height),
        Radius.circular(radius),
      ),
      _p['stationBoxShadow']!,
    );

    _dynamicPaint.color = topColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: center + Offset(0, -depth * 0.6),
          width: width,
          height: depth,
        ),
        Radius.circular(radius - 2),
      ),
      _dynamicPaint,
    );

    _dynamicPaint.color = sideColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: center + Offset(width * 0.4, 4),
          width: depth,
          height: height,
        ),
        Radius.circular(radius - 2),
      ),
      _dynamicPaint,
    );

    final faceRect = Rect.fromCenter(center: center, width: width, height: height);
    _dynamicPaint.color = faceColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(faceRect, Radius.circular(radius)),
      _dynamicPaint,
    );

    _dynamicPaint.color = edgeColor;
    _dynamicPaint.style = PaintingStyle.stroke;
    _dynamicPaint.strokeWidth = 3;
    canvas.drawRRect(
      RRect.fromRectAndRadius(faceRect, Radius.circular(radius)),
      _dynamicPaint,
    );
    _dynamicPaint.style = PaintingStyle.fill; // Reset

    _dynamicPaint.color = Colors.white.withValues(alpha: 0.32);
    canvas.drawRect(
      Rect.fromCenter(
        center: center + Offset(-width * 0.16, -height * 0.18),
        width: width * 0.46,
        height: 6,
      ),
      _dynamicPaint,
    );
  }

  void _drawExpansion(Canvas canvas, Rect market) {
    final center = _point(market, GameController.bakeryZone);
    final unlocked = game.bakeryUnlocked;
    _interactionGlow(canvas, market, GameController.bakeryZone, 0.13);
    final zone = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: 105, height: 91),
      const Radius.circular(18),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: center + const Offset(4, 5),
          width: 105,
          height: 91,
        ),
        const Radius.circular(18),
      ),
      _p['expansionShadow']!,
    );
    canvas.drawRRect(zone, unlocked ? _p['expansionUnlocked']! : _p['expansionLocked']!);
    canvas.drawRRect(zone, unlocked ? _p['expansionUnlockedBorder']! : _p['expansionLockedBorder']!);
    canvas.drawRect(
      Rect.fromCenter(
        center: center + const Offset(0, -21),
        width: 54,
        height: 8,
      ),
      _p['expansionHighlight']!,
    );
    _text(
      canvas,
      unlocked ? '🥐' : '🔒',
      center - const Offset(0, 19),
      fontSize: 23,
    );
    if (unlocked) {
      final readyPaint = _p['bakeryReady']!;
      final emptyPaint = _p['bakeryEmpty']!;
      for (var index = 0; index < GameBalance.bakeryReadyCapacity; index++) {
        final ready = index < game.bakeryReadyStock;
        canvas.drawOval(
          Rect.fromCenter(
            center: center + Offset(-21 + index * 14, 2),
            width: 10,
            height: 6,
          ),
          ready ? readyPaint : emptyPaint,
        );
      }
    }
    _text(
      canvas,
      unlocked ? bakeryLabel : bakeryLockedLabel,
      center + const Offset(0, 17),
      color: const Color(0xFF645E55),
      fontSize: 10,
      weight: FontWeight.w800,
    );
    if (unlocked) {
      _text(
        canvas,
        bakeryReadyLabel,
        center + const Offset(0, 31),
        color: const Color(0xFF8A5B17),
        fontSize: 9,
        weight: FontWeight.w900,
      );
    }
  }

  void _drawMovementTarget(Canvas canvas, Rect market) {
    final target = game.movementTarget;
    if (target == null) {
      return;
    }
    final center = _point(market, target);
    final pulse = 10 + sin(animationTime * 6) * 2;
    canvas.drawCircle(
      center,
      pulse,
      _p['movementTargetRing']!,
    );
    canvas.drawCircle(center, 3.5, _p['movementTarget']!);
  }

  void _drawStockerRoute(Canvas canvas, Rect market) {
    if (!game.isStaffHired(StaffRole.stocker)) return;
    
    final department = game.stockerTargetDepartment;
    if (department == null) return;
    
    _p.putIfAbsent('stockerRoute', () {
      final color = DepartmentCatalog.find(department)?.color ?? const Color(0xFF5B8DEF);
      return Paint()
        ..color = color.withValues(alpha: 0.24)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
    });

    final from = _point(market, GameController.stockerPickupZone);
    final to = _point(market, game.departmentZone(department));
    final delta = to - from;
    final distance = delta.distance;
    if (distance <= 0) return;
    
    final direction = delta / distance;
    final paint = _p['stockerRoute']!;
    for (var step = 0.0; step < distance; step += 12) {
      final segmentEnd = min(step + 6, distance);
      canvas.drawLine(
        from + direction * step,
        from + direction * segmentEnd,
        paint,
      );
    }
  }

  void _drawCashier(Canvas canvas, Rect market, int workerIndex) {
    final center = _point(
      market,
      GameController.checkoutZone +
          Offset(0.075 + workerIndex * 0.035, 0.035 + workerIndex * 0.055),
    );
    final serving = game.staffStatus(StaffRole.cashier) == StaffStatus.serving;
    final bounce = serving ? sin(animationTime * 12) * 1.2 : 0.0;
    final bodyCenter = center + Offset(0, bounce);

    canvas.drawOval(
      Rect.fromCenter(
        center: center + const Offset(0, 16),
        width: 30,
        height: 10,
      ),
      _p['cashierShadow']!,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: bodyCenter, width: 27, height: 34),
        const Radius.circular(10),
      ),
      _p['cashierUniform']!,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: bodyCenter + const Offset(0, 5),
          width: 19,
          height: 17,
        ),
        const Radius.circular(5),
      ),
      _p['cashierApron']!,
    );
    canvas.drawCircle(
      bodyCenter - const Offset(0, 21),
      10,
      _p['cashierSkin']!,
    );
    canvas.drawArc(
      Rect.fromCircle(center: bodyCenter - const Offset(0, 23), radius: 11),
      pi,
      pi,
      true,
      _p['cashierHair']!,
    );
    final cashierFace = bodyCenter - const Offset(0, 21);
    final eyePaint = _p['cashierEye']!;
    canvas.drawCircle(cashierFace + const Offset(-3.4, 0.5), 1.2, eyePaint);
    canvas.drawCircle(cashierFace + const Offset(3.4, 0.5), 1.2, eyePaint);
    canvas.drawArc(
      Rect.fromCenter(
        center: cashierFace + const Offset(0, 4),
        width: 7,
        height: serving ? 5 : 3,
      ),
      0,
      pi,
      false,
      _p['cashierFeature']!,
    );
    if (serving) {
      final scannerAlpha = (150 + (sin(animationTime * 15) + 1) * 50).round().clamp(0, 255);
      _dynamicPaint.color = Color.fromARGB(scannerAlpha, 255, 224, 102);
      canvas.drawCircle(
        _point(market, GameController.checkoutZone) + const Offset(-24, -7),
        12,
        _dynamicPaint,
      );
      _bubble(canvas, bodyCenter - const Offset(16, 39), '💳');
    }
  }

  void _drawStaffMember(
    Canvas canvas,
    Rect market,
    StaffRole role,
    int workerIndex,
  ) {
    final status = game.staffStatus(role);
    final active =
        status != StaffStatus.idle &&
        status != StaffStatus.waitingForStock &&
        status != StaffStatus.waitingForShelf;
    final workerOffset = Offset((workerIndex % 2) * 0.025, workerIndex * 0.035);
    final basePosition =
        switch (role) {
          StaffRole.stocker => game.stockerPosition,
          StaffRole.cleaner => Offset(
            0.52 + sin(animationTime * 0.7) * 0.09,
            0.84,
          ),
          StaffRole.baker =>
            GameController.bakeryZone + const Offset(-0.13, -0.01),
          StaffRole.manager => const Offset(0.22, 0.25),
          StaffRole.courier =>
            status == StaffStatus.delivering
                ? Offset(
                    0.18 + ((sin(animationTime * 1.2) + 1) / 2) * 0.25,
                    0.61 + cos(animationTime * 1.2) * 0.035,
                  )
                : const Offset(0.29, 0.61),
          StaffRole.promoter => const Offset(0.32, 0.18),
          StaffRole.cashier => GameController.checkoutZone,
        } +
        workerOffset;
    final bounce = active ? sin(animationTime * 8 + role.index) * 1.3 : 0.0;
    final center = _point(market, basePosition);
    final bodyCenter = center + Offset(0, bounce);
    
    _dynamicPaint.color = switch (role) {
      StaffRole.stocker => const Color(0xFF5B8DEF),
      StaffRole.cleaner => const Color(0xFF1FA8A8),
      StaffRole.baker => const Color(0xFFF6A623),
      StaffRole.manager => const Color(0xFF8B66D8),
      StaffRole.courier => const Color(0xFFE85D75),
      StaffRole.promoter => const Color(0xFF38B879),
      StaffRole.cashier => const Color(0xFF315F8F),
    };
    final hairPaint = Paint()..color = switch (role) {
      StaffRole.stocker => const Color(0xFF473126),
      StaffRole.cleaner => const Color(0xFF2F3E52),
      StaffRole.baker => const Color(0xFF8A623D),
      StaffRole.manager => const Color(0xFF6B4528),
      StaffRole.courier => const Color(0xFF2F3E52),
      StaffRole.promoter => const Color(0xFF473126),
      StaffRole.cashier => const Color(0xFF473126),
    };

    canvas.drawOval(
      Rect.fromCenter(
        center: center + const Offset(0, 17),
        width: 29,
        height: 10,
      ),
      _p['staffShadow']!,
    );

    final legPaint = _p['staffLegs']!;
    canvas.drawLine(bodyCenter + const Offset(-5, 9), bodyCenter + const Offset(-6, 21), legPaint);
    canvas.drawLine(bodyCenter + const Offset(5, 9), bodyCenter + const Offset(6, 21), legPaint);

    final torso = RRect.fromRectAndRadius(
      Rect.fromCenter(center: bodyCenter, width: 26, height: 33),
      const Radius.circular(10),
    );
    canvas.drawRRect(torso, _dynamicPaint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: bodyCenter + const Offset(0, 5), width: 18, height: 16),
        const Radius.circular(5),
      ),
      _p['staffApron']!,
    );

    final face = bodyCenter - const Offset(0, 21);
    canvas.drawCircle(face, 10, _p['staffSkin']!);
    canvas.drawArc(
      Rect.fromCircle(center: face - const Offset(0, 2), radius: 11),
      pi,
      pi,
      true,
      hairPaint,
    );
    final eyePaint = _p['staffEye']!;
    canvas.drawCircle(face + const Offset(-3.3, 0.5), 1.1, eyePaint);
    canvas.drawCircle(face + const Offset(3.3, 0.5), 1.1, eyePaint);
    canvas.drawArc(
      Rect.fromCenter(center: face + const Offset(0, 4), width: 7, height: active ? 5 : 3),
      0,
      pi,
      false,
      _p['staffFeature']!,
    );

    switch (role) {
      case StaffRole.stocker:
        if (game.stockerCarried > 0) {
          final target = game.stockerTargetDepartment;
          final targetDefinition = target == null ? null : DepartmentCatalog.find(target);
          _dynamicPaint.color = targetDefinition?.color ?? const Color(0xFFF6A623);
          final box = RRect.fromRectAndRadius(
            Rect.fromCenter(center: bodyCenter + const Offset(15, 4), width: 15, height: 13),
            const Radius.circular(3),
          );
          canvas.drawRRect(box, _dynamicPaint);
          canvas.drawLine(
            bodyCenter + const Offset(8, 1),
            bodyCenter + const Offset(22, 1),
            _p['staffStockerBoxLine']!,
          );
        }
        if (workerIndex == 0) {
          final bubble = switch (status) {
            StaffStatus.waitingForStock => '📦?',
            StaffStatus.waitingForShelf => '✓',
            _ => game.stockerCarried > 0
                ? DepartmentCatalog.find(game.stockerTargetDepartment ?? DepartmentType.generalGoods)?.emoji ?? '📦'
                : '…',
          };
          _bubble(canvas, bodyCenter - const Offset(15, 39), bubble);
        }
        break;
      case StaffRole.cleaner:
        canvas.drawLine(
          bodyCenter + const Offset(8, -5),
          bodyCenter + const Offset(18, 21),
          _p['staffCleanerMopStick']!,
        );
        final mopHeadPaint = _p['staffCleanerMopHead']!;
        for (var offset = -4.0; offset <= 4; offset += 4) {
          canvas.drawLine(
            bodyCenter + Offset(18, 21),
            bodyCenter + Offset(18 + offset, 25),
            mopHeadPaint,
          );
        }
        if (workerIndex == 0 && status == StaffStatus.cleaning) {
          _bubble(canvas, bodyCenter - const Offset(15, 39), '✨');
        }
        break;
      case StaffRole.baker:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: bodyCenter + const Offset(0, -10), width: 22, height: 6),
            const Radius.circular(4),
          ),
          _p['staffBakerHat']!,
        );
        if (workerIndex == 0 && status == StaffStatus.baking) {
          _bubble(canvas, bodyCenter - const Offset(15, 39), '🥐');
        }
        break;
      case StaffRole.manager:
        final clipboard = RRect.fromRectAndRadius(
          Rect.fromCenter(center: bodyCenter + const Offset(15, 2), width: 14, height: 18),
          const Radius.circular(3),
        );
        canvas.drawRRect(clipboard, _p['staffManagerClipboard']!);
        _dynamicPaint.color = const Color(0xFF5F477E);
        _dynamicPaint.style = PaintingStyle.stroke;
        _dynamicPaint.strokeWidth = 1.4;
        canvas.drawRRect(clipboard, _dynamicPaint);
        _dynamicPaint.style = PaintingStyle.fill;
        canvas.drawLine(
          bodyCenter + const Offset(11, 0),
          bodyCenter + const Offset(19, 0),
          _p['staffManagerClipboardLine']!,
        );
        if (workerIndex == 0) {
          _bubble(canvas, bodyCenter - const Offset(15, 39), '📈');
        }
        break;
      case StaffRole.courier:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: bodyCenter + const Offset(0, -11), width: 24, height: 7),
            const Radius.circular(4),
          ),
          _p['staffCourierHat']!,
        );
        if (workerIndex == 0 && status == StaffStatus.delivering) {
          _bubble(canvas, bodyCenter - const Offset(15, 39), '🚚');
        }
        break;
      case StaffRole.promoter:
        final signCenter = bodyCenter + const Offset(17, -2);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: signCenter, width: 17, height: 14),
            const Radius.circular(3),
          ),
          _p['staffPromoterSign']!,
        );
        canvas.drawLine(
          signCenter + const Offset(0, 7),
          signCenter + const Offset(0, 20),
          _p['staffPromoterSignStick']!,
        );
        if (workerIndex == 0) {
          _bubble(canvas, bodyCenter - const Offset(15, 39), '📣');
        }
        break;
      case StaffRole.cashier:
        break;
    }

    canvas.drawCircle(
      bodyCenter + const Offset(-11, 12),
      7,
      _p['staffLevelBadge']!,
    );
    _text(
      canvas,
      '${game.staffLevel(role)}',
      bodyCenter + const Offset(-11, 12),
      color: Colors.white,
      fontSize: 8,
      weight: FontWeight.w900,
    );
  }

  void _drawPlayer(Canvas canvas, Offset center) {
    final walking = game.movement.distance > 0.05;
    final bounce = walking ? sin(animationTime * 11) * 2.2 : 0.0;
    final bodyCenter = center + Offset(0, bounce);

    canvas.drawOval(
      Rect.fromCenter(
        center: center + const Offset(0, 19),
        width: 39,
        height: 14,
      ),
      _p['playerShadow']!,
    );

    final legPaint = _p['playerLegs']!;
    final stride = walking ? sin(animationTime * 11) * 6 : 0.0;
    canvas.drawLine(
      bodyCenter + const Offset(-7, 12),
      bodyCenter + Offset(-7 + stride, 27),
      legPaint,
    );
    canvas.drawLine(
      bodyCenter + const Offset(7, 12),
      bodyCenter + Offset(7 - stride, 27),
      legPaint,
    );

    final torso = RRect.fromRectAndRadius(
      Rect.fromCenter(center: bodyCenter, width: 34, height: 42),
      const Radius.circular(13),
    );
    canvas.drawRRect(torso, _p['playerTorso']!);
    canvas.drawRRect(torso, _p['playerTorsoBorder']!);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: bodyCenter + const Offset(0, 5),
          width: 24,
          height: 24,
        ),
        const Radius.circular(8),
      ),
      _p['playerApron']!,
    );
    canvas.drawCircle(
      bodyCenter - const Offset(0, 27),
      15,
      _p['playerSkin']!,
    );

    final hair = _p['playerHair']!;
    canvas.drawArc(
      Rect.fromCircle(center: bodyCenter - const Offset(0, 29), radius: 17),
      pi,
      pi,
      true,
      hair,
    );
    canvas.drawCircle(bodyCenter + const Offset(12, -31), 6, hair);
    final eyePaint = _p['playerEye']!;
    canvas.drawCircle(bodyCenter + const Offset(-5, -26), 1.6, eyePaint);
    canvas.drawCircle(bodyCenter + const Offset(5, -26), 1.6, eyePaint);

    final featurePaint = _p['playerFeature']!;
    canvas.drawLine(bodyCenter + const Offset(-8, -31), bodyCenter + const Offset(-3, -32), featurePaint);
    canvas.drawLine(bodyCenter + const Offset(3, -32), bodyCenter + const Offset(8, -31), featurePaint);
    canvas.drawArc(
      Rect.fromCenter(center: bodyCenter + const Offset(0, -21), width: 11, height: 7),
      0,
      pi,
      false,
      featurePaint,
    );

    if (game.carried > 0) {
      final carriedDefinition = DepartmentCatalog.find(
        game.carriedDepartment ?? DepartmentType.generalGoods,
      );
      _dynamicPaint.color = carriedDefinition?.color ?? const Color(0xFFF6A623);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: bodyCenter + const Offset(22, 5),
            width: 24,
            height: 28,
          ),
          const Radius.circular(6),
        ),
        _dynamicPaint,
      );
      _text(
        canvas,
        '${game.carried}',
        bodyCenter + const Offset(22, 5),
        fontSize: 12,
        color: Colors.white,
        weight: FontWeight.w900,
      );
      _text(
        canvas,
        carriedDefinition?.emoji ?? '📦',
        bodyCenter + const Offset(30, -8),
        fontSize: 10,
      );
    }
  }

  void _drawCustomer(Canvas canvas, Offset center, MarketCustomer customer) {
    canvas.drawOval(
      Rect.fromCenter(center: center + const Offset(0, 13), width: 31, height: 12),
      _p['customerShadow']!,
    );

    final bodyRect = Rect.fromCenter(center: center + const Offset(0, 3), width: 26, height: 32);
    final body = RRect.fromRectAndRadius(bodyRect, const Radius.circular(10));
    _dynamicPaint.color = customer.color;
    canvas.drawRRect(body, _dynamicPaint);
    canvas.drawRRect(body, _p['customerBorder']!);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center + const Offset(0, 2), width: 18, height: 12),
        const Radius.circular(5),
      ),
      _p['customerApron']!,
    );
    canvas.drawCircle(center - const Offset(0, 20), 11, _p['customerSkin']!);
    final customerFace = center - const Offset(0, 20);

    const hairColors = <Color>[
      Color(0xFF3B2A24),
      Color(0xFF7A4F2B),
      Color(0xFF2F3E52),
      Color(0xFF8A623D),
    ];
    final hairPaint = _customerHairPaints.putIfAbsent(
        customer.id.abs() % hairColors.length,
        () => Paint()..color = hairColors[customer.id.abs() % hairColors.length]);
    canvas.drawArc(
      Rect.fromCircle(center: customerFace - const Offset(0, 1.5), radius: 12),
      pi,
      pi,
      true,
      hairPaint,
    );
    final eyePaint = _p['customerEye']!;
    canvas.drawCircle(customerFace + const Offset(-3.5, 0.5), 1.1, eyePaint);
    canvas.drawCircle(customerFace + const Offset(3.5, 0.5), 1.1, eyePaint);

    final featurePaint = _p['customerFeature']!;
    final isWorried = customer.phase == CustomerPhase.shopping && game.shelfStock == 0;
    final isHappy = customer.hasProduct || customer.phase == CustomerPhase.paying || customer.phase == CustomerPhase.leaving;
    if (isWorried) {
      canvas.drawArc(
        Rect.fromCenter(center: customerFace + const Offset(0, 6), width: 7, height: 4),
        pi,
        pi,
        false,
        featurePaint,
      );
      canvas.drawLine(customerFace + const Offset(-6, -3), customerFace + const Offset(-2, -2), featurePaint);
      canvas.drawLine(customerFace + const Offset(2, -2), customerFace + const Offset(6, -3), featurePaint);
    } else if (isHappy) {
      canvas.drawArc(
        Rect.fromCenter(center: customerFace + const Offset(0, 4), width: 8, height: 5),
        0,
        pi,
        false,
        featurePaint,
      );
    } else {
      canvas.drawLine(customerFace + const Offset(-3, 5), customerFace + const Offset(3, 5), featurePaint);
    }

    if (customer.hasProduct) {
      canvas.drawCircle(center + const Offset(15, 2), 7, _p['customerProduct']!);
    }
    if (customer.isVip) {
      canvas.drawCircle(center + const Offset(15, -27), 8, _p['customerVipBadge']!);
      _text(
        canvas,
        '★',
        center + const Offset(15, -27),
        color: const Color(0xFF8A5B17),
        fontSize: 9,
        weight: FontWeight.w900,
      );
    }
    if (customer.phase == CustomerPhase.shopping && game.shelfStock == 0) {
      _bubble(canvas, center - const Offset(18, 45), '📦?');
    }
    if (customer.phase == CustomerPhase.paying) {
      _bubble(canvas, center - const Offset(18, 45), '💰');
    }
  }

  void _interactionGlow(Canvas canvas, Rect market, Offset zone, double radius) {
    final center = _point(market, zone);
    final active = (game.playerPosition - zone).distance <= radius;
    final pulse = active ? 0.55 + sin(animationTime * 4) * 0.12 : 0.35;
    final ringRadius = min(market.width, market.height) * min(radius * 0.58, 0.075);
    canvas.drawCircle(center, ringRadius, active ? _p['interactionGlowActive']! : _p['interactionGlowInactive']!);
    if (active) {
      canvas.drawCircle(center, ringRadius * pulse, _p['interactionRing']!);
    }
  }

  void _stationLabel(Canvas canvas, Offset center, String label) {
    _textPainter.textDirection = textDirection;
    _textPainter.text = TextSpan(
      text: label,
      style: const TextStyle(
        color: Color(0xFF34433C),
        fontSize: 11,
        fontWeight: FontWeight.w800,
        height: 1.05,
      ),
    );
    _textPainter.layout();
    final bubble = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center,
        width: _textPainter.width + 18,
        height: _textPainter.height + 9,
      ),
      const Radius.circular(10),
    );
    canvas.drawRRect(bubble, _p['stationLabelBubble']!);
    _textPainter.paint(
      canvas,
      center - Offset(_textPainter.width / 2, _textPainter.height / 2),
    );
  }

  void _bubble(Canvas canvas, Offset center, String content) {
    canvas.drawCircle(center, 17, _p['bubbleFill']!);
    _text(canvas, content, center, fontSize: 13);
  }

  Offset _point(Rect rect, Offset normalized) {
    return Offset(
      rect.left + rect.width * normalized.dx,
      rect.top + rect.height * normalized.dy,
    );
  }

  void _text(
    Canvas canvas,
    String value,
    Offset center, {
    Color color = const Color(0xFF273043),
    double fontSize = 12,
    FontWeight weight = FontWeight.w600,
  }) {
    _textPainter.textDirection = textDirection;
    _textPainter.text = TextSpan(
      text: value,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: weight,
        height: 1.05,
      ),
    );
    _textPainter.layout();
    _textPainter.paint(
      canvas,
      center - Offset(_textPainter.width / 2, _textPainter.height / 2),
    );
  }

  void _drawFloatingEffects(Canvas canvas, Rect market) {
    if (game.floatingEffects.isEmpty) return;
    for (final effect in game.floatingEffects) {
      final pos = _point(market, effect.currentPosition);
      final textStyle = TextStyle(
        color: effect.color.withValues(alpha: effect.opacity),
        fontSize: effect.fontSize,
        fontWeight: FontWeight.bold,
        shadows: [
          Shadow(
            color: Colors.black.withValues(alpha: effect.opacity * 0.5),
            blurRadius: 3,
            offset: const Offset(1, 1),
          ),
        ],
      );
      _textPainter.text = TextSpan(text: effect.text, style: textStyle);
      _textPainter.textDirection = TextDirection.ltr;
      _textPainter.layout();
      _textPainter.paint(
        canvas,
        pos - Offset(_textPainter.width / 2, _textPainter.height / 2),
      );
    }
  }

  /// Renders drifting ambient seasonal particles on top of the scene.
  ///
  /// Particle positions are derived purely from [animationTime] so they
  /// look animated without requiring any mutable state in the painter.
  void _drawSeasonalParticles(Canvas canvas, Rect market) {
    final count = season.maxParticles;
    if (count == 0) return;

    final speed = season.particleSpeed;
    final emoji = season.particleEmoji;
    final t = animationTime * speed;

    for (var i = 0; i < count; i++) {
      // Deterministic seed per particle.
      final seed = (i * 1.618 + 0.3);
      final xBase = (seed * 0.37 + 0.05) % 0.90 + 0.05;
      final yPhase = (t * 0.12 + seed * 1.7) % 1.0;
      final xWobble = sin(t * 0.8 + seed * 2.1) * 0.025;

      final x = xBase + xWobble;
      final y = yPhase;

      // Fade near top/bottom edges.
      final edgeFade = sin(y * pi).clamp(0.0, 1.0) * 0.85 + 0.15;
      final opacity = (edgeFade * 0.55).clamp(0.0, 1.0);

      final pos = _point(market, Offset(x, y));
      final scale = _sceneScale(market);
      final fontSize = (9.0 + (seed * 3.1) % 5.0) * scale;

      final style = TextStyle(
        fontSize: fontSize,
        color: Colors.white.withValues(alpha: opacity),
      );
      _textPainter.text = TextSpan(text: emoji, style: style);
      _textPainter.textDirection = TextDirection.ltr;
      _textPainter.layout();
      _textPainter.paint(
        canvas,
        pos - Offset(_textPainter.width / 2, _textPainter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant MarketPainter oldDelegate) =>
      oldDelegate.game != game ||
      oldDelegate.storageLabel != storageLabel ||
      oldDelegate.shelfLabel != shelfLabel ||
      oldDelegate.checkoutLabel != checkoutLabel ||
      oldDelegate.bakeryLabel != bakeryLabel ||
      oldDelegate.bakeryReadyLabel != bakeryReadyLabel ||
      oldDelegate.bakeryLockedLabel != bakeryLockedLabel ||
      oldDelegate.departmentLabels != departmentLabels ||
      oldDelegate.textDirection != textDirection ||
      oldDelegate.season != season;
}
