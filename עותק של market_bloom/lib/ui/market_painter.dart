import 'dart:math';

import 'package:flutter/material.dart';

import '../game/game_controller.dart';
import '../game/game_models.dart';

class MarketPainter extends CustomPainter {
  const MarketPainter({required this.game, required this.animationTime});

  final GameController game;
  final double animationTime;

  @override
  void paint(Canvas canvas, Size size) {
    final market = Rect.fromLTWH(8, 6, size.width - 16, size.height - 12);
    _drawMarket(canvas, market);
    _drawEntrance(canvas, market);
    _drawStockRoom(canvas, market);
    _drawShelf(canvas, market);
    _drawCheckout(canvas, market);
    _drawExpansion(canvas, market);

    for (final customer in game.customers) {
      _drawCustomer(canvas, _point(market, customer.position), customer);
    }
    _drawPlayer(canvas, _point(market, game.playerPosition));
  }

  void _drawMarket(Canvas canvas, Rect rect) {
    final shadow = RRect.fromRectAndRadius(
      rect.shift(const Offset(0, 4)),
      const Radius.circular(26),
    );
    canvas.drawRRect(shadow, Paint()..color = const Color(0x26000000));

    final room = RRect.fromRectAndRadius(rect, const Radius.circular(26));
    canvas.drawRRect(room, Paint()..color = const Color(0xFFFFFCF2));
    canvas.save();
    canvas.clipRRect(room);

    const tile = 34.0;
    final gridPaint = Paint()
      ..color = const Color(0x0F315F4A)
      ..strokeWidth = 1;
    for (var x = rect.left; x < rect.right; x += tile) {
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), gridPaint);
    }
    for (var y = rect.top; y < rect.bottom; y += tile) {
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), gridPaint);
    }
    canvas.restore();

    canvas.drawRRect(
      room,
      Paint()
        ..color = const Color(0xFF315F4A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
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

    final crate = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: 64, height: 52),
      const Radius.circular(10),
    );
    canvas.drawRRect(crate, Paint()..color = const Color(0xFFE0A45B));
    canvas.drawRRect(
      crate,
      Paint()
        ..color = const Color(0xFF9B6230)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
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
    _stationLabel(canvas, center + const Offset(0, 39), 'STORAGE');
  }

  void _drawShelf(Canvas canvas, Rect market) {
    final center = _point(market, GameController.shelfZone);
    _interactionGlow(canvas, market, GameController.shelfZone, 0.14);

    final shelf = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: 104, height: 82),
      const Radius.circular(13),
    );
    canvas.drawRRect(shelf, Paint()..color = const Color(0xFF5B8DEF));
    canvas.drawRRect(
      shelf,
      Paint()
        ..color = const Color(0xFF315EAC)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
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
    _stationLabel(
      canvas,
      center + const Offset(0, 55),
      'SHELF ${game.shelfStock}/${game.shelfCapacity}',
    );
  }

  void _drawCheckout(Canvas canvas, Rect market) {
    final center = _point(market, GameController.checkoutZone);
    _interactionGlow(canvas, market, GameController.checkoutZone, 0.13);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: 92, height: 56),
        const Radius.circular(14),
      ),
      Paint()..color = const Color(0xFFE85D75),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: center + const Offset(17, -12),
          width: 29,
          height: 21,
        ),
        const Radius.circular(5),
      ),
      Paint()..color = const Color(0xFF3B4054),
    );
    canvas.drawCircle(
      center + const Offset(-24, -7),
      9,
      Paint()..color = const Color(0xFFFFD166),
    );
    _stationLabel(canvas, center + const Offset(0, 39), 'CHECKOUT');
  }

  void _drawExpansion(Canvas canvas, Rect market) {
    final center = _point(market, const Offset(0.78, 0.76));
    final unlocked = game.storeLevel >= 3;
    final zone = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: 105, height: 91),
      const Radius.circular(18),
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
    _text(
      canvas,
      unlocked ? '🥐' : '🔒',
      center - const Offset(0, 14),
      fontSize: 25,
    );
    _text(
      canvas,
      unlocked ? 'BAKERY\nSOON' : 'UNLOCKS\nAT LEVEL 3',
      center + const Offset(0, 20),
      color: const Color(0xFF645E55),
      fontSize: 11,
      weight: FontWeight.w800,
    );
  }

  void _drawPlayer(Canvas canvas, Offset center) {
    final walking = game.movement.distance > 0.05;
    final bounce = walking ? sin(animationTime * 11) * 2.2 : 0.0;
    final bodyCenter = center + Offset(0, bounce);

    canvas.drawOval(
      Rect.fromCenter(
        center: center + const Offset(0, 19),
        width: 37,
        height: 15,
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

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: bodyCenter, width: 34, height: 42),
        const Radius.circular(13),
      ),
      Paint()..color = const Color(0xFF38B879),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: bodyCenter + const Offset(0, 5),
          width: 23,
          height: 25,
        ),
        const Radius.circular(7),
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
      bodyCenter + const Offset(-5, -28),
      1.5,
      Paint()..color = const Color(0xFF273043),
    );
    canvas.drawCircle(
      bodyCenter + const Offset(5, -28),
      1.5,
      Paint()..color = const Color(0xFF273043),
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
        width: 28,
        height: 10,
      ),
      Paint()..color = const Color(0x22000000),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: 24, height: 31),
        const Radius.circular(9),
      ),
      Paint()..color = customer.color,
    );
    canvas.drawCircle(
      center - const Offset(0, 20),
      11,
      Paint()..color = const Color(0xFFFFD3B6),
    );
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
    canvas.drawCircle(
      center,
      min(market.width, market.height) * radius,
      Paint()
        ..color = active ? const Color(0x3338B879) : const Color(0x0F315F4A)
        ..style = PaintingStyle.fill,
    );
    if (active) {
      canvas.drawCircle(
        center,
        min(market.width, market.height) * radius,
        Paint()
          ..color = const Color(0x9938B879)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
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
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
  }

  @override
  bool shouldRepaint(covariant MarketPainter oldDelegate) => true;
}
