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
    // Repaint on the per-frame scene channel, not the controller's visible-
    // state notifier. The player and customers move every tick but the
    // controller only calls notifyListeners on visible state changes, so
    // binding to `game` left the board frozen between those — which read as
    // "the player doesn't move" even though its position was updating.
  }) : super(repaint: game.scene);

  final GameController game;
  final String storageLabel;
  final String bakeryLabel;
  final String checkoutLabel;
  final String shelfLabel;
  final TextDirection textDirection;

  // Store palette. Saturated enough to survive the ambient grade without
  // turning garish under the warm key light.
  static const _floorLight = Color(0xFFF4F0E7);
  static const _floorDark = Color(0xFFDED6C6);
  static const _floorSeam = Color(0x22705E3A);
  // Light walls that recede as backdrop. Dark walls dominated the frame and
  // made the shop feel like a basement; commercial tycoon boards use bright,
  // near-white interiors.
  static const _wallBack = Color(0xFFCFE9DA);
  static const _wallSide = Color(0xFFA8D2C1);
  static const _fridgeBody = Color(0xFF3D8FC4);
  static const _counterBody = Color(0xFF3C4F58);
  static const _crateBody = Color(0xFFB07C43);
  static const _bakeryBody = Color(0xFFE0A542);
  static const _accentGold = Color(0xFFFFC33D);

  @override
  void paint(Canvas canvas, Size size) {
    if (game.pendingShiftSummary != null || size.shortestSide < 80) return;

    // CustomPaint does not clip, so without this the extended room and its
    // walls project past the board and paint over the HUD above it.
    canvas.clipRect(Offset.zero & size);

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
    _paintZoneLabels(canvas, projection);
    _paintFloatingEffects(canvas, projection);

    _paintAmbience(canvas, size, projection);
  }

  /// Floating name tags over each area of the shop.
  ///
  /// The genre leans on this: every commercial supermarket-tycoon board labels
  /// its zones so a new player knows the storeroom from the tills at a glance.
  /// The painter already receives these strings; it just never drew them, which
  /// is a large part of why the board read as unreadable.
  void _paintZoneLabels(Canvas canvas, IsoProjection p) {
    void tag(Offset zone, double lift, String text, Color color) {
      final anchor = p.project(zone.dx, zone.dy, lift);
      final painter = TextPainter(
        textDirection: TextDirection.ltr,
        text: TextSpan(
          text: text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.6,
            height: 1,
          ),
        ),
      )..layout();
      final w = painter.width + 16 * p.scale;
      final h = painter.height + 8 * p.scale;
      final rect = Rect.fromCenter(
        center: Offset(anchor.dx, anchor.dy),
        width: w,
        height: h,
      );
      final rrect = RRect.fromRectAndRadius(rect, Radius.circular(h / 2));
      canvas.drawRRect(
        rrect.shift(Offset(0, 1.5 * p.scale)),
        Paint()..color = const Color(0x5504211A),
      );
      canvas.drawRRect(
        rrect,
        Paint()
          ..shader = ui.Gradient.linear(rect.topCenter, rect.bottomCenter, [
            color,
            IsoLight.shade(color, 0.7),
          ]),
      );
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.8, 1 * p.scale)
          ..color = Colors.white.withValues(alpha: 0.28),
      );
      painter.paint(
        canvas,
        Offset(anchor.dx - painter.width / 2, anchor.dy - painter.height / 2),
      );
    }

    tag(GameController.stockZone, 0.24, storageLabel, const Color(0xFF4A6B76));
    tag(GameController.shelfZone, 0.30, shelfLabel, const Color(0xFF2F7B58));
    tag(
      GameController.checkoutZone,
      0.26,
      checkoutLabel,
      const Color(0xFF3C4F58),
    );
    if (game.bakeryUnlocked) {
      tag(GameController.bakeryZone, 0.28, bakeryLabel, _bakeryBody);
    }
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
          // Brand-tinted ramp. A neutral grey surround left roughly a third of
          // the board screen visually dead, which is the main reason the market
          // read as flat next to the colourful fixtures.
          colors: [Color(0xFFDFF1E7), Color(0xFFB4D9C7)],
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
          // Back-of-house apron. Previously a warm beige that filled roughly a
          // third of the board with a dull, undesigned band; a cool slate-green
          // reads as the shop's surround and lets the lit sales floor pop.
          const [Color(0xFF97B7A8), Color(0xFFB6CFC2)],
        ),
    );

    // Rim light where the apron meets the sales floor, so the lit field looks
    // raised rather than pasted onto the apron.
    canvas.drawPath(
      p.groundPath(),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.6, 2.4 * p.scale)
        ..color = Colors.white.withValues(alpha: 0.55),
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
    // shelves look, so the board reflects play state at a glance. Each run is a
    // different category so the aisles read as a colourful shop, not a row of
    // identical green blocks.
    // Two tidy aisles with a clear walking lane between and gaps between the
    // runs, so the floor reads as open rather than packed wall to wall.
    const runs = <({double x, double y, double length, int category})>[
      (x: 0.14, y: 0.26, length: 0.20, category: 0),
      (x: 0.14, y: 0.54, length: 0.20, category: 1),
      (x: 0.42, y: 0.26, length: 0.20, category: 2),
      (x: 0.42, y: 0.54, length: 0.20, category: 3),
    ];
    final fillRatio = (game.shelfStock / 12).clamp(0.0, 1.0);
    for (final run in runs) {
      add(
        IsoProjection.depthOf(run.x + 0.07, run.y + run.length),
        (canvas) => _shelfRun(
          canvas,
          brush,
          p,
          run.x,
          run.y,
          run.length,
          fillRatio,
          run.category,
        ),
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

    // Dressing, kept to the corners only. Props in the middle of the floor
    // made the shop feel cramped; the aisles need clear walking space to read
    // as roomy, so the produce bins are gone and only corner greenery and a
    // single tucked-away trolley remain.
    const planters = <Offset>[Offset(0.05, 0.92), Offset(0.92, 0.06)];
    for (final spot in planters) {
      add(
        IsoProjection.depthOf(spot.dx, spot.dy),
        (canvas) => _planter(canvas, brush, spot),
      );
    }

    add(
      IsoProjection.depthOf(0.93, 0.9),
      (canvas) => _trolley(canvas, brush, const Offset(0.93, 0.9)),
    );
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
    brush.sphere(
      canvas,
      x: at.dx,
      y: at.dy,
      z: 0.10,
      radius: 0.062,
      color: const Color(0xFF3E8F4F),
    );
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

  /// A category colour theme for one gondola: the header/kick trim plus the
  /// palette its products are drawn from.
  static ({Color trim, List<Color> products}) _category(int index) =>
      switch (index % 4) {
        // Produce — greens and a splash of fruit.
        0 => (
          trim: const Color(0xFF3FA85C),
          products: const [
            Color(0xFF66C24E),
            Color(0xFFF2B134),
            Color(0xFFE0573F),
            Color(0xFF8ED04F),
          ],
        ),
        // Snacks — warm reds and oranges.
        1 => (
          trim: const Color(0xFFE8663C),
          products: const [
            Color(0xFFF07A3D),
            Color(0xFFE0453B),
            Color(0xFFF2B134),
            Color(0xFFD98BC0),
          ],
        ),
        // Drinks — blues and teals.
        2 => (
          trim: const Color(0xFF3D8FD4),
          products: const [
            Color(0xFF4FA3E8),
            Color(0xFF43C7C7),
            Color(0xFF6E7BE0),
            Color(0xFFE8C34A),
          ],
        ),
        // Household — violets and cool tones.
        _ => (
          trim: const Color(0xFF9B6FD4),
          products: const [
            Color(0xFFB07CE8),
            Color(0xFF5FB0E0),
            Color(0xFFEF8FB0),
            Color(0xFFE8C34A),
          ],
        ),
      };

  void _shelfRun(
    Canvas canvas,
    IsoBrush brush,
    IsoProjection p,
    double x,
    double y,
    double length,
    double fill,
    int category,
  ) {
    const width = 0.10;
    const deckHeight = 0.05;
    final theme = _category(category);

    brush.groundShadow(
      canvas,
      x: x + width / 2,
      y: y + length / 2,
      radiusX: width * 1.7,
      radiusY: length * 1.35,
      opacity: 0.24,
    );

    // White cabinet with a coloured kick strip — real gondolas read as bright
    // fixtures, not solid slabs.
    brush.box(
      canvas,
      x0: x,
      y0: y,
      x1: x + width,
      y1: y + length,
      height: deckHeight,
      color: const Color(0xFFF3F1EA),
      topColor: const Color(0xFFFBFAF5),
    );
    brush.box(
      canvas,
      x0: x,
      y0: y,
      x1: x + width,
      y1: y + length,
      base: 0,
      height: 0.014,
      color: theme.trim,
      outline: false,
    );

    // Recognisable products in two dense columns. The item shape follows the
    // aisle category — bottles in drinks, boxes with a label in snacks and
    // household, fruit in crates in produce — so the shelves read as a real
    // shop, not rows of coloured cubes.
    const cols = 2;
    final gap = 0.011;
    final colW = (width - gap * (cols + 1)) / cols;
    final rows = (length / 0.03).floor();
    final stocked = (rows * fill).clamp(0, rows).round();
    for (var r = 0; r < stocked; r++) {
      final cy = y + gap + r * 0.03;
      for (var c = 0; c < cols; c++) {
        final cx = x + gap + c * (colW + gap);
        final seed = r * cols + c + (x * 53).round() + category * 7;
        final colour = theme.products[seed % theme.products.length];
        _product(
          canvas,
          brush,
          cx,
          cy,
          colW,
          deckHeight,
          colour,
          category,
          seed,
        );
      }
    }

    // Coloured header board standing at the back of the run — the aisle's
    // category banner.
    brush.box(
      canvas,
      x0: x,
      y0: y,
      x1: x + 0.012,
      y1: y + length,
      base: deckHeight + 0.10,
      height: 0.03,
      color: theme.trim,
      topColor: IsoLight.lift(theme.trim, 0.25),
      outline: false,
    );
  }

  /// One recognisable grocery item on a shelf slot [cx],[cy] of width [w],
  /// standing on the deck at height [base]. Shape depends on the aisle
  /// [category]; [seed] adds small per-item variation.
  void _product(
    Canvas canvas,
    IsoBrush brush,
    double cx,
    double cy,
    double w,
    double base,
    Color color,
    int category,
    int seed,
  ) {
    const d = 0.022; // slot depth
    switch (category) {
      case 2: // Drinks — a bottle: slim body, white label band, dark cap.
        final bx0 = cx + w * 0.30;
        final bx1 = cx + w * 0.70;
        brush.box(
          canvas,
          x0: bx0,
          y0: cy + d * 0.16,
          x1: bx1,
          y1: cy + d * 0.84,
          base: base,
          height: 0.052,
          color: color,
          topColor: IsoLight.lift(color, 0.28),
          outline: false,
        );
        brush.box(
          canvas,
          x0: bx0,
          y0: cy + d * 0.16,
          x1: bx1,
          y1: cy + d * 0.84,
          base: base + 0.02,
          height: 0.012,
          color: Colors.white.withValues(alpha: 0.9),
          outline: false,
        );
        brush.box(
          canvas,
          x0: cx + w * 0.40,
          y0: cy + d * 0.34,
          x1: cx + w * 0.60,
          y1: cy + d * 0.66,
          base: base + 0.052,
          height: 0.014,
          color: IsoLight.shade(color, 0.55),
          outline: false,
        );
      case 0: // Produce — a shallow crate heaped with round fruit.
        brush.box(
          canvas,
          x0: cx,
          y0: cy,
          x1: cx + w,
          y1: cy + d,
          base: base,
          height: 0.018,
          color: const Color(0xFF9C6B3C),
          outline: false,
        );
        for (var i = 0; i < 2; i++) {
          brush.sphere(
            canvas,
            x: cx + w * (0.32 + 0.36 * i),
            y: cy + d * 0.5,
            z: base + 0.03,
            radius: w * 0.62,
            color: i.isEven ? color : IsoLight.lift(color, 0.18),
          );
        }
      default: // Snacks / household — a box with a bright label panel.
        final h = 0.05 + (seed % 3) * 0.006;
        brush.box(
          canvas,
          x0: cx,
          y0: cy,
          x1: cx + w,
          y1: cy + d,
          base: base,
          height: h,
          color: color,
          topColor: IsoLight.lift(color, 0.30),
          outline: false,
        );
        // Label band wrapped around the box just below the top.
        brush.box(
          canvas,
          x0: cx,
          y0: cy,
          x1: cx + w,
          y1: cy + d,
          base: base + h * 0.42,
          height: h * 0.30,
          color: Colors.white.withValues(alpha: 0.82),
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
      topColor: const Color(0xFF6FB8DE),
    );
    // Colourful stock standing inside, seen through the glass.
    const drinks = [
      Color(0xFFE0453B),
      Color(0xFFF2B134),
      Color(0xFF66C24E),
      Color(0xFF4FA3E8),
      Color(0xFFD98BC0),
    ];
    final slots = ((y1 - y0 - 0.03) / 0.03).floor();
    for (var i = 0; i < slots; i++) {
      final sy = y0 + 0.03 + i * 0.03;
      brush.box(
        canvas,
        x0: x + 0.03,
        y0: sy,
        x1: x + 0.078,
        y1: sy + 0.02,
        base: 0.04,
        height: 0.12,
        color: drinks[(i + (y0 * 40).round()) % drinks.length],
        outline: false,
      );
    }
    // Glass door on the face turned toward the shop floor.
    brush.panel(
      canvas,
      x0: x + 0.09,
      y0: y0 + 0.02,
      x1: x + 0.09,
      y1: y1 - 0.02,
      base: 0.035,
      top: 0.185,
      color: const Color(0x66CDECF7),
    );
    // Bright frame highlight along the top of the unit.
    brush.box(
      canvas,
      x0: x,
      y0: y0,
      x1: x + 0.09,
      y1: y0 + 0.012,
      base: 0.20,
      height: 0.016,
      color: const Color(0xFF8FD0EC),
      outline: false,
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
    // Bright counter top so the till reads as the shop's focal point.
    brush.box(
      canvas,
      x0: x,
      y0: y,
      x1: x + 0.15,
      y1: y + 0.11,
      base: 0.072,
      height: 0.008,
      color: const Color(0xFF37C88E),
      outline: false,
    );
    if (!unlocked) return;
    // Register block and its screen.
    brush.box(
      canvas,
      x0: x + 0.015,
      y0: y + 0.02,
      x1: x + 0.062,
      y1: y + 0.07,
      base: 0.08,
      height: 0.055,
      color: const Color(0xFF2C3B44),
      outline: false,
    );
    brush.panel(
      canvas,
      x0: x + 0.062,
      y0: y + 0.025,
      x1: x + 0.062,
      y1: y + 0.065,
      base: 0.098,
      top: 0.133,
      color: const Color(0xFF6FE3B4),
    );
    // Belt with a few grocery items riding along it.
    brush.groundQuad(
      canvas,
      x0: x + 0.075,
      y0: y + 0.018,
      x1: x + 0.142,
      y1: y + 0.092,
      color: const Color(0xFF25333A),
      z: 0.081,
    );
    const items = [Color(0xFFE0453B), Color(0xFFF2B134), Color(0xFF66C24E)];
    for (var i = 0; i < 3; i++) {
      brush.box(
        canvas,
        x0: x + 0.088 + i * 0.018,
        y0: y + 0.04,
        x1: x + 0.10 + i * 0.018,
        y1: y + 0.066,
        base: 0.081,
        height: 0.028,
        color: items[i],
        outline: false,
      );
    }
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

  /// Mood above a shopper. Only shown when it tells the player something they
  /// can act on — a shopper running out of patience, a VIP, or a big spender.
  _Mood? _customerBubble(MarketCustomer customer) {
    if (customer.phase == CustomerPhase.leaving) return null;
    if (customer.patience < 2.2) return _Mood.impatient;
    if (customer.isVip) return _Mood.vip;
    if (customer.phase == CustomerPhase.checkout ||
        customer.phase == CustomerPhase.paying) {
      return _Mood.paying;
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
    _Mood? bubble,
  }) {
    final x = at.dx.clamp(0.0, 1.0);
    final y = at.dy.clamp(0.0, 1.0);
    final p = brush.projection;
    final ground = p.project(x, y);

    // Shoulder width drives every other measurement so the figure scales as a
    // unit with the board. Kept small so shoppers read as tidy figures rather
    // than looming over the shelves.
    final u = p.tileWidth * 0.034;
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
      pill(
        ground.dx - u * 0.92,
        baseY - u * 1.30 + stride * 0.5,
        u * 0.40,
        u * 1.02,
      ),
      paint,
    );
    canvas.drawRRect(
      pill(
        ground.dx + u * 0.92,
        baseY - u * 1.30 - stride * 0.5,
        u * 0.40,
        u * 1.02,
      ),
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
  void _speechBubble(Canvas canvas, Offset at, double u, _Mood mood) {
    final paint = Paint()..isAntiAlias = true;
    final rect = Rect.fromCenter(center: at, width: u * 1.7, height: u * 1.35);
    paint.color = const Color(0xF7FFFFFF);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(u * 0.46)),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(at.dx - u * 0.24, rect.bottom - u * 0.06)
        ..lineTo(at.dx, rect.bottom + u * 0.36)
        ..lineTo(at.dx + u * 0.18, rect.bottom - u * 0.06)
        ..close(),
      paint,
    );

    // Icons are drawn, not typed: CanvasKit on web has no emoji font, so glyph
    // bubbles rendered as empty tofu boxes.
    final r = u * 0.44;
    switch (mood) {
      case _Mood.vip:
        _drawStar(canvas, at, r, _accentGold);
      case _Mood.paying:
        paint.color = const Color(0xFFE0A11E);
        canvas.drawCircle(at, r, paint);
        paint.color = const Color(0xFFFFD466);
        canvas.drawCircle(at, r * 0.74, paint);
        final s = TextPainter(
          text: TextSpan(
            text: r'$',
            style: TextStyle(
              color: const Color(0xFF7A5310),
              fontSize: u * 0.78,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        s.paint(canvas, at - Offset(s.width / 2, s.height / 2));
      case _Mood.impatient:
        paint.color = const Color(0xFFE0483C);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: at.translate(0, -u * 0.1),
              width: u * 0.26,
              height: u * 0.66,
            ),
            Radius.circular(u * 0.13),
          ),
          paint,
        );
        canvas.drawCircle(at.translate(0, u * 0.42), u * 0.15, paint);
    }
  }

  void _drawStar(Canvas canvas, Offset c, double r, Color color) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final radius = i.isEven ? r : r * 0.46;
      final a = -math.pi / 2 + i * math.pi / 5;
      final point = c + Offset(math.cos(a) * radius, math.sin(a) * radius);
      i == 0
          ? path.moveTo(point.dx, point.dy)
          : path.lineTo(point.dx, point.dy);
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..isAntiAlias = true,
    );
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
      final pop = progress < 0.16 ? 0.72 + 0.28 * (progress / 0.16) : 1.0;
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
                color: const Color(
                  0xFF04211A,
                ).withValues(alpha: 0.65 * opacity.clamp(0.0, 1.0)),
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
        Offset(
          anchor.dx - painter.width / 2,
          anchor.dy - rise - painter.height,
        ),
      );
    }
  }

  void _paintAmbience(Canvas canvas, Size size, IsoProjection p) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          rect.center,
          rect.longestSide * 0.62,
          [const Color(0x0016241F), const Color(0x2216241F)],
          [0.55, 1],
        ),
    );
  }

  @override
  bool shouldRepaint(covariant IsoMarketPainter oldDelegate) => true;
}

/// Actionable shopper moods surfaced as a bubble above the figure.
enum _Mood { vip, paying, impatient }
