import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../game/game_controller.dart';
import '../../game/game_models.dart';
import 'iso_projection.dart';
import 'iso_shapes.dart';

/// Procedural isometric renderer for the market.
///
/// Everything here is drawn from geometry rather than sprite sheets. The
/// previous board used flat top-down bitmaps, which meant no amount of floor
/// shading could make the space read as three-dimensional — the ground implied
/// depth while every object on it stayed flat. Building the props as lit solids
/// removes that contradiction and lets one light direction govern the scene.
class IsoMarketPainter extends CustomPainter {
  IsoMarketPainter({
    required this.game,
    required this.storageLabel,
    required this.bakeryLabel,
    required this.checkoutLabel,
    required this.shelfLabel,
    required this.textDirection,
  }) : super(repaint: game);

  final GameController game;
  final String storageLabel;
  final String bakeryLabel;
  final String checkoutLabel;
  final String shelfLabel;
  final TextDirection textDirection;

  // Store palette. Saturated enough to survive the ambient grade without
  // turning garish under the warm key light.
  static const _floorLight = Color(0xFFF3E3C4);
  static const _floorDark = Color(0xFFD9BC8E);
  static const _floorSeam = Color(0x2A6B5334);
  static const _wallBack = Color(0xFF52685D);
  static const _wallSide = Color(0xFF3E5349);
  static const _shelfBody = Color(0xFF2F7B58);
  static const _fridgeBody = Color(0xFF356F98);
  static const _counterBody = Color(0xFF3C4F58);
  static const _crateBody = Color(0xFFB07C43);
  static const _bakeryBody = Color(0xFFC98A3C);
  static const _accentGold = Color(0xFFFFC33D);

  static const _productPalette = <Color>[
    Color(0xFFE0573F),
    Color(0xFFF0A93B),
    Color(0xFF52A85E),
    Color(0xFF4A8FD4),
    Color(0xFFB268D6),
    Color(0xFFE8C34A),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (game.pendingShiftSummary != null || size.shortestSide < 80) return;

    final projection = IsoProjection.fit(size);
    final brush = IsoBrush(projection);

    _paintBackdrop(canvas, size);
    _paintWalls(canvas, brush, projection);
    _paintFloor(canvas, brush, projection);
    _paintFloorDecals(canvas, brush, projection);

    // Everything that stands up is depth-sorted together so props and people
    // occlude each other correctly regardless of draw order in code.
    final calls = <IsoDrawCall>[];
    _collectFixtures(calls, brush, projection);
    _collectCharacters(calls, brush, projection);
    calls.sort((a, b) => a.depth.compareTo(b.depth));
    for (final call in calls) {
      call.paint(canvas);
    }

    // The avatar is exempt from depth sorting. Correct occlusion buries it
    // whenever it stands behind a gondola, and losing track of your own
    // character mid-shift is worse than the small break in realism.
    _paintPlayer(canvas, brush);

    _paintAmbience(canvas, size, projection);
  }

  // ---------------------------------------------------------------- backdrop

  void _paintBackdrop(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF10493A), Color(0xFF06251D)],
        ).createShader(rect),
    );
  }

  void _paintWalls(Canvas canvas, IsoBrush brush, IsoProjection p) {
    // Low walls. Full-height ones met at the far corner and read as a tent
    // pitched over the shop rather than as the back of a room.
    const height = 0.15;
    final paint = Paint()..isAntiAlias = true;

    // Back-right wall lies along y = 0; back-left along x = 0.
    Path wall(Offset a, Offset b) => Path()
      ..moveTo(p.projectOffset(a).dx, p.projectOffset(a).dy)
      ..lineTo(p.projectOffset(b).dx, p.projectOffset(b).dy)
      ..lineTo(p.projectOffset(b, height).dx, p.projectOffset(b, height).dy)
      ..lineTo(p.projectOffset(a, height).dx, p.projectOffset(a, height).dy)
      ..close();

    final right = wall(const Offset(0, 0), const Offset(1, 0));
    final left = wall(const Offset(0, 0), const Offset(0, 1));

    paint.color = _wallSide;
    canvas.drawPath(right, paint);
    paint.color = _wallBack;
    canvas.drawPath(left, paint);

    // Skirting plus the gradient that anchors each wall to the floor.
    for (final entry in [
      (right, const Offset(0, 0), const Offset(1, 0)),
      (left, const Offset(0, 0), const Offset(0, 1)),
    ]) {
      final a = p.projectOffset(entry.$2);
      final b = p.projectOffset(entry.$3);
      canvas.save();
      canvas.clipPath(entry.$1);
      canvas.drawPath(
        entry.$1,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2),
            Offset(
              (a.dx + b.dx) / 2,
              (a.dy + b.dy) / 2 - height * p.unitHeight,
            ),
            [const Color(0x5507231B), const Color(0x0007231B)],
          ),
      );
      canvas.restore();
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = const Color(0xFF7E8C85)
          ..strokeWidth = math.max(1.4, 2.4 * p.scale),
      );
    }
  }

  // ------------------------------------------------------------------- floor

  void _paintFloor(Canvas canvas, IsoBrush brush, IsoProjection p) {
    final ground = p.groundPath();
    final bounds = ground.getBounds();

    canvas.drawPath(
      ground,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(bounds.center.dx, bounds.top),
          Offset(bounds.center.dx, bounds.bottom),
          const [_floorDark, _floorLight],
        ),
    );

    // Checkerboard tiling in world space keeps the perspective honest — tiles
    // narrow toward the far corner for free because the projection does it.
    const divisions = 10;
    final tile = Paint()..color = Colors.white.withValues(alpha: 0.16);
    for (var ix = 0; ix < divisions; ix++) {
      for (var iy = 0; iy < divisions; iy++) {
        if ((ix + iy).isEven) continue;
        brush.groundQuad(
          canvas,
          x0: ix / divisions,
          y0: iy / divisions,
          x1: (ix + 1) / divisions,
          y1: (iy + 1) / divisions,
          color: tile.color,
        );
      }
    }

    final seam = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.5, 0.7 * p.scale)
      ..color = _floorSeam;
    for (var i = 1; i < divisions; i++) {
      final t = i / divisions;
      canvas.drawLine(p.project(t, 0), p.project(t, 1), seam);
      canvas.drawLine(p.project(0, t), p.project(1, t), seam);
    }

    // Warm pool over the middle of the shop floor.
    canvas.save();
    canvas.clipPath(ground);
    canvas.drawRect(
      bounds,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(
          p.project(0.45, 0.55),
          bounds.width * 0.42,
          [const Color(0x33FFDCA0), const Color(0x00FFDCA0)],
        ),
    );
    canvas.restore();

    canvas.drawPath(
      ground,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, 2 * p.scale)
        ..color = const Color(0x66452F16),
    );
  }

  void _paintFloorDecals(Canvas canvas, IsoBrush brush, IsoProjection p) {
    // Queue lane leading to the tills.
    brush.groundQuad(
      canvas,
      x0: 0.52,
      y0: 0.30,
      x1: 0.98,
      y1: 0.44,
      color: const Color(0x38FFC33D),
    );
    for (var i = 0; i < 4; i++) {
      final x = 0.60 + i * 0.10;
      final tip = p.project(x + 0.05, 0.37);
      final a = p.project(x, 0.33);
      final b = p.project(x, 0.41);
      canvas.drawPath(
        Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy)
          ..close(),
        Paint()..color = const Color(0x8CB87A22),
      );
    }

    // Entrance mat at the near corner.
    brush.groundQuad(
      canvas,
      x0: 0.68,
      y0: 0.86,
      x1: 0.94,
      y1: 0.99,
      color: const Color(0x99346654),
    );
  }

  // ---------------------------------------------------------------- fixtures

  void _collectFixtures(
    List<IsoDrawCall> calls,
    IsoBrush brush,
    IsoProjection p,
  ) {
    void add(double depth, void Function(Canvas) paint) =>
        calls.add(IsoDrawCall(depth, paint));

    // Gondola runs across the sales floor. Stock level drives how full the
    // shelves look, so the board reflects play state at a glance.
    const runs = <({double x, double y, double length})>[
      (x: 0.16, y: 0.30, length: 0.26),
      (x: 0.16, y: 0.52, length: 0.26),
      (x: 0.44, y: 0.30, length: 0.22),
      (x: 0.44, y: 0.52, length: 0.22),
    ];
    final fillRatio = (game.shelfStock / 12).clamp(0.0, 1.0);
    for (final run in runs) {
      add(
        IsoProjection.depthOf(run.x + 0.06, run.y + run.length),
        (canvas) => _shelfRun(canvas, brush, p, run.x, run.y, run.length, fillRatio),
      );
    }

    // Chillers along the back-left wall.
    for (var i = 0; i < 3; i++) {
      final y = 0.10 + i * 0.24;
      add(
        IsoProjection.depthOf(0.09, y + 0.18),
        (canvas) => _fridge(canvas, brush, p, 0.02, y, y + 0.18),
      );
    }

    // Tills along the back-right wall.
    for (final station in game.checkoutStations) {
      final zone = game.checkoutStationZone(station.id);
      add(
        IsoProjection.depthOf(zone.dx + 0.07, zone.dy + 0.05),
        (canvas) => _checkout(canvas, brush, p, zone, station.unlocked),
      );
    }

    // Stockroom shelving.
    add(
      IsoProjection.depthOf(
        GameController.stockZone.dx + 0.09,
        GameController.stockZone.dy + 0.02,
      ),
      (canvas) => _stockroom(canvas, brush, p),
    );

    // Bakery counter.
    add(
      IsoProjection.depthOf(
        GameController.bakeryZone.dx + 0.09,
        GameController.bakeryZone.dy + 0.03,
      ),
      (canvas) => _bakery(canvas, brush, p, game.bakeryUnlocked),
    );

    // Storefront arch at the near corner.
    add(
      IsoProjection.depthOf(0.99, 0.99),
      (canvas) => _entrance(canvas, brush, p),
    );
  }

  void _shelfRun(
    Canvas canvas,
    IsoBrush brush,
    IsoProjection p,
    double x,
    double y,
    double length,
    double fill,
  ) {
    const width = 0.085;
    const bodyHeight = 0.085;
    brush.groundShadow(
      canvas,
      x: x + width / 2,
      y: y + length / 2,
      radiusX: width * 1.9,
      radiusY: length * 1.5,
      opacity: 0.26,
    );
    brush.box(
      canvas,
      x0: x,
      y0: y,
      x1: x + width,
      y1: y + length,
      height: bodyHeight,
      color: _shelfBody,
    );

    // Product blocks sitting on the deck.
    final rows = (length / 0.045).floor();
    final stocked = (rows * fill).round();
    for (var i = 0; i < stocked; i++) {
      final cy = y + 0.006 + i * 0.045;
      final colour = _productPalette[(i + (x * 37).round()) % _productPalette.length];
      brush.box(
        canvas,
        x0: x + 0.012,
        y0: cy,
        x1: x + width - 0.012,
        y1: cy + 0.032,
        base: bodyHeight,
        height: 0.05 + (i % 3) * 0.008,
        color: colour,
        outline: false,
      );
    }
  }

  void _fridge(
    Canvas canvas,
    IsoBrush brush,
    IsoProjection p,
    double x,
    double y0,
    double y1,
  ) {
    brush.groundShadow(
      canvas,
      x: x + 0.045,
      y: (y0 + y1) / 2,
      radiusX: 0.14,
      radiusY: (y1 - y0) * 1.3,
      opacity: 0.24,
    );
    brush.box(
      canvas,
      x0: x,
      y0: y0,
      x1: x + 0.09,
      y1: y1,
      height: 0.20,
      color: _fridgeBody,
    );
    // Glass door on the face turned toward the shop floor.
    brush.panel(
      canvas,
      x0: x + 0.09,
      y0: y0 + 0.02,
      x1: x + 0.09,
      y1: y1 - 0.02,
      base: 0.035,
      top: 0.175,
      color: const Color(0x8FBFE6F5),
    );
  }

  void _checkout(
    Canvas canvas,
    IsoBrush brush,
    IsoProjection p,
    Offset zone,
    bool unlocked,
  ) {
    final body = unlocked ? _counterBody : const Color(0xFF6B7671);
    final x = zone.dx - 0.07;
    final y = zone.dy - 0.10;
    brush.groundShadow(
      canvas,
      x: zone.dx,
      y: zone.dy - 0.05,
      radiusX: 0.20,
      radiusY: 0.18,
      opacity: 0.26,
    );
    brush.box(
      canvas,
      x0: x,
      y0: y,
      x1: x + 0.15,
      y1: y + 0.11,
      height: 0.072,
      color: body,
      topColor: unlocked ? const Color(0xFF6E8A93) : const Color(0xFF8A948F),
    );
    if (!unlocked) return;
    // Register block and its screen.
    brush.box(
      canvas,
      x0: x + 0.015,
      y0: y + 0.02,
      x1: x + 0.062,
      y1: y + 0.07,
      base: 0.072,
      height: 0.055,
      color: const Color(0xFF25333A),
      outline: false,
    );
    brush.panel(
      canvas,
      x0: x + 0.062,
      y0: y + 0.025,
      x1: x + 0.062,
      y1: y + 0.065,
      base: 0.09,
      top: 0.125,
      color: const Color(0xFF6FE3B4),
    );
    // Belt stripe.
    brush.groundQuad(
      canvas,
      x0: x + 0.075,
      y0: y + 0.018,
      x1: x + 0.142,
      y1: y + 0.092,
      color: const Color(0xFF1D2A30),
      z: 0.0725,
    );
  }

  void _stockroom(Canvas canvas, IsoBrush brush, IsoProjection p) {
    final zone = GameController.stockZone;
    final x = zone.dx - 0.075;
    final y = zone.dy - 0.055;
    brush.groundShadow(
      canvas,
      x: zone.dx,
      y: zone.dy,
      radiusX: 0.22,
      radiusY: 0.20,
      opacity: 0.28,
    );
    brush.box(
      canvas,
      x0: x,
      y0: y,
      x1: x + 0.15,
      y1: y + 0.11,
      height: 0.055,
      color: const Color(0xFF4A5B63),
    );
    // Crate stack — height tracks how much stock is waiting to be carried out.
    final crates = (game.inventoryFor('General') / 4).clamp(0, 5).toInt();
    for (var i = 0; i < math.max(1, crates); i++) {
      brush.box(
        canvas,
        x0: x + 0.022 + (i.isEven ? 0 : 0.012),
        y0: y + 0.018,
        x1: x + 0.088 + (i.isEven ? 0 : 0.012),
        y1: y + 0.086,
        base: 0.055 + i * 0.042,
        height: 0.042,
        color: i.isEven ? _crateBody : const Color(0xFF9C6C39),
        outline: false,
      );
    }
  }

  void _bakery(Canvas canvas, IsoBrush brush, IsoProjection p, bool unlocked) {
    final zone = GameController.bakeryZone;
    final x = zone.dx - 0.075;
    final y = zone.dy - 0.06;
    brush.groundShadow(
      canvas,
      x: zone.dx,
      y: zone.dy,
      radiusX: 0.22,
      radiusY: 0.20,
      opacity: 0.26,
    );
    brush.box(
      canvas,
      x0: x,
      y0: y,
      x1: x + 0.15,
      y1: y + 0.12,
      height: 0.075,
      color: unlocked ? _bakeryBody : const Color(0xFF8C8478),
    );
    if (!unlocked) return;
    // Glass display hood plus loaves.
    brush.panel(
      canvas,
      x0: x + 0.15,
      y0: y + 0.02,
      x1: x + 0.15,
      y1: y + 0.10,
      base: 0.075,
      top: 0.15,
      color: const Color(0x99D9F0F7),
    );
    for (var i = 0; i < 3; i++) {
      brush.box(
        canvas,
        x0: x + 0.03 + i * 0.036,
        y0: y + 0.04,
        x1: x + 0.058 + i * 0.036,
        y1: y + 0.082,
        base: 0.075,
        height: 0.024,
        color: const Color(0xFFE8B98A),
        outline: false,
      );
    }
  }

  void _entrance(Canvas canvas, IsoBrush brush, IsoProjection p) {
    brush.box(
      canvas,
      x0: 0.66,
      y0: 0.99,
      x1: 0.74,
      y1: 1.02,
      height: 0.30,
      color: const Color(0xFF1F5C46),
      outline: false,
    );
    brush.box(
      canvas,
      x0: 0.92,
      y0: 0.99,
      x1: 1.0,
      y1: 1.02,
      height: 0.30,
      color: const Color(0xFF1F5C46),
      outline: false,
    );
    brush.box(
      canvas,
      x0: 0.66,
      y0: 0.99,
      x1: 1.0,
      y1: 1.02,
      base: 0.30,
      height: 0.07,
      color: const Color(0xFF2A7A5C),
      topColor: _accentGold,
    );
  }

  // -------------------------------------------------------------- characters

  void _collectCharacters(
    List<IsoDrawCall> calls,
    IsoBrush brush,
    IsoProjection p,
  ) {
    for (final customer in game.customers) {
      final position = customer.position;
      calls.add(
        IsoDrawCall(
          IsoProjection.depthOf(position.dx, position.dy),
          (canvas) => _person(
            canvas,
            brush,
            position,
            body: customer.color,
            skin: const Color(0xFFF6D2AE),
            highlight: customer.isVip ? _accentGold : null,
          ),
        ),
      );
    }

    for (final role in StaffRole.values) {
      if (!game.isStaffHired(role)) continue;
      for (var i = 0; i < game.staffWorkerCount(role); i++) {
        final spot = _staffSpot(role, i);
        calls.add(
          IsoDrawCall(
            IsoProjection.depthOf(spot.dx, spot.dy),
            (canvas) => _person(
              canvas,
              brush,
              spot,
              body: const Color(0xFF3E8E6B),
              skin: const Color(0xFFF2C9A0),
            ),
          ),
        );
      }
    }

  }

  void _paintPlayer(Canvas canvas, IsoBrush brush) {
    _person(
      canvas,
      brush,
      game.playerPosition,
      body: const Color(0xFF2FD08C),
      skin: const Color(0xFFF8D8B4),
      highlight: game.carried > 0 ? _accentGold : null,
      isPlayer: true,
    );
  }

  Offset _staffSpot(StaffRole role, int index) {
    final base = switch (role) {
      StaffRole.cashier => const Offset(0.72, 0.34),
      StaffRole.stocker => GameController.stockerPickupZone,
      _ => const Offset(0.45, 0.62),
    };
    return Offset(
      (base.dx + index * 0.05).clamp(0.05, 0.95),
      (base.dy + index * 0.03).clamp(0.05, 0.95),
    );
  }

  void _person(
    Canvas canvas,
    IsoBrush brush,
    Offset at, {
    required Color body,
    required Color skin,
    Color? highlight,
    bool isPlayer = false,
  }) {
    final x = at.dx.clamp(0.0, 1.0);
    final y = at.dy.clamp(0.0, 1.0);
    brush.groundShadow(
      canvas,
      x: x,
      y: y,
      radiusX: 0.052,
      radiusY: 0.052,
      opacity: 0.34,
    );
    if (highlight != null) {
      brush.groundShadow(
        canvas,
        x: x,
        y: y,
        radiusX: 0.075,
        radiusY: 0.075,
        opacity: 0.16,
      );
    }
    brush.capsule(
      canvas,
      x: x,
      y: y,
      base: 0,
      height: 0.155,
      radius: 0.072,
      color: body,
    );
    if (isPlayer) {
      // Apron front so the player reads apart from shoppers at a glance.
      brush.capsule(
        canvas,
        x: x,
        y: y,
        base: 0.012,
        height: 0.085,
        radius: 0.046,
        color: const Color(0xFFF3F8F4),
      );
    }
    brush.sphere(canvas, x: x, y: y, z: 0.205, radius: 0.066, color: skin);
    if (highlight != null) {
      brush.sphere(
        canvas,
        x: x,
        y: y,
        z: 0.30,
        radius: 0.030,
        color: highlight,
      );
    }
  }

  // ---------------------------------------------------------------- ambience

  void _paintAmbience(Canvas canvas, Size size, IsoProjection p) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          rect.center,
          rect.longestSide * 0.62,
          [const Color(0x0004211A), const Color(0x7A04211A)],
          [0.55, 1],
        ),
    );
  }

  @override
  bool shouldRepaint(covariant IsoMarketPainter oldDelegate) => true;
}
