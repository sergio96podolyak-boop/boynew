import 'dart:math';

import 'package:flutter/material.dart';

import '../game/game_controller.dart';
import '../game/game_models.dart';

class MarketPainter extends CustomPainter {
  const MarketPainter({
    required this.game,
    required this.animationTime,
    required this.storageLabel,
    required this.shelfLabel,
    required this.checkoutLabel,
    required this.bakeryLabel,
    required this.bakeryReadyLabel,
    required this.bakeryLockedLabel,
    required this.textDirection,
  });

  final GameController game;
  final double animationTime;
  final String storageLabel;
  final String shelfLabel;
  final String checkoutLabel;
  final String bakeryLabel;
  final String bakeryReadyLabel;
  final String bakeryLockedLabel;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final market = Rect.fromLTWH(8, 6, size.width - 16, size.height - 12);
    _drawMarket(canvas, market);
    _drawEntrance(canvas, market);
    _drawStockRoom(canvas, market);
    _drawShelf(canvas, market);
    _drawCheckout(canvas, market);
    _drawExpansion(canvas, market);
    _drawMovementTarget(canvas, market);

    if (game.isStaffHired(StaffRole.cashier)) {
      _drawCashier(canvas, market);
    }
    for (final customer in game.customers) {
      _drawCustomer(canvas, _point(market, customer.position), customer);
    }
    _drawPlayer(canvas, _point(market, game.playerPosition));
  }

  void _drawMarket(Canvas canvas, Rect rect) {
    final shadow = RRect.fromRectAndRadius(
      rect.shift(const Offset(0, 7)),
      const Radius.circular(30),
    );
    canvas.drawRRect(shadow, Paint()..color = const Color(0x1F243529));

    final room = RRect.fromRectAndRadius(rect, const Radius.circular(28));
    canvas.drawRRect(
      room,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFFFF6E2),
            const Color(0xFFF3D8A6),
            const Color(0xFFE3BF76),
          ],
        ).createShader(rect),
    );

    canvas.save();
    canvas.clipRRect(room);

    final gridPaint = Paint()
      ..color = const Color(0x0A315F4A)
      ..strokeWidth = 0.6;
    final diamondPaint = Paint()
      ..color = const Color(0x06315F4A)
      ..strokeWidth = 0.5;

    final tile = 34.0;
    final halfTile = tile / 2;
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

    final glow = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.38, 0.16),
        radius: 1.05,
        colors: [const Color(0x55FFFFFF), const Color(0x00FFFFFF)],
      ).createShader(rect);
    canvas.drawRect(rect, glow);

    final vignette = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.5, 0.5),
        radius: 1.2,
        colors: [const Color(0x00000000), const Color(0x26000000)],
      ).createShader(rect);
    canvas.drawRect(rect, vignette);
    canvas.restore();

    canvas.drawRRect(
      room,
      Paint()
        ..color = const Color(0xFF315F4A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
  }

  void _drawEntrance(Canvas canvas, Rect market) {
    final center = _point(market, GameController.entrance);
    final door = Rect.fromCenter(center: center, width: 74, height: 34);
    canvas.drawRRect(
      RRect.fromRectAndRadius(door, const Radius.circular(12)),
      Paint()..color = const Color(0xFF83D3B0),
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
      canvas,
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
    canvas.drawLine(
      center + const Offset(-26, -15),
      center + const Offset(26, 15),
      Paint()
        ..color = const Color(0x669B6230)
        ..strokeWidth = 3,
    );
    canvas.drawLine(
      center + const Offset(26, -15),
      center + const Offset(-26, 15),
      Paint()
        ..color = const Color(0x669B6230)
        ..strokeWidth = 3,
    );
    _stationLabel(canvas, center + const Offset(0, 39), storageLabel);
  }

  void _drawShelf(Canvas canvas, Rect market) {
    final center = _point(market, GameController.shelfZone);
    _interactionGlow(canvas, market, GameController.shelfZone, 0.14);

    _drawStationBox(
      canvas,
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
    for (final dy in [-19.0, 5.0, 29.0]) {
      canvas.drawLine(
        center + Offset(-46, dy),
        center + Offset(46, dy),
        Paint()
          ..color = const Color(0xFFEAF1FF)
          ..strokeWidth = 4,
      );
    }

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
        Paint()
          ..color = [
            const Color(0xFFF6A623),
            const Color(0xFFE85D75),
            const Color(0xFF43AA8B),
          ][index % 3],
      );
    }
    if (game.shelfStock == 0) {
      canvas.drawRect(
        Rect.fromCenter(
          center: center + const Offset(0, 8),
          width: 58,
          height: 18,
        ),
        Paint()..color = const Color(0x33E85D75),
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
      canvas,
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
      Paint()..color = const Color(0xFF3B4054),
    );
    canvas.drawCircle(
      center + const Offset(-24, -7),
      9,
      Paint()..color = const Color(0xFFFFD166),
    );
    _drawQueueGuide(canvas, market);
    _stationLabel(canvas, center + const Offset(0, 39), checkoutLabel);
  }

  void _drawQueueGuide(Canvas canvas, Rect market) {
    final checkoutCenter = _point(market, GameController.checkoutZone);
    final queueCustomers = game.customers
        .where(
          (customer) =>
              customer.phase == CustomerPhase.checkout ||
              customer.phase == CustomerPhase.paying,
        )
        .toList();
    if (queueCustomers.isEmpty) {
      return;
    }

    final laneStart = Offset(checkoutCenter.dx - 118, checkoutCenter.dy + 4);
    final laneEnd = Offset(checkoutCenter.dx - 118, checkoutCenter.dy + 92);
    canvas.drawLine(
      laneStart,
      laneEnd,
      Paint()
        ..color = const Color(0x1F315F4A)
        ..strokeWidth = 2,
    );

    for (var index = 0; index < min(4, queueCustomers.length); index++) {
      final offset = Offset(laneStart.dx + 6, laneStart.dy + 18 + index * 22);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: offset, width: 22, height: 22),
          const Radius.circular(8),
        ),
        Paint()..color = queueCustomers[index].color.withValues(alpha: 0.95),
      );
      canvas.drawCircle(
        offset + const Offset(0, -5),
        7,
        Paint()..color = const Color(0xFFFFD3B6),
      );
    }
  }

  void _drawStationBox(
    Canvas canvas, {
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
      Paint()..color = const Color(0x18000000),
    );

    final faceRect = Rect.fromCenter(
      center: center,
      width: width,
      height: height,
    );
    final topRect = Rect.fromCenter(
      center: center + Offset(0, -depth * 0.6),
      width: width,
      height: depth,
    );
    final sideRect = Rect.fromCenter(
      center: center + Offset(width * 0.4, 4),
      width: depth,
      height: height,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(topRect, Radius.circular(radius - 2)),
      Paint()..color = topColor,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(sideRect, Radius.circular(radius - 2)),
      Paint()..color = sideColor,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(faceRect, Radius.circular(radius)),
      Paint()..color = faceColor,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(faceRect, Radius.circular(radius)),
      Paint()
        ..color = edgeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    canvas.drawRect(
      Rect.fromCenter(
        center: center + Offset(-width * 0.16, -height * 0.18),
        width: width * 0.46,
        height: 6,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.32),
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
      Paint()..color = const Color(0x14000000),
    );
    canvas.drawRRect(
      zone,
      Paint()
        ..color = unlocked ? const Color(0xFFFFE7B6) : const Color(0xFFF0ECE3),
    );
    canvas.drawRRect(
      zone,
      Paint()
        ..color = unlocked ? const Color(0xFFF6A623) : const Color(0xFFAAA59B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawRect(
      Rect.fromCenter(
        center: center + const Offset(0, -21),
        width: 54,
        height: 8,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.35),
    );
    _text(
      canvas,
      unlocked ? '🥐' : '🔒',
      center - const Offset(0, 19),
      fontSize: 23,
    );
    if (unlocked) {
      for (var index = 0; index < GameBalance.bakeryReadyCapacity; index++) {
        final ready = index < game.bakeryReadyStock;
        canvas.drawOval(
          Rect.fromCenter(
            center: center + Offset(-21 + index * 14, 2),
            width: 10,
            height: 6,
          ),
          Paint()
            ..color = ready ? const Color(0xFFE09A20) : const Color(0x33A98D62),
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
      Paint()
        ..color = const Color(0x6638B879)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(center, 3.5, Paint()..color = const Color(0xFF38B879));
  }

  void _drawCashier(Canvas canvas, Rect market) {
    final center = _point(
      market,
      GameController.checkoutZone + const Offset(0.075, 0.035),
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
      Paint()..color = const Color(0x22000000),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: bodyCenter, width: 27, height: 34),
        const Radius.circular(10),
      ),
      Paint()..color = const Color(0xFF315F8F),
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
      Paint()..color = const Color(0xFFF6A623),
    );
    canvas.drawCircle(
      bodyCenter - const Offset(0, 21),
      10,
      Paint()..color = const Color(0xFFFFD3B6),
    );
    canvas.drawArc(
      Rect.fromCircle(center: bodyCenter - const Offset(0, 23), radius: 11),
      pi,
      pi,
      true,
      Paint()..color = const Color(0xFF473126),
    );
    final cashierFace = bodyCenter - const Offset(0, 21);
    final cashierFeaturePaint = Paint()
      ..color = const Color(0xFF382B2A)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(
      cashierFace + const Offset(-3.4, 0.5),
      1.2,
      Paint()..color = const Color(0xFF382B2A),
    );
    canvas.drawCircle(
      cashierFace + const Offset(3.4, 0.5),
      1.2,
      Paint()..color = const Color(0xFF382B2A),
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: cashierFace + const Offset(0, 4),
        width: 7,
        height: serving ? 5 : 3,
      ),
      0,
      pi,
      false,
      cashierFeaturePaint,
    );
    if (serving) {
      final scannerAlpha = (150 + (sin(animationTime * 15) + 1) * 50)
          .round()
          .clamp(0, 255);
      canvas.drawCircle(
        _point(market, GameController.checkoutZone) + const Offset(-24, -7),
        12,
        Paint()..color = Color.fromARGB(scannerAlpha, 255, 224, 102),
      );
      _bubble(canvas, bodyCenter - const Offset(16, 39), '💳');
    }
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
      Paint()..color = const Color(0x25000000),
    );

    final legPaint = Paint()
      ..color = const Color(0xFF273043)
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
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
    canvas.drawRRect(torso, Paint()..color = const Color(0xFF38B879));
    canvas.drawRRect(
      torso,
      Paint()
        ..color = const Color(0xFF1F6A46)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: bodyCenter + const Offset(0, 5),
          width: 24,
          height: 24,
        ),
        const Radius.circular(8),
      ),
      Paint()..color = const Color(0xFFFFF3D7),
    );
    canvas.drawCircle(
      bodyCenter - const Offset(0, 27),
      15,
      Paint()..color = const Color(0xFFFFCFAC),
    );

    final hair = Paint()..color = const Color(0xFF5A3825);
    canvas.drawArc(
      Rect.fromCircle(center: bodyCenter - const Offset(0, 29), radius: 17),
      pi,
      pi,
      true,
      hair,
    );
    canvas.drawCircle(bodyCenter + const Offset(12, -31), 6, hair);
    canvas.drawCircle(
      bodyCenter + const Offset(-5, -26),
      1.6,
      Paint()..color = const Color(0xFF273043),
    );
    canvas.drawCircle(
      bodyCenter + const Offset(5, -26),
      1.6,
      Paint()..color = const Color(0xFF273043),
    );
    final playerFeaturePaint = Paint()
      ..color = const Color(0xFF56352E)
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      bodyCenter + const Offset(-8, -31),
      bodyCenter + const Offset(-3, -32),
      playerFeaturePaint,
    );
    canvas.drawLine(
      bodyCenter + const Offset(3, -32),
      bodyCenter + const Offset(8, -31),
      playerFeaturePaint,
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: bodyCenter + const Offset(0, -21),
        width: 11,
        height: 7,
      ),
      0,
      pi,
      false,
      playerFeaturePaint,
    );

    if (game.carried > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: bodyCenter + const Offset(22, 5),
            width: 24,
            height: 28,
          ),
          const Radius.circular(6),
        ),
        Paint()..color = const Color(0xFFF6A623),
      );
      _text(
        canvas,
        '${game.carried}',
        bodyCenter + const Offset(22, 5),
        fontSize: 12,
        color: Colors.white,
        weight: FontWeight.w900,
      );
    }
  }

  void _drawCustomer(Canvas canvas, Offset center, MarketCustomer customer) {
    canvas.drawOval(
      Rect.fromCenter(
        center: center + const Offset(0, 13),
        width: 31,
        height: 12,
      ),
      Paint()..color = const Color(0x22000000),
    );

    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center + const Offset(0, 3),
        width: 26,
        height: 32,
      ),
      const Radius.circular(10),
    );
    canvas.drawRRect(body, Paint()..color = customer.color);
    canvas.drawRRect(
      body,
      Paint()
        ..color = const Color(0xFF4C3A2F)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: center + const Offset(0, 2),
          width: 18,
          height: 12,
        ),
        const Radius.circular(5),
      ),
      Paint()..color = const Color(0xFFFFF3D7),
    );
    canvas.drawCircle(
      center - const Offset(0, 20),
      11,
      Paint()..color = const Color(0xFFFFD3B6),
    );
    final customerFace = center - const Offset(0, 20);
    final hairColors = <Color>[
      const Color(0xFF3B2A24),
      const Color(0xFF7A4F2B),
      const Color(0xFF2F3E52),
      const Color(0xFF8A623D),
    ];
    final customerHair = Paint()
      ..color = hairColors[customer.id.abs() % hairColors.length];
    canvas.drawArc(
      Rect.fromCircle(center: customerFace - const Offset(0, 1.5), radius: 12),
      pi,
      pi,
      true,
      customerHair,
    );
    canvas.drawCircle(
      customerFace + const Offset(-3.5, 0.5),
      1.1,
      Paint()..color = const Color(0xFF382B2A),
    );
    canvas.drawCircle(
      customerFace + const Offset(3.5, 0.5),
      1.1,
      Paint()..color = const Color(0xFF382B2A),
    );
    final customerFeaturePaint = Paint()
      ..color = const Color(0xFF573B35)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final isWorried =
        customer.phase == CustomerPhase.shopping && game.shelfStock == 0;
    final isHappy =
        customer.hasProduct ||
        customer.phase == CustomerPhase.paying ||
        customer.phase == CustomerPhase.leaving;
    if (isWorried) {
      canvas.drawArc(
        Rect.fromCenter(
          center: customerFace + const Offset(0, 6),
          width: 7,
          height: 4,
        ),
        pi,
        pi,
        false,
        customerFeaturePaint,
      );
      canvas.drawLine(
        customerFace + const Offset(-6, -3),
        customerFace + const Offset(-2, -2),
        customerFeaturePaint,
      );
      canvas.drawLine(
        customerFace + const Offset(2, -2),
        customerFace + const Offset(6, -3),
        customerFeaturePaint,
      );
    } else if (isHappy) {
      canvas.drawArc(
        Rect.fromCenter(
          center: customerFace + const Offset(0, 4),
          width: 8,
          height: 5,
        ),
        0,
        pi,
        false,
        customerFeaturePaint,
      );
    } else {
      canvas.drawLine(
        customerFace + const Offset(-3, 5),
        customerFace + const Offset(3, 5),
        customerFeaturePaint,
      );
    }

    if (customer.hasProduct) {
      canvas.drawCircle(
        center + const Offset(15, 2),
        7,
        Paint()..color = const Color(0xFFF6A623),
      );
    }
    if (customer.phase == CustomerPhase.shopping && game.shelfStock == 0) {
      _bubble(canvas, center - const Offset(18, 45), '📦?');
    }
    if (customer.phase == CustomerPhase.paying) {
      _bubble(canvas, center - const Offset(18, 45), '💰');
    }
  }

  void _interactionGlow(
    Canvas canvas,
    Rect market,
    Offset zone,
    double radius,
  ) {
    final center = _point(market, zone);
    final active = (game.playerPosition - zone).distance <= radius;
    final pulse = active ? 0.55 + sin(animationTime * 4) * 0.12 : 0.35;
    final ringRadius = min(market.width, market.height) * radius;
    canvas.drawCircle(
      center,
      ringRadius,
      Paint()
        ..color = active ? const Color(0x3338B879) : const Color(0x0F315F4A)
        ..style = PaintingStyle.fill,
    );
    if (active) {
      canvas.drawCircle(
        center,
        ringRadius * pulse,
        Paint()
          ..color = const Color(0x9938B879)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.1,
      );
    }
  }

  void _stationLabel(Canvas canvas, Offset center, String label) {
    final painter = _makeTextPainter(
      label,
      color: const Color(0xFF34433C),
      fontSize: 11,
      weight: FontWeight.w800,
    );
    final bubble = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center,
        width: painter.width + 18,
        height: painter.height + 9,
      ),
      const Radius.circular(10),
    );
    canvas.drawRRect(bubble, Paint()..color = const Color(0xEFFFFFFF));
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  void _bubble(Canvas canvas, Offset center, String content) {
    canvas.drawCircle(center, 17, Paint()..color = Colors.white);
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
    final painter = _makeTextPainter(
      value,
      color: color,
      fontSize: fontSize,
      weight: weight,
    );
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  TextPainter _makeTextPainter(
    String value, {
    required Color color,
    required double fontSize,
    required FontWeight weight,
  }) {
    return TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: weight,
          height: 1.05,
        ),
      ),
      textDirection: textDirection,
      textAlign: TextAlign.center,
    )..layout();
  }

  @override
  bool shouldRepaint(covariant MarketPainter oldDelegate) => true;
}
