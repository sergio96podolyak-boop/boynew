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
  static const _wallUpper = Color(0xFFE8F2EC);
  static const _wallLower = Color(0xFFBFD9CC);
  static const _wallJoint = Color(0x33607A6E);
  static const _wallSkirt = Color(0xFF5E7C70);
  static const _wallCap = Color(0xFFF6FBF8);
  static const _fridgeBody = Color(0xFF3D8FC4);
  static const _counterBody = Color(0xFF3C4F58);
  static const _crateBody = Color(0xFFB07C43);
  static const _bakeryBody = Color(0xFFE0A542);
  static const _accentGold = Color(0xFFFFC33D);

  // --------------------------------------------------------------- dimensions
  //
  // Everything in the scene is sized in metres against a twelve-metre-wide
  // sales floor. The previous fixtures were authored by eye, which is why a
  // gondola ended up 0.33 world units tall against a 0.14-unit shopper — the
  // shelves were literally taller than the people and each run swallowed most
  // of the floor. One scale constant makes proportion checkable instead of a
  // matter of taste.
  static const _floorMetres = 12.0;
  static const double _m = 1 / _floorMetres;

  static const _personHeight = 1.70 * _m;
  static const _gondolaHeight = 1.45 * _m;
  static const _gondolaDepth = 0.90 * _m;
  static const _gondolaLength = 4.20 * _m;
  static const _aisleWidth = 2.30 * _m;
  static const _counterHeight = 0.95 * _m;
  static const _chillerHeight = 2.00 * _m;
  static const _chillerDepth = 0.80 * _m;
  static const _promoRed = Color(0xFFE8503F);

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
    _paintAffordances(canvas, brush, projection);

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
    if (game.shelfStock < 3) {
      _alertMarker(canvas, projection, GameController.shelfZone, 0.74);
    }
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
          style: TextStyle(
            color: Colors.white,
            fontSize: math.max(7, 8.5 * p.scale),
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
            height: 1,
          ),
        ),
      )..layout();
      final w = painter.width + 20 * p.scale;
      final h = painter.height + 6 * p.scale;
      final rect = Rect.fromCenter(
        center: Offset(anchor.dx, anchor.dy),
        width: w,
        height: h,
      );
      final rrect = RRect.fromRectAndRadius(rect, Radius.circular(h / 2));
      canvas.drawRRect(
        rrect.shift(Offset(0, 1.5 * p.scale)),
        Paint()..color = const Color(0x4404211A),
      );
      canvas.drawRRect(
        rrect,
        Paint()..color = const Color(0xE60D2A21),
      );
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.8, 1 * p.scale)
          ..color = color.withValues(alpha: 0.75),
      );
      // Zone colour reads from the dot, so the tag itself can stay quiet.
      canvas.drawCircle(
        Offset(rect.left + h * 0.42, rect.center.dy),
        h * 0.16,
        Paint()..color = color,
      );
      painter.paint(
        canvas,
        Offset(
          rect.left + h * 0.72,
          anchor.dy - painter.height / 2,
        ),
      );
    }

    tag(GameController.stockZone, 2.5 * _m, storageLabel, const Color(0xFF4A6B76));
    tag(GameController.shelfZone, 2.6 * _m, shelfLabel, const Color(0xFF2F7B58));
    tag(
      GameController.checkoutZone,
      2.7 * _m,
      checkoutLabel,
      const Color(0xFF3C4F58),
    );
    if (game.bakeryUnlocked) {
      tag(GameController.bakeryZone, 2.5 * _m, bakeryLabel, _bakeryBody);
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
          // Matched to the apron so the room has no visible outer edge: a
          // hard seam around the floor is what made the shop read as a model
          // sitting on a table rather than a space you are standing in.
          colors: [Color(0xFF9DBBAD), Color(0xFFAFC8BB)],
        ).createShader(rect),
    );
  }

  /// The shop's architecture: two full-height walls, wainscot, brand fascia,
  /// signage and a back-of-house doorway.
  ///
  /// The walls used to be 0.15 units — a kerb, not a room — so the shop read as
  /// props scattered on an open plane. Real height gives the scene a back, and
  /// a back is what turns a diagram into an interior.
  void _paintWalls(Canvas canvas, IsoBrush brush, IsoProjection p) {
    const h = IsoProjection.wallHeight;
    const wainscot = 1.15 * _m;
    const m = IsoProjection.roomMargin;
    const lo = -m;
    const hi = 1 + m;
    final paint = Paint()..isAntiAlias = true;

    Path band(Offset a, Offset b, double z0, double z1) => Path()
      ..moveTo(p.projectOffset(a, z0).dx, p.projectOffset(a, z0).dy)
      ..lineTo(p.projectOffset(b, z0).dx, p.projectOffset(b, z0).dy)
      ..lineTo(p.projectOffset(b, z1).dx, p.projectOffset(b, z1).dy)
      ..lineTo(p.projectOffset(a, z1).dx, p.projectOffset(a, z1).dy)
      ..close();

    // Two runs: back-right along y = lo, back-left along x = lo. Each is shaded
    // differently because they face different ways relative to the key light.
    final runs = <({Offset a, Offset b, double shade})>[
      (a: const Offset(lo, lo), b: const Offset(hi, lo), shade: 1.0),
      (a: const Offset(lo, lo), b: const Offset(lo, hi), shade: 0.86),
    ];

    for (final run in runs) {
      Color tone(Color c) => IsoLight.shade(c, run.shade);

      // Upper painted wall.
      paint
        ..shader = null
        ..color = tone(_wallUpper);
      canvas.drawPath(band(run.a, run.b, wainscot, h), paint);

      // Lower tiled wainscot, darker so the floor line reads.
      paint.color = tone(_wallLower);
      canvas.drawPath(band(run.a, run.b, 0, wainscot), paint);

      // Vertical tile joints on the wainscot.
      final joints = Paint()
        ..color = tone(_wallLower).withValues(alpha: 0.0)
        ..blendMode = BlendMode.srcOver;
      joints.color = IsoLight.shade(_wallJoint, run.shade);
      joints.strokeWidth = math.max(0.6, 0.8 * p.scale);
      final horizontal = run.b.dx - run.a.dx != 0;
      for (var i = 1; i < 26; i++) {
        final t = i / 26;
        final at = horizontal
            ? Offset(run.a.dx + (run.b.dx - run.a.dx) * t, run.a.dy)
            : Offset(run.a.dx, run.a.dy + (run.b.dy - run.a.dy) * t);
        canvas.drawLine(
          p.projectOffset(at, 0),
          p.projectOffset(at, wainscot),
          joints,
        );
      }

      // Brand fascia running the length of the wall at head height.
      paint.color = IsoLight.shade(_accentGold, run.shade);
      canvas.drawPath(
        band(run.a, run.b, wainscot, wainscot + 0.14 * _m),
        paint,
      );
      paint.color = IsoLight.shade(_wallCap, run.shade);
      canvas.drawPath(band(run.a, run.b, h - 0.18 * _m, h), paint);

      // Skirting where the wall meets the floor.
      paint.color = IsoLight.shade(_wallSkirt, run.shade);
      canvas.drawPath(band(run.a, run.b, 0, 0.14 * _m), paint);

      // Ambient occlusion up from the floor line, then a light wash down from
      // the ceiling: the pair is what stops a large flat wall looking like a
      // sheet of paper.
      final foot = p.projectOffset(run.a);
      final head = p.projectOffset(run.a, h);
      canvas.save();
      canvas.clipPath(band(run.a, run.b, 0, h));
      canvas.drawPath(
        band(run.a, run.b, 0, h),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(foot.dx, foot.dy),
            Offset(foot.dx, head.dy),
            [const Color(0x4A06231A), const Color(0x0006231A)],
          ),
      );
      canvas.drawPath(
        band(run.a, run.b, 0, h),
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.linear(
            Offset(head.dx, head.dy),
            Offset(head.dx, foot.dy),
            [const Color(0x22FFF4DA), const Color(0x00FFF4DA)],
          ),
      );
      canvas.restore();
    }

    // Back-of-house doorway on the left wall — a dark opening reading as depth
    // beyond the room.
    paint
      ..shader = null
      ..color = const Color(0xFF14312A);
    canvas.drawPath(
      band(const Offset(lo, 0.30), const Offset(lo, 0.48), 0, 2.20 * _m),
      paint,
    );
    paint.color = const Color(0xFF0A1F19);
    canvas.drawPath(
      band(const Offset(lo, 0.315), const Offset(lo, 0.465), 0, 2.05 * _m),
      paint,
    );
    paint.color = _accentGold.withValues(alpha: 0.85);
    canvas.drawPath(
      band(const Offset(lo, 0.30), const Offset(lo, 0.48), 2.20 * _m, 2.32 * _m),
      paint,
    );

    // Window band on the right wall, letting daylight into the room.
    paint.color = const Color(0xFFBFE7F2);
    canvas.drawPath(
      band(const Offset(0.18, lo), const Offset(0.86, lo), 1.55 * _m, 2.85 * _m),
      paint,
    );
    canvas.save();
    canvas.clipPath(
      band(const Offset(0.18, lo), const Offset(0.86, lo), 1.55 * _m, 2.85 * _m),
    );
    final winA = p.project(0.18, lo, 2.85 * _m);
    final winB = p.project(0.18, lo, 1.55 * _m);
    canvas.drawPath(
      band(const Offset(0.18, lo), const Offset(0.86, lo), 1.55 * _m, 2.85 * _m),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(winA.dx, winA.dy),
          Offset(winA.dx, winB.dy),
          [const Color(0xFFF4FCFF), const Color(0xFF8FCBDE)],
        ),
    );
    canvas.restore();
    // Mullions.
    final mullion = Paint()
      ..color = _wallCap
      ..strokeWidth = math.max(1.4, 2.2 * p.scale);
    for (var i = 0; i <= 4; i++) {
      final x = 0.18 + (0.86 - 0.18) * i / 4;
      canvas.drawLine(
        p.project(x, lo, 1.55 * _m),
        p.project(x, lo, 2.85 * _m),
        mullion,
      );
    }
    canvas.drawLine(
      p.project(0.18, lo, 2.85 * _m),
      p.project(0.86, lo, 2.85 * _m),
      mullion,
    );

    // Corner post where the two walls meet, so the join reads as built.
    paint.color = _wallCap;
    canvas.drawPath(
      band(const Offset(lo, lo), const Offset(lo + 0.012, lo), 0, h),
      paint,
    );
  }

  // ------------------------------------------------------------------- floor

  void _paintFloor(Canvas canvas, IsoBrush brush, IsoProjection p) {
    // Back-of-house apron reaching past the play field to the frame edges.
    final room = p.roomPath();
    final roomBounds = room.getBounds();
    canvas.drawPath(
      room,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(roomBounds.center.dx, roomBounds.top),
          Offset(roomBounds.center.dx, roomBounds.bottom),
          const [Color(0xFF8FB0A2), Color(0xFFB0C9BD)],
        ),
    );

    // Apron tiling, on a coarser grid than the sales floor so the two surfaces
    // read as different materials rather than one continuous plane.
    canvas.save();
    canvas.clipPath(room);
    final apronSeam = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.5, 0.7 * p.scale)
      ..color = const Color(0x1A0A2A1E);
    const lo = -IsoProjection.farMargin;
    const hi = 1 + IsoProjection.nearMargin;
    for (var i = -2; i <= 17; i++) {
      final t = i / 8;
      canvas.drawLine(p.project(t, lo), p.project(t, hi), apronSeam);
      canvas.drawLine(p.project(lo, t), p.project(hi, t), apronSeam);
    }
    canvas.restore();

    final ground = p.groundPath();
    final bounds = ground.getBounds();

    // Sales floor: a polished light terrazzo, brighter toward the camera so the
    // near half of the shop is the lit stage.
    canvas.drawPath(
      ground,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(bounds.center.dx, bounds.top),
          Offset(bounds.center.dx, bounds.bottom),
          const [_floorDark, _floorLight],
        ),
    );

    // Zone materials. A single checkerboard over the whole floor told the
    // player nothing; different surfaces per area are how a real shop signals
    // "this part of the room does a different job".
    canvas.save();
    canvas.clipPath(ground);

    // Chiller aisle: cool grey, running the full left edge.
    brush.groundQuad(
      canvas,
      x0: -0.02,
      y0: -0.02,
      x1: 0.16,
      y1: 1.02,
      color: const Color(0xFFDCE6E8),
    );
    // Bakery: warm boards.
    brush.groundQuad(
      canvas,
      x0: GameController.bakeryZone.dx - 0.10,
      y0: GameController.bakeryZone.dy - 0.12,
      x1: GameController.bakeryZone.dx + 0.16,
      y1: GameController.bakeryZone.dy + 0.14,
      color: const Color(0xFFE6C79A),
    );
    // Checkout apron: a slightly darker service surface.
    brush.groundQuad(
      canvas,
      x0: 0.52,
      y0: -0.02,
      x1: 1.02,
      y1: 0.30,
      color: const Color(0xFFDDE3DE),
    );

    // Circulation lane: the bright walkway the shopper follows from the door,
    // round the aisles and to the tills. It is the scene's main line of
    // movement and it was completely absent.
    const laneColour = Color(0x40FFFFFF);
    brush.groundQuad(
      canvas,
      x0: 0.30,
      y0: 0.86,
      x1: 1.02,
      y1: 0.99,
      color: laneColour,
    );
    brush.groundQuad(
      canvas,
      x0: 0.30,
      y0: 0.02,
      x1: 0.40,
      y1: 0.99,
      color: laneColour,
    );
    brush.groundQuad(
      canvas,
      x0: 0.66,
      y0: 0.02,
      x1: 0.76,
      y1: 0.99,
      color: laneColour,
    );

    // Tile grid, tighter than before so the floor has a real sense of scale.
    const divisions = 14;
    final seam = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.5, 0.6 * p.scale)
      ..color = _floorSeam;
    for (var i = 1; i < divisions; i++) {
      final t = i / divisions;
      canvas.drawLine(p.project(t, 0), p.project(t, 1), seam);
      canvas.drawLine(p.project(0, t), p.project(1, t), seam);
    }

    // Specular sheen sweeping across the polished floor.
    canvas.drawRect(
      bounds,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.linear(
          bounds.topLeft,
          bounds.bottomRight,
          [
            const Color(0x00FFFFFF),
            const Color(0x1FFFFFFF),
            const Color(0x00FFFFFF),
          ],
          const [0.25, 0.5, 0.78],
        ),
    );
    canvas.restore();

    // Foreground falloff: the apron nearest the camera drops away into shadow
    // so the frame closes rather than trailing off into flat colour.
    canvas.drawPath(
      room,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(roomBounds.center.dx, bounds.bottom),
          Offset(roomBounds.center.dx, roomBounds.bottom),
          const [Color(0x0004150F), Color(0x8C04150F)],
        ),
    );

    // Rim light where the sales floor meets the apron, so the lit stage reads
    // as raised out of the back-of-house.
    canvas.drawPath(
      ground,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.6, 2.4 * p.scale)
        ..color = Colors.white.withValues(alpha: 0.55),
    );
  }

  /// Hanging light rig. Pools of light alone read as stains on the floor; the
  /// fixtures themselves are what tell the player there is a ceiling up there.
  void _paintCeilingLights(Canvas canvas, IsoProjection p) {
    const spots = <Offset>[
      Offset(0.24, 0.24),
      Offset(0.74, 0.24),
      Offset(0.24, 0.74),
      Offset(0.74, 0.74),
      Offset(0.49, 0.49),
    ];

    // Floor pools first, clipped to the sales floor.
    canvas.save();
    canvas.clipPath(p.groundPath());
    for (final spot in spots) {
      final centre = p.project(spot.dx, spot.dy);
      final radius = p.tileWidth * 0.26;
      canvas.drawOval(
        Rect.fromCenter(
          center: centre,
          width: radius * 2,
          height: radius * 1.05,
        ),
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.radial(centre, radius, [
            const Color(0x3AFFEBC2),
            const Color(0x00FFEBC2),
          ]),
      );
    }
    canvas.restore();

    // Then the fixtures, hanging from the rig.
    const z = IsoProjection.ceilingHeight;
    for (final spot in spots) {
      final anchor = p.project(spot.dx, spot.dy, z + 0.14);
      final lamp = p.project(spot.dx, spot.dy, z);
      canvas.drawLine(
        anchor,
        lamp,
        Paint()
          ..color = const Color(0x99223A31)
          ..strokeWidth = math.max(1, 1.4 * p.scale),
      );
      final r = p.tileWidth * 0.035;
      // Shade: a shallow cone seen from slightly above.
      canvas.drawPath(
        Path()
          ..moveTo(lamp.dx - r, lamp.dy)
          ..lineTo(lamp.dx + r, lamp.dy)
          ..lineTo(lamp.dx + r * 0.34, lamp.dy - r * 1.1)
          ..lineTo(lamp.dx - r * 0.34, lamp.dy - r * 1.1)
          ..close(),
        Paint()..color = const Color(0xFF2C4C3F),
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(lamp.dx, lamp.dy),
          width: r * 2,
          height: r * 0.8,
        ),
        Paint()..color = const Color(0xFFFFF0C8),
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(lamp.dx, lamp.dy + r * 0.1),
          width: r * 3.4,
          height: r * 1.8,
        ),
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.radial(
            Offset(lamp.dx, lamp.dy),
            r * 1.7,
            [const Color(0x55FFE9B8), const Color(0x00FFE9B8)],
          ),
      );
    }
  }

  /// Floor-level interaction affordances.
  ///
  /// The scene previously gave the player no spatial feedback at all: nothing
  /// showed where they were heading, which zone was live, or which fixture
  /// needed attention. These are drawn on the ground, under the fixtures, so
  /// they read as markings in the world rather than as an overlay on top of it.
  void _paintAffordances(Canvas canvas, IsoBrush brush, IsoProjection p) {
    final t = game.totalPlaySeconds;
    canvas.save();
    canvas.clipPath(p.groundPath());

    /// A pulsing ring painted flat on the floor at a world position.
    void ring(Offset at, Color colour, double radius, double phase) {
      final pulse = 0.5 + 0.5 * math.sin(t * 2.4 + phase);
      final r = radius * (0.86 + 0.14 * pulse);
      final centre = p.projectOffset(at);
      final rect = Rect.fromCenter(
        center: centre,
        width: r * p.tileWidth,
        height: r * p.tileHeight,
      );
      canvas.drawOval(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.6, 2.6 * p.scale)
          ..color = colour.withValues(alpha: 0.30 + 0.34 * pulse),
      );
      canvas.drawOval(
        rect,
        Paint()
          ..shader = ui.Gradient.radial(centre, rect.width / 2, [
            colour.withValues(alpha: 0.20 * pulse),
            colour.withValues(alpha: 0),
          ]),
      );
    }

    // Live zones: where the player can act right now.
    ring(GameController.stockZone, const Color(0xFF6FD3E8), 0.30, 0);
    ring(GameController.shelfZone, const Color(0xFF56E8A9), 0.34, 1.1);
    ring(GameController.checkoutZone, const Color(0xFFFFC33D), 0.30, 2.2);
    if (game.bakeryUnlocked) {
      ring(GameController.bakeryZone, _bakeryBody, 0.28, 3.1);
    }

    // Carry state: a trail under the player while they are holding stock, so
    // the run from the storeroom to the shelves is legible at a glance.
    if (game.carried > 0) {
      final from = GameController.stockZone;
      final to = GameController.shelfZone;
      for (var i = 1; i < 7; i++) {
        final k = i / 7;
        final at = Offset(
          from.dx + (to.dx - from.dx) * k,
          from.dy + (to.dy - from.dy) * k,
        );
        final fade = (math.sin(t * 3 - i * 0.7) + 1) / 2;
        final centre = p.projectOffset(at);
        canvas.drawOval(
          Rect.fromCenter(
            center: centre,
            width: 0.05 * p.tileWidth,
            height: 0.05 * p.tileHeight,
          ),
          Paint()
            ..color = _accentGold.withValues(alpha: 0.18 + 0.30 * fade),
        );
      }
    }

    canvas.restore();
  }

  /// Attention marker floating over a fixture that needs the player.
  void _alertMarker(Canvas canvas, IsoProjection p, Offset at, double lift) {
    final t = game.totalPlaySeconds;
    final hover = math.sin(t * 3.2) * p.unitHeight * 0.012;
    final anchor = p.project(at.dx, at.dy, lift);
    final centre = Offset(anchor.dx, anchor.dy + hover);
    final r = math.max(7.0, 9.0 * p.scale);

    canvas.drawCircle(
      centre,
      r * 1.7,
      Paint()
        ..shader = ui.Gradient.radial(centre, r * 1.7, [
          const Color(0x66FF6B6B),
          const Color(0x00FF6B6B),
        ]),
    );
    canvas.drawCircle(
      centre.translate(0, r * 0.22),
      r,
      Paint()..color = const Color(0x5504211A),
    );
    canvas.drawCircle(centre, r, Paint()..color = const Color(0xFFE8503F));
    canvas.drawCircle(
      centre,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, 1.4 * p.scale)
        ..color = Colors.white.withValues(alpha: 0.85),
    );
    final bar = Paint()..color = Colors.white;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: centre.translate(0, -r * 0.14),
          width: r * 0.24,
          height: r * 0.74,
        ),
        Radius.circular(r * 0.12),
      ),
      bar,
    );
    canvas.drawCircle(centre.translate(0, r * 0.44), r * 0.13, bar);
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
    // Two 4.2 m gondola runs with a 2.3 m aisle between them, set in the
    // middle-left of the floor. Three seven-metre runs filled the shop wall to
    // wall and left no circulation — the store read as a maze of furniture.
    // Fewer, correctly-sized fixtures leave the open floor that makes a shop
    // navigable and lets the eye rest.
    const runs = <({double x, double y, double length, int category})>[
      (x: 0.30, y: 0.20, length: _gondolaLength, category: 0),
      (
        x: 0.30 + _gondolaDepth + _aisleWidth,
        y: 0.20,
        length: _gondolaLength,
        category: 1,
      ),
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

    // Chiller run along the far-left wall, clear of the aisles.
    for (var i = 0; i < 3; i++) {
      final y = 0.12 + i * 0.20;
      add(
        IsoProjection.depthOf(0.06 + _chillerDepth, y + 0.17),
        (canvas) => _fridge(canvas, brush, p, 0.06, y, y + 0.17),
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
    // Promo island near the entrance — the seasonal dump bin every shop puts
    // in the first thing you walk past.
    add(
      IsoProjection.depthOf(0.42, 0.76),
      (canvas) => _promoIsland(canvas, brush, 0.34, 0.68),
    );
    // Trolley bay just inside the doors.
    add(
      IsoProjection.depthOf(0.68, 0.94),
      (canvas) => _trolleyBay(canvas, brush, 0.62, 0.88),
    );

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

  /// Seasonal promo island: a low bin heaped with produce under a price flag.
  void _promoIsland(Canvas canvas, IsoBrush brush, double x, double y) {
    const w = 0.14;
    const d = 0.14;
    brush.castShadow(
      canvas,
      x0: x,
      y0: y,
      x1: x + w,
      y1: y + d,
      height: 0.90 * _m,
    );
    brush.box(
      canvas,
      x0: x,
      y0: y,
      x1: x + w,
      y1: y + d,
      height: 0.75 * _m,
      color: const Color(0xFFE2E6E0),
      topColor: const Color(0xFFF6F8F4),
    );
    brush.box(
      canvas,
      x0: x,
      y0: y,
      x1: x + w,
      y1: y + d,
      height: 0.14 * _m,
      color: _accentGold,
      outline: false,
    );
    // Heaped stock.
    const heap = <(double, double, Color)>[
      (0.035, 0.040, Color(0xFFE8663C)),
      (0.075, 0.035, Color(0xFF3FA85C)),
      (0.050, 0.085, Color(0xFFFFC33D)),
      (0.095, 0.080, Color(0xFFE8663C)),
      (0.068, 0.060, Color(0xFF9B6FD4)),
    ];
    for (final (dx, dy, colour) in heap) {
      brush.sphere(
        canvas,
        x: x + dx,
        y: y + dy,
        z: 0.86 * _m,
        radius: 0.11 * _m,
        color: colour,
      );
    }
    // Price flag on a stem.
    brush.box(
      canvas,
      x0: x + w / 2 - 0.004,
      y0: y + d / 2 - 0.004,
      x1: x + w / 2 + 0.004,
      y1: y + d / 2 + 0.004,
      base: 0.90 * _m,
      height: 0.70 * _m,
      color: const Color(0xFFB9C4BD),
      outline: false,
    );
    brush.box(
      canvas,
      x0: x + w / 2 - 0.004,
      y0: y + d / 2 - 0.030,
      x1: x + w / 2 + 0.004,
      y1: y + d / 2 + 0.030,
      base: 1.55 * _m,
      height: 0.34 * _m,
      color: _promoRed,
      topColor: const Color(0xFFFF8A7A),
      outline: false,
    );
  }

  /// Trolley bay just inside the doors — nested trolleys against a rail.
  void _trolleyBay(Canvas canvas, IsoBrush brush, double x, double y) {
    brush.castShadow(
      canvas,
      x0: x,
      y0: y,
      x1: x + 0.07,
      y1: y + 0.16,
      height: 1.00 * _m,
    );
    for (var i = 0; i < 4; i++) {
      final oy = y + i * 0.026;
      brush.box(
        canvas,
        x0: x,
        y0: oy,
        x1: x + 0.062,
        y1: oy + 0.030,
        base: 0.22 * _m,
        height: 0.55 * _m,
        color: const Color(0xFFCFD8D2),
        topColor: const Color(0xFFEAF0EC),
        outline: false,
      );
    }
    // Guide rail.
    brush.box(
      canvas,
      x0: x - 0.014,
      y0: y - 0.010,
      x1: x - 0.006,
      y1: y + 0.17,
      base: 0,
      height: 0.95 * _m,
      color: const Color(0xFF9FB0A8),
      outline: false,
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

  /// A supermarket gondola: solid cabinet, coloured kick plate, three product
  /// bands facing the aisle and a lit header sign.
  ///
  /// Drawing each tier as its own deck box produced a staircase of bare white
  /// slabs whenever stock was low. A solid cabinet with the tiers expressed as
  /// bands on the aisle-facing face reads correctly at every stock level, and
  /// is how a real gondola looks from this angle anyway.
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
    const width = _gondolaDepth;
    const kick = 0.15 * _m;
    const height = _gondolaHeight - kick;
    const tiers = 3;
    final theme = _category(category);
    final top = kick + height;

    brush.castShadow(
      canvas,
      x0: x,
      y0: y,
      x1: x + width,
      y1: y + length,
      height: top,
    );

    // Coloured kick plate: the aisle's identity band at floor level.
    brush.box(
      canvas,
      x0: x,
      y0: y,
      x1: x + width,
      y1: y + length,
      height: kick,
      color: IsoLight.shade(theme.trim, 0.80),
      topColor: theme.trim,
      outline: false,
    );

    // Cabinet body.
    brush.box(
      canvas,
      x0: x,
      y0: y,
      x1: x + width,
      y1: y + length,
      base: kick,
      height: height,
      color: const Color(0xFFEDEFE9),
      topColor: const Color(0xFFF9FAF6),
    );

    // Product bands on the aisle-facing side. Each band is a shallow box
    // standing proud of the cabinet face, segmented along the run so individual
    // packs read at this scale.
    // One facing every 0.30 m along the run.
    final segments = (length / (0.30 * _m)).floor().clamp(3, 20);
    for (var t = 0; t < tiers; t++) {
      final base = kick + 0.10 * _m + t * (height - 0.30 * _m) / (tiers - 1);
      // Shelf lip the products stand on.
      brush.box(
        canvas,
        x0: x + width - 0.02 * _m,
        y0: y + 0.05 * _m,
        x1: x + width + 0.10 * _m,
        y1: y + length - 0.05 * _m,
        base: base - 0.04 * _m,
        height: 0.04 * _m,
        color: const Color(0xFFDFE3DC),
        topColor: const Color(0xFFF4F6F1),
        outline: false,
      );

      // Upper tiers sell down first, so an emptying shelf is legible.
      final tierFill = (fill * tiers - (tiers - 1 - t)).clamp(0.0, 1.0);
      final stocked = (segments * tierFill).round();
      for (var i = 0; i < stocked; i++) {
        final sy = y + 0.06 * _m + i * (length - 0.12 * _m) / segments;
        final seed = i + (x * 71).round() + category * 5 + t * 3;
        _product(
          canvas,
          brush,
          x + width,
          sy,
          (length - 0.12 * _m) / segments - 0.05 * _m,
          base,
          theme.products[seed % theme.products.length],
          category,
          seed,
        );
      }
    }

    // Header sign board above the cabinet.
    brush.box(
      canvas,
      x0: x + 0.20 * _m,
      y0: y + length * 0.20,
      x1: x + 0.28 * _m,
      y1: y + length * 0.80,
      base: top + 0.10 * _m,
      height: 0.34 * _m,
      color: theme.trim,
      topColor: IsoLight.lift(theme.trim, 0.34),
      outline: false,
    );
    brush.box(
      canvas,
      x0: x + 0.28 * _m,
      y0: y + length * 0.24,
      x1: x + 0.31 * _m,
      y1: y + length * 0.76,
      base: top + 0.16 * _m,
      height: 0.20 * _m,
      color: Colors.white.withValues(alpha: 0.9),
      outline: false,
    );
  }

  /// One pack standing on a gondola band at [cx],[cy], [w] deep along the run.
  ///
  /// Shape follows the aisle [category] — bottles in drinks, produce in the
  /// fruit aisle, cartons elsewhere — so a glance at an aisle tells you what it
  /// sells. [seed] adds per-item variation so a run is not a repeating pattern.
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
    final jitter = (seed % 5) * 0.02 * _m;
    switch (category % 4) {
      case 2:
        // Drinks: a slim bottle with a lighter cap.
        brush.box(
          canvas,
          x0: cx - 0.10 * _m,
          y0: cy,
          x1: cx - 0.02 * _m,
          y1: cy + w,
          base: base,
          height: 0.26 * _m + jitter,
          color: color,
          outline: false,
        );
        brush.box(
          canvas,
          x0: cx - 0.08 * _m,
          y0: cy + w * 0.28,
          x1: cx - 0.04 * _m,
          y1: cy + w * 0.72,
          base: base + 0.26 * _m + jitter,
          height: 0.07 * _m,
          color: IsoLight.lift(color, 0.4),
          outline: false,
        );
      case 0:
        // Produce: a low mound in an open tray.
        brush.box(
          canvas,
          x0: cx - 0.12 * _m,
          y0: cy,
          x1: cx - 0.01 * _m,
          y1: cy + w,
          base: base,
          height: 0.08 * _m,
          color: _crateBody,
          outline: false,
        );
        brush.sphere(
          canvas,
          x: cx - 0.065 * _m,
          y: cy + w / 2,
          z: base + 0.12 * _m,
          radius: 0.07 * _m,
          color: color,
        );
      default:
        // Cartons with a label band.
        brush.box(
          canvas,
          x0: cx - 0.11 * _m,
          y0: cy,
          x1: cx - 0.015 * _m,
          y1: cy + w,
          base: base,
          height: 0.23 * _m + jitter,
          color: color,
          outline: false,
        );
        brush.box(
          canvas,
          x0: cx - 0.115 * _m,
          y0: cy,
          x1: cx - 0.095 * _m,
          y1: cy + w,
          base: base + 0.07 * _m,
          height: 0.07 * _m,
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
    brush.castShadow(
      canvas,
      x0: x,
      y0: y0,
      x1: x + _chillerDepth,
      y1: y1,
      height: _chillerHeight,
      opacity: 0.26,
    );
    brush.box(
      canvas,
      x0: x,
      y0: y0,
      x1: x + _chillerDepth,
      y1: y1,
      height: _chillerHeight,
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
    final slots = ((y1 - y0 - 0.20 * _m) / (0.25 * _m)).floor();
    for (var i = 0; i < slots; i++) {
      final sy = y0 + 0.16 * _m + i * 0.25 * _m;
      brush.box(
        canvas,
        x0: x + 0.20 * _m,
        y0: sy,
        x1: x + _chillerDepth - 0.10 * _m,
        y1: sy + 0.18 * _m,
        base: 0.35 * _m,
        height: 0.50 * _m,
        color: drinks[(i + (y0 * 40).round()) % drinks.length],
        outline: false,
      );
    }
    // Glass door on the face turned toward the shop floor.
    brush.panel(
      canvas,
      x0: x + _chillerDepth,
      y0: y0 + 0.12 * _m,
      x1: x + _chillerDepth,
      y1: y1 - 0.12 * _m,
      base: 0.25 * _m,
      top: _chillerHeight - 0.15 * _m,
      color: const Color(0x66CDECF7),
    );
    // Bright frame highlight along the top of the unit.
    brush.box(
      canvas,
      x0: x,
      y0: y0,
      x1: x + 0.09,
      y1: y0 + 0.012,
      base: _chillerHeight,
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
    const length = 2.0 * _m;
    const depth = 0.75 * _m;
    final x = zone.dx - length / 2;
    final y = zone.dy - depth / 2;
    brush.castShadow(
      canvas,
      x0: x,
      y0: y,
      x1: x + length,
      y1: y + depth,
      height: _counterHeight,
      opacity: 0.26,
    );
    brush.box(
      canvas,
      x0: x,
      y0: y,
      x1: x + length,
      y1: y + depth,
      height: _counterHeight,
      color: body,
      topColor: unlocked ? const Color(0xFF6E8A93) : const Color(0xFF8A948F),
    );
    // Bright counter top so the till reads as the shop's focal point.
    brush.box(
      canvas,
      x0: x,
      y0: y,
      x1: x + length,
      y1: y + depth,
      base: _counterHeight,
      height: 0.04 * _m,
      color: const Color(0xFF37C88E),
      outline: false,
    );
    if (!unlocked) return;

    // Register block and its customer-facing screen.
    brush.box(
      canvas,
      x0: x + 0.20 * _m,
      y0: y + 0.14 * _m,
      x1: x + 0.62 * _m,
      y1: y + depth - 0.14 * _m,
      base: _counterHeight + 0.04 * _m,
      height: 0.30 * _m,
      color: const Color(0xFF2C3B44),
      outline: false,
    );
    brush.panel(
      canvas,
      x0: x + 0.62 * _m,
      y0: y + 0.18 * _m,
      x1: x + 0.62 * _m,
      y1: y + depth - 0.18 * _m,
      base: _counterHeight + 0.34 * _m,
      top: _counterHeight + 0.60 * _m,
      color: const Color(0xFF6FE3B4),
    );

    // Belt running the length of the counter, with a few items on it.
    brush.groundQuad(
      canvas,
      x0: x + 0.80 * _m,
      y0: y + 0.12 * _m,
      x1: x + length - 0.18 * _m,
      y1: y + depth - 0.12 * _m,
      color: const Color(0xFF25333A),
      z: _counterHeight + 0.045 * _m,
    );
    const items = [Color(0xFFE0453B), Color(0xFFF2B134), Color(0xFF66C24E)];
    for (var i = 0; i < items.length; i++) {
      brush.box(
        canvas,
        x0: x + 0.95 * _m + i * 0.24 * _m,
        y0: y + 0.26 * _m,
        x1: x + 1.10 * _m + i * 0.24 * _m,
        y1: y + depth - 0.26 * _m,
        base: _counterHeight + 0.05 * _m,
        height: 0.16 * _m,
        color: items[i],
        outline: false,
      );
    }

    // Hanging lane number, the landmark that makes a till findable.
    brush.box(
      canvas,
      x0: x + length * 0.42,
      y0: y + depth * 0.5 - 0.02 * _m,
      x1: x + length * 0.42 + 0.05 * _m,
      y1: y + depth * 0.5 + 0.02 * _m,
      base: _counterHeight + 0.60 * _m,
      height: 0.85 * _m,
      color: const Color(0xFF9FB0A8),
      outline: false,
    );
    brush.box(
      canvas,
      x0: x + length * 0.36,
      y0: y + depth * 0.5 - 0.03 * _m,
      x1: x + length * 0.52,
      y1: y + depth * 0.5 + 0.03 * _m,
      base: _counterHeight + 1.45 * _m,
      height: 0.34 * _m,
      color: const Color(0xFF2A7A5C),
      topColor: _accentGold,
      outline: false,
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
      height: 0.55 * _m,
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
      height: _counterHeight,
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
      base: _counterHeight,
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
        base: _counterHeight,
        height: 0.16 * _m,
        color: const Color(0xFFE8B98A),
        outline: false,
      );
    }
  }

  /// Glazed shopfront at the near edge: two piers, a glass door between them,
  /// a fascia and an entrance mat on the floor.
  ///
  /// Sized like a real shop door — a 2.4 m opening, not the four-metre arch it
  /// used to be, which towered over the shoppers walking through it.
  void _entrance(Canvas canvas, IsoBrush brush, IsoProjection p) {
    const y0 = 0.985;
    const y1 = 1.015;
    const h = 2.40 * _m;
    const pier = 0.55 * _m;

    brush.groundQuad(
      canvas,
      x0: 0.70,
      y0: 0.90,
      x1: 1.02,
      y1: 0.985,
      color: const Color(0x66244A3C),
    );

    brush.castShadow(
      canvas,
      x0: 0.70,
      y0: y0,
      x1: 1.02,
      y1: y1,
      height: h,
      opacity: 0.16,
    );

    // Glazing between the piers.
    brush.box(
      canvas,
      x0: 0.70 + pier,
      y0: y0 + 0.004,
      x1: 1.02 - pier,
      y1: y1 - 0.004,
      height: h - 0.10 * _m,
      color: const Color(0xFFBFE0E6),
      topColor: const Color(0xFFDDF0F4),
      outline: false,
    );
    // Door split.
    final mid = (0.70 + 1.02) / 2;
    brush.box(
      canvas,
      x0: mid - 0.004,
      y0: y0,
      x1: mid + 0.004,
      y1: y1,
      height: h - 0.10 * _m,
      color: const Color(0xFF2A7A5C),
      outline: false,
    );

    for (final x in const [0.70, 1.02 - 0.55 / 12]) {
      brush.box(
        canvas,
        x0: x,
        y0: y0,
        x1: x + pier,
        y1: y1,
        height: h,
        // Lighter than the fixtures behind it: the nearest object should frame
        // the shop, not out-contrast the till it is standing in front of.
        color: const Color(0xFF7FA394),
        topColor: const Color(0xFF9DBDAF),
        outline: false,
      );
    }

    // Fascia across the top, carrying the shop's accent.
    brush.box(
      canvas,
      x0: 0.70,
      y0: y0,
      x1: 1.02,
      y1: y1,
      base: h,
      height: 0.42 * _m,
      color: const Color(0xFF4E7F6C),
      topColor: _accentGold,
    );
    brush.box(
      canvas,
      x0: 0.76,
      y0: y0 - 0.004,
      x1: 0.98,
      y1: y0,
      base: h + 0.06 * _m,
      height: 0.26 * _m,
      color: _accentGold,
      outline: false,
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

    // Derived from the same metric scale as the fixtures: a 1.7 m person is
    // about 3.4 shoulder-widths tall, so one unit here is that shoulder width.
    // Sizing figures and furniture off one constant is what keeps a 1.45 m
    // gondola reading as chest height rather than towering over the shopper.
    final u = _personHeight * p.unitHeight / 3.4;
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
    // Vignette tinted with the shell colour, and strong enough at the frame
    // edges that the board sinks into the dark chrome above and below it
    // instead of ending on a hard bright line.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          rect.center,
          rect.longestSide * 0.60,
          [const Color(0x000D2A21), const Color(0x330D2A21), const Color(0x990D2A21)],
          [0.42, 0.78, 1],
        ),
    );
    // Contact shadow along the top edge, where the HUD overhangs the world.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height * 0.10),
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topCenter,
          Offset(rect.center.dx, size.height * 0.10),
          [const Color(0x7307190F), const Color(0x0007190F)],
        ),
    );
  }

  @override
  bool shouldRepaint(covariant IsoMarketPainter oldDelegate) => true;
}

/// Actionable shopper moods surfaced as a bubble above the figure.
enum _Mood { vip, paying, impatient }
