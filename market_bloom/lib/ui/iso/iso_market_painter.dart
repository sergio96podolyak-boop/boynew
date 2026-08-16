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
    _paintCeilingLights(canvas, projection);
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
    _paintHangingSign(canvas, projection);
    _paintFloatingEffects(canvas, projection);

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

    // Walls run along the back edges of the extended room, not the play field,
    // so the room reads as fully enclosed rather than as a raised platform.
    const m = IsoProjection.roomMargin;
    const lo = -m;
    const hi = 1 + m;

    // Back-right wall lies along y = lo; back-left along x = lo.
    Path wall(Offset a, Offset b) => Path()
      ..moveTo(p.projectOffset(a).dx, p.projectOffset(a).dy)
      ..lineTo(p.projectOffset(b).dx, p.projectOffset(b).dy)
      ..lineTo(p.projectOffset(b, height).dx, p.projectOffset(b, height).dy)
      ..lineTo(p.projectOffset(a, height).dx, p.projectOffset(a, height).dy)
      ..close();

    final right = wall(const Offset(lo, lo), const Offset(hi, lo));
    final left = wall(const Offset(lo, lo), const Offset(lo, hi));

    paint.color = _wallSide;
    canvas.drawPath(right, paint);
    paint.color = _wallBack;
    canvas.drawPath(left, paint);

    // Skirting plus the gradient that anchors each wall to the floor.
    for (final entry in [
      (right, const Offset(lo, lo), const Offset(hi, lo)),
      (left, const Offset(lo, lo), const Offset(lo, hi)),
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
    // The room floor reaches past the play field so it meets the frame edges,
    // then the 0..1 field is laid on top as the lit shopping area. A small
    // floating diamond in a black void was the biggest reason the board read as
    // a prototype rather than a shop.
    final room = p.extendedGroundPath(IsoProjection.roomMargin);
    final roomBounds = room.getBounds();
    canvas.drawPath(
      room,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(roomBounds.center.dx, roomBounds.top),
          Offset(roomBounds.center.dx, roomBounds.bottom),
          const [Color(0xFFB59A6C), Color(0xFFCBB588)],
        ),
    );

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

  /// Warm pools cast by overhead fixtures.
  ///
  /// Regularly spaced light on the floor is what reads as "a lit shop" rather
  /// than "an evenly shaded diagram". The pools sit under the props so fixtures
  /// still cast their own contact shadows on top.
  void _paintCeilingLights(Canvas canvas, IsoProjection p) {
    final ground = p.groundPath();
    canvas.save();
    canvas.clipPath(ground);
    const spots = <Offset>[
      Offset(0.28, 0.28),
      Offset(0.72, 0.28),
      Offset(0.28, 0.72),
      Offset(0.72, 0.72),
      Offset(0.5, 0.5),
    ];
    for (final spot in spots) {
      final centre = p.project(spot.dx, spot.dy);
      final radius = p.tileWidth * 0.22;
      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.radial(centre, radius, [
            const Color(0x2EFFE6B0),
            const Color(0x00FFE6B0),
          ]),
      );
    }
    canvas.restore();
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

    // Dressing. An empty floor reads as a prototype however good the lighting
    // is, so the corners get props that also hint at what the shop sells.
    const planters = <Offset>[
      Offset(0.06, 0.90),
      Offset(0.90, 0.08),
      Offset(0.93, 0.93),
    ];
    for (final spot in planters) {
      add(
        IsoProjection.depthOf(spot.dx, spot.dy),
        (canvas) => _planter(canvas, brush, spot),
      );
    }

    const carts = <Offset>[Offset(0.80, 0.94), Offset(0.88, 0.86)];
    for (final spot in carts) {
      add(
        IsoProjection.depthOf(spot.dx, spot.dy),
        (canvas) => _trolley(canvas, brush, spot),
      );
    }

    // Produce bins in the middle of the floor break up the empty span between
    // the gondolas and the tills.
    const bins = <Offset>[Offset(0.62, 0.60), Offset(0.62, 0.74)];
    for (var i = 0; i < bins.length; i++) {
      final spot = bins[i];
      add(
        IsoProjection.depthOf(spot.dx + 0.05, spot.dy + 0.05),
        (canvas) => _produceBin(canvas, brush, spot, i),
      );
    }
  }

  void _planter(Canvas canvas, IsoBrush brush, Offset at) {
    brush.groundShadow(
      canvas,
      x: at.dx,
      y: at.dy,
      radiusX: 0.075,
      radiusY: 0.075,
      opacity: 0.28,
    );
    brush.box(
      canvas,
      x0: at.dx - 0.028,
      y0: at.dy - 0.028,
      x1: at.dx + 0.028,
      y1: at.dy + 0.028,
      height: 0.055,
      color: const Color(0xFFA9603C),
    );
    // Foliage as overlapping spheres so it reads organic against the boxes.
    brush.sphere(canvas, x: at.dx, y: at.dy, z: 0.10, radius: 0.062, color: const Color(0xFF3E8F4F));
    brush.sphere(
      canvas,
      x: at.dx - 0.018,
      y: at.dy + 0.012,
      z: 0.135,
      radius: 0.048,
      color: const Color(0xFF54A85F),
    );
    brush.sphere(
      canvas,
      x: at.dx + 0.020,
      y: at.dy - 0.010,
      z: 0.125,
      radius: 0.042,
      color: const Color(0xFF2F7A44),
    );
  }

  void _trolley(Canvas canvas, IsoBrush brush, Offset at) {
    brush.groundShadow(
      canvas,
      x: at.dx,
      y: at.dy,
      radiusX: 0.075,
      radiusY: 0.062,
      opacity: 0.24,
    );
    brush.box(
      canvas,
      x0: at.dx - 0.035,
      y0: at.dy - 0.028,
      x1: at.dx + 0.035,
      y1: at.dy + 0.028,
      base: 0.028,
      height: 0.046,
      color: const Color(0xFFB9C6C0),
      topColor: const Color(0xFF8FA39A),
    );
    brush.box(
      canvas,
      x0: at.dx + 0.026,
      y0: at.dy - 0.006,
      x1: at.dx + 0.032,
      y1: at.dy + 0.006,
      base: 0.074,
      height: 0.036,
      color: const Color(0xFF7B8B84),
      outline: false,
    );
  }

  void _produceBin(Canvas canvas, IsoBrush brush, Offset at, int index) {
    brush.groundShadow(
      canvas,
      x: at.dx + 0.05,
      y: at.dy + 0.05,
      radiusX: 0.13,
      radiusY: 0.13,
      opacity: 0.26,
    );
    brush.box(
      canvas,
      x0: at.dx,
      y0: at.dy,
      x1: at.dx + 0.10,
      y1: at.dy + 0.10,
      height: 0.048,
      color: index.isEven ? const Color(0xFF8C5A33) : const Color(0xFF7A6A4A),
    );
    // Loose produce heaped above the rim.
    final palette = index.isEven
        ? const [Color(0xFFE0573F), Color(0xFFEF7A4D), Color(0xFFC94430)]
        : const [Color(0xFF7FB93E), Color(0xFF9CCB53), Color(0xFF5F9A2E)];
    for (var i = 0; i < 5; i++) {
      final angle = i * 1.257 + index;
      brush.sphere(
        canvas,
        x: at.dx + 0.05 + math.cos(angle) * 0.024,
        y: at.dy + 0.05 + math.sin(angle) * 0.024,
        z: 0.062,
        radius: 0.030,
        color: palette[i % palette.length],
      );
    }
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
    final clock = game.totalPlaySeconds;
    for (final customer in game.customers) {
      final position = customer.position;
      final moving =
          customer.phase == CustomerPhase.entering ||
          customer.phase == CustomerPhase.shopping ||
          customer.phase == CustomerPhase.leaving;
      // Offsetting each shopper's gait by their id stops the crowd marching in
      // lockstep, which is the tell that a scene is procedurally animated.
      final phase = moving ? clock * 6.2 + customer.id.hashCode % 7 : 0.0;
      calls.add(
        IsoDrawCall(
          IsoProjection.depthOf(position.dx, position.dy),
          (canvas) => _person(
            canvas,
            brush,
            position,
            body: customer.color,
            skin: const Color(0xFFF6D2AE),
            hair: _hairFor(customer.id.hashCode),
            walkPhase: phase,
            facingRight: position.dx < 0.5,
            bubble: _customerBubble(customer),
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
    final moving = game.movement.distanceSquared > 0.0001;
    _person(
      canvas,
      brush,
      game.playerPosition,
      body: const Color(0xFF2FD08C),
      skin: const Color(0xFFF8D8B4),
      hair: const Color(0xFF3A2A1E),
      highlight: game.carried > 0 ? _accentGold : null,
      isPlayer: true,
      walkPhase: moving ? game.totalPlaySeconds * 8.4 : 0,
      facingRight: game.movement.dx >= 0,
    );
  }

  static Color _hairFor(int seed) => switch (seed.abs() % 5) {
    0 => const Color(0xFF3A2A1E),
    1 => const Color(0xFF6B4A2F),
    2 => const Color(0xFF1F1B18),
    3 => const Color(0xFFA9702F),
    _ => const Color(0xFF52463E),
  };

  /// Mood glyph above a shopper. Only shown when it tells the player something
  /// they can act on — a shopper running out of patience, or a big spender.
  String? _customerBubble(MarketCustomer customer) {
    if (customer.phase == CustomerPhase.leaving) return null;
    if (customer.patience < 2.2) return '😠';
    if (customer.isVip) return '⭐';
    if (customer.phase == CustomerPhase.checkout ||
        customer.phase == CustomerPhase.paying) {
      return '💰';
    }
    return null;
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

  /// A stylised shopper drawn as a screen-space billboard anchored to its
  /// ground point.
  ///
  /// Capsule-and-sphere placeholders read as chess pieces rather than people.
  /// Limbs, an apron and a hair cap cost little and are what make the floor
  /// feel populated.
  void _person(
    Canvas canvas,
    IsoBrush brush,
    Offset at, {
    required Color body,
    required Color skin,
    Color? highlight,
    bool isPlayer = false,
    Color hair = const Color(0xFF4A342A),
    double walkPhase = 0,
    bool facingRight = true,
    String? bubble,
  }) {
    final x = at.dx.clamp(0.0, 1.0);
    final y = at.dy.clamp(0.0, 1.0);
    final p = brush.projection;
    final ground = p.project(x, y);

    // Shoulder width drives every other measurement so the figure scales as a
    // unit with the board.
    final u = p.tileWidth * 0.052;
    final stride = math.sin(walkPhase) * u * 0.34;
    final bob = (math.sin(walkPhase * 2).abs()) * u * 0.10;
    final baseY = ground.dy - bob;

    brush.groundShadow(
      canvas,
      x: x,
      y: y,
      radiusX: 0.058,
      radiusY: 0.058,
      opacity: 0.36,
    );

    final paint = Paint()..isAntiAlias = true;
    RRect pill(double cx, double cy, double w, double h) =>
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx, cy), width: w, height: h),
          Radius.circular(w / 2),
        );

    // Legs — the trailing one is darkened so the stride reads at small sizes.
    final legColor = IsoLight.shade(body, 0.52);
    paint.color = IsoLight.shade(legColor, 0.82);
    canvas.drawRRect(
      pill(ground.dx - u * 0.34 - stride, baseY - u * 0.34, u * 0.46, u * 0.86),
      paint,
    );
    paint.color = legColor;
    canvas.drawRRect(
      pill(ground.dx + u * 0.34 + stride, baseY - u * 0.34, u * 0.46, u * 0.86),
      paint,
    );

    // Torso.
    final torsoRect = Rect.fromCenter(
      center: Offset(ground.dx, baseY - u * 1.28),
      width: u * 1.62,
      height: u * 1.44,
    );
    paint.shader = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [IsoLight.lift(body, 0.26), body, IsoLight.shade(body, 0.66)],
      stops: const [0, 0.5, 1],
    ).createShader(torsoRect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(torsoRect, Radius.circular(u * 0.5)),
      paint,
    );
    paint.shader = null;

    if (isPlayer) {
      // Apron marks the shop owner apart from shoppers at a glance.
      paint.color = const Color(0xFFF6FAF7);
      canvas.drawRRect(
        pill(ground.dx, baseY - u * 1.12, u * 0.94, u * 1.02),
        paint,
      );
      paint.color = const Color(0xFF2FD08C);
      canvas.drawRRect(
        pill(ground.dx, baseY - u * 1.72, u * 0.86, u * 0.20),
        paint,
      );
    }

    // Arms.
    paint.color = IsoLight.shade(body, 0.86);
    canvas.drawRRect(
      pill(ground.dx - u * 0.92, baseY - u * 1.30 + stride * 0.5, u * 0.40, u * 1.02),
      paint,
    );
    canvas.drawRRect(
      pill(ground.dx + u * 0.92, baseY - u * 1.30 - stride * 0.5, u * 0.40, u * 1.02),
      paint,
    );

    // Head, then a hair cap that also encodes facing.
    final headCentre = Offset(ground.dx, baseY - u * 2.32);
    final headRect = Rect.fromCircle(center: headCentre, radius: u * 0.66);
    paint.shader = RadialGradient(
      center: const Alignment(-0.3, -0.4),
      radius: 0.95,
      colors: [IsoLight.lift(skin, 0.24), skin, IsoLight.shade(skin, 0.74)],
      stops: const [0, 0.55, 1],
    ).createShader(headRect);
    canvas.drawCircle(headCentre, u * 0.66, paint);
    paint.shader = null;

    paint.color = hair;
    canvas.drawArc(
      Rect.fromCircle(center: headCentre, radius: u * 0.68),
      math.pi * (facingRight ? 0.98 : 1.06),
      math.pi * 0.96,
      true,
      paint,
    );

    // Eyes give the figure a front and stop it reading as a mannequin.
    paint.color = const Color(0xFF2A2018);
    final eyeShift = facingRight ? u * 0.10 : -u * 0.10;
    canvas.drawCircle(
      headCentre + Offset(eyeShift - u * 0.20, u * 0.10),
      u * 0.075,
      paint,
    );
    canvas.drawCircle(
      headCentre + Offset(eyeShift + u * 0.20, u * 0.10),
      u * 0.075,
      paint,
    );

    if (highlight != null) {
      // Carried crate held out in front.
      paint.color = highlight;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(ground.dx, baseY - u * 1.02),
            width: u * 1.10,
            height: u * 0.72,
          ),
          Radius.circular(u * 0.14),
        ),
        paint,
      );
      paint.color = IsoLight.lift(highlight, 0.32);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(ground.dx, baseY - u * 1.28),
            width: u * 1.10,
            height: u * 0.20,
          ),
          Radius.circular(u * 0.08),
        ),
        paint,
      );
    }

    if (bubble != null) {
      _speechBubble(canvas, Offset(ground.dx, baseY - u * 3.3), u, bubble);
    }
  }

  /// Small mood bubble above a shopper.
  void _speechBubble(Canvas canvas, Offset at, double u, String glyph) {
    final paint = Paint()..isAntiAlias = true;
    final rect = Rect.fromCenter(center: at, width: u * 1.5, height: u * 1.2);
    paint.color = const Color(0xF2FFFFFF);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(u * 0.42)),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(at.dx - u * 0.22, rect.bottom - u * 0.06)
        ..lineTo(at.dx, rect.bottom + u * 0.34)
        ..lineTo(at.dx + u * 0.16, rect.bottom - u * 0.06)
        ..close(),
      paint,
    );
    final painter = TextPainter(
      text: TextSpan(
        text: glyph,
        style: TextStyle(fontSize: u * 0.82, height: 1),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, at - Offset(painter.width / 2, painter.height / 2));
  }

  // ---------------------------------------------------------------- ambience

  /// Earnings and status text rising off the point that produced them.
  ///
  /// Drawn above the depth-sorted layer so a sale is never hidden behind a
  /// gondola — the payoff has to be visible to land.
  void _paintFloatingEffects(Canvas canvas, IsoProjection p) {
    for (final effect in game.floatingEffects) {
      final progress = effect.progress;
      final anchor = p.project(
        effect.position.dx.clamp(0.0, 1.0),
        effect.position.dy.clamp(0.0, 1.0),
        0.22,
      );
      // Ease out on the way up, fade only over the last third.
      final rise = (1 - math.pow(1 - progress, 3)) * p.tileHeight * 0.16;
      final opacity = progress < 0.66 ? 1.0 : (1 - progress) / 0.34;
      final pop = progress < 0.16
          ? 0.72 + 0.28 * (progress / 0.16)
          : 1.0;
      final size = effect.fontSize * p.scale * pop;

      final painter = TextPainter(
        text: TextSpan(
          text: effect.text,
          style: TextStyle(
            color: effect.color.withValues(
              alpha: effect.color.a * opacity.clamp(0.0, 1.0),
            ),
            fontSize: size,
            fontWeight: FontWeight.w900,
            height: 1,
            shadows: [
              Shadow(
                color: const Color(0xFF04211A).withValues(
                  alpha: 0.65 * opacity.clamp(0.0, 1.0),
                ),
                blurRadius: 3,
                offset: const Offset(0, 1.5),
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset(anchor.dx - painter.width / 2, anchor.dy - rise - painter.height),
      );
    }
  }

  /// Brand plaque hung from the ceiling over the shop floor.
  ///
  /// Gives the space an identity from inside the world — the icon carries the
  /// brand on the store facade, but the board itself had no marque. Drawn late
  /// so it always hangs in front of the fixtures below it.
  void _paintHangingSign(Canvas canvas, IsoProjection p) {
    final anchor = p.project(0.5, 0.16, 0.62);
    final width = p.tileWidth * 0.30;
    final height = width * 0.30;
    final rect = Rect.fromCenter(
      center: anchor,
      width: width,
      height: height,
    );

    final paint = Paint()..isAntiAlias = true;
    // Suspension cords back up to the ceiling line.
    paint
      ..color = const Color(0x66203029)
      ..strokeWidth = math.max(1, 1.4 * p.scale);
    canvas.drawLine(
      rect.topLeft + Offset(width * 0.18, 0),
      rect.topLeft + Offset(width * 0.30, -height * 0.9),
      paint,
    );
    canvas.drawLine(
      rect.topRight - Offset(width * 0.18, 0),
      rect.topRight - Offset(width * 0.30, height * 0.9),
      paint,
    );

    // Plaque.
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(height * 0.34));
    canvas.drawRRect(
      rrect.shift(Offset(0, height * 0.14)),
      Paint()..color = const Color(0x4D04211A),
    );
    paint.shader = ui.Gradient.linear(rect.topCenter, rect.bottomCenter, const [
      Color(0xFF14624A),
      Color(0xFF0A3D2E),
    ]);
    canvas.drawRRect(rrect, paint);
    paint.shader = null;
    canvas.drawRRect(
      rrect.deflate(height * 0.10),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, 1.4 * p.scale)
        ..color = _accentGold.withValues(alpha: 0.7),
    );

    // Leaf mark plus wordmark.
    final leafCentre = rect.centerLeft + Offset(width * 0.16, 0);
    canvas.drawCircle(
      leafCentre,
      height * 0.22,
      Paint()..color = _accentGold,
    );
    final painter = TextPainter(
      text: TextSpan(
        text: 'PoMARKET',
        style: TextStyle(
          color: Colors.white,
          fontSize: height * 0.42,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(
        leafCentre.dx + height * 0.30,
        anchor.dy - painter.height / 2,
      ),
    );
  }

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
