import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'iso_projection.dart';

/// Fixed key-light direction for the whole scene.
///
/// Every solid is shaded from the same imaginary lamp above and to the screen
/// left. Consistency here is what makes separately drawn props read as one
/// space rather than a collage.
abstract final class IsoLight {
  /// Multiplier applied to the upward-facing surface.
  static const top = 1.0;

  /// Screen-left face — the one turned toward the lamp.
  static const left = 0.78;

  /// Screen-right face — turned away, so it carries the darkest tone.
  static const right = 0.55;

  static Color shade(Color base, double factor) {
    if (factor >= 1) return base;
    return Color.lerp(const Color(0xFF0A1D16), base, factor)!;
  }

  static Color lift(Color base, double amount) =>
      Color.lerp(base, const Color(0xFFFFFFFF), amount)!;
}

/// A drawing scheduled against a depth key so props can be sorted back-to-front.
class IsoDrawCall {
  const IsoDrawCall(this.depth, this.paint);

  final double depth;
  final void Function(Canvas canvas) paint;
}

/// Primitive solids in isometric space.
///
/// Everything the market is built from — shelving, counters, crates, signage —
/// composes out of these, so the whole store can be drawn without a single
/// bitmap asset.
class IsoBrush {
  IsoBrush(this.projection);

  final IsoProjection projection;
  final Paint _fill = Paint()..isAntiAlias = true;

  /// Soft contact shadow on the ground plane.
  void groundShadow(
    Canvas canvas, {
    required double x,
    required double y,
    required double radiusX,
    required double radiusY,
    double opacity = 0.30,
  }) {
    final centre = projection.project(x, y);
    // Footprints are isometric, so the shadow has to be much flatter than it is
    // wide or it reads as a glowing ring rather than something touching down.
    final rect = Rect.fromCenter(
      center: centre.translate(0, radiusY * projection.tileHeight * 0.10),
      width: radiusX * projection.tileWidth * 0.85,
      height: radiusY * projection.tileHeight * 0.55,
    );
    _fill
      ..shader = null
      ..maskFilter = null
      ..color = const Color(0xFF06201A).withValues(alpha: opacity * 0.34);
    canvas.drawOval(rect.inflate(rect.height * 0.22), _fill);
    _fill.color = const Color(0xFF06201A).withValues(alpha: opacity);
    canvas.drawOval(rect, _fill);
  }

  /// An axis-aligned box standing on the ground plane.
  ///
  /// [x0]/[y0] is the far corner and [x1]/[y1] the near one; [height] is in
  /// world-z units. Only the three camera-facing surfaces are emitted.
  /// Directional cast shadow for a box footprint.
  ///
  /// A soft ellipse under a prop says "this floats"; a sheared quad thrown away
  /// from a fixed key light says "this is lit". One consistent light direction
  /// across every fixture is the cheapest way to make a procedural scene read
  /// as a single physical space.
  void castShadow(
    Canvas canvas, {
    required double x0,
    required double y0,
    required double x1,
    required double y1,
    required double height,
    double opacity = 0.30,
  }) {
    // Key light comes from over the camera's left shoulder, so shadows fall
    // down-right in world space, lengthening with the caster's height.
    final throwX = height * 0.55;
    final throwY = height * 0.28;
    final corners = <Offset>[
      Offset(x0, y0),
      Offset(x1, y0),
      Offset(x1, y1),
      Offset(x0, y1),
    ];
    final path = Path();
    for (var i = 0; i < corners.length; i++) {
      final c = corners[i];
      // The far edge of the footprint stays put; the near edge is pushed out,
      // which is what shears the quad rather than just translating it.
      final lean = (c.dx - x0) / math.max(0.0001, x1 - x0);
      final at = projection.project(
        c.dx + throwX * (0.35 + 0.65 * lean),
        c.dy + throwY,
      );
      if (i == 0) {
        path.moveTo(at.dx, at.dy);
      } else {
        path.lineTo(at.dx, at.dy);
      }
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF0A2419).withValues(alpha: opacity)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          math.max(1.5, 3 * projection.scale),
        ),
    );
  }

  void box(
    Canvas canvas, {
    required double x0,
    required double y0,
    required double x1,
    required double y1,
    required double height,
    required Color color,
    double base = 0,
    Color? topColor,
    bool outline = true,
  }) {
    final top = base + height;

    // Screen-left face lies on the x = x1 plane; screen-right on y = y1.
    final leftFace = Path()
      ..moveTo(projection.project(x1, y0, base).dx, projection.project(x1, y0, base).dy)
      ..lineTo(projection.project(x1, y1, base).dx, projection.project(x1, y1, base).dy)
      ..lineTo(projection.project(x1, y1, top).dx, projection.project(x1, y1, top).dy)
      ..lineTo(projection.project(x1, y0, top).dx, projection.project(x1, y0, top).dy)
      ..close();

    final rightFace = Path()
      ..moveTo(projection.project(x0, y1, base).dx, projection.project(x0, y1, base).dy)
      ..lineTo(projection.project(x1, y1, base).dx, projection.project(x1, y1, base).dy)
      ..lineTo(projection.project(x1, y1, top).dx, projection.project(x1, y1, top).dy)
      ..lineTo(projection.project(x0, y1, top).dx, projection.project(x0, y1, top).dy)
      ..close();

    final topFace = Path()
      ..moveTo(projection.project(x0, y0, top).dx, projection.project(x0, y0, top).dy)
      ..lineTo(projection.project(x1, y0, top).dx, projection.project(x1, y0, top).dy)
      ..lineTo(projection.project(x1, y1, top).dx, projection.project(x1, y1, top).dy)
      ..lineTo(projection.project(x0, y1, top).dx, projection.project(x0, y1, top).dy)
      ..close();

    _fill
      ..shader = null
      ..style = PaintingStyle.fill;

    _fill.color = IsoLight.shade(color, IsoLight.left);
    canvas.drawPath(leftFace, _fill);

    _fill.color = IsoLight.shade(color, IsoLight.right);
    canvas.drawPath(rightFace, _fill);

    _fill.color = topColor ?? IsoLight.lift(color, 0.12);
    canvas.drawPath(topFace, _fill);

    if (outline) {
      _fill
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.6, 0.9 * projection.scale)
        ..color = IsoLight.shade(color, 0.34).withValues(alpha: 0.55);
      canvas.drawPath(topFace, _fill);
      canvas.drawPath(leftFace, _fill);
      canvas.drawPath(rightFace, _fill);
      _fill.style = PaintingStyle.fill;
    }
  }

  /// Flat quad laid directly on the ground — floor decals, rugs, lane markings.
  void groundQuad(
    Canvas canvas, {
    required double x0,
    required double y0,
    required double x1,
    required double y1,
    required Color color,
    double z = 0.001,
  }) {
    final path = Path()
      ..moveTo(projection.project(x0, y0, z).dx, projection.project(x0, y0, z).dy)
      ..lineTo(projection.project(x1, y0, z).dx, projection.project(x1, y0, z).dy)
      ..lineTo(projection.project(x1, y1, z).dx, projection.project(x1, y1, z).dy)
      ..lineTo(projection.project(x0, y1, z).dx, projection.project(x0, y1, z).dy)
      ..close();
    _fill
      ..shader = null
      ..style = PaintingStyle.fill
      ..color = color;
    canvas.drawPath(path, _fill);
  }

  /// Upright billboard quad, used for glass fronts and signage faces.
  void panel(
    Canvas canvas, {
    required double x0,
    required double y0,
    required double x1,
    required double y1,
    required double base,
    required double top,
    required Color color,
  }) {
    final path = Path()
      ..moveTo(projection.project(x0, y0, base).dx, projection.project(x0, y0, base).dy)
      ..lineTo(projection.project(x1, y1, base).dx, projection.project(x1, y1, base).dy)
      ..lineTo(projection.project(x1, y1, top).dx, projection.project(x1, y1, top).dy)
      ..lineTo(projection.project(x0, y0, top).dx, projection.project(x0, y0, top).dy)
      ..close();
    _fill
      ..shader = null
      ..style = PaintingStyle.fill
      ..color = color;
    canvas.drawPath(path, _fill);
  }

  /// Rounded upright capsule used for character bodies and heads.
  void capsule(
    Canvas canvas, {
    required double x,
    required double y,
    required double base,
    required double height,
    required double radius,
    required Color color,
    double squash = 1,
  }) {
    final bottom = projection.project(x, y, base);
    final top = projection.project(x, y, base + height);
    final width = radius * projection.tileWidth;
    final rect = Rect.fromLTRB(
      bottom.dx - width / 2,
      top.dy,
      bottom.dx + width / 2,
      bottom.dy,
    );
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.elliptical(width / 2, width / 2 * squash),
    );
    _fill
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          IsoLight.lift(color, 0.24),
          color,
          IsoLight.shade(color, 0.62),
        ],
        stops: const [0, 0.45, 1],
      ).createShader(rect);
    canvas.drawRRect(rrect, _fill);
    _fill.shader = null;
  }

  void sphere(
    Canvas canvas, {
    required double x,
    required double y,
    required double z,
    required double radius,
    required Color color,
  }) {
    final centre = projection.project(x, y, z);
    final r = radius * projection.tileWidth / 2;
    final rect = Rect.fromCircle(center: centre, radius: r);
    _fill
      ..style = PaintingStyle.fill
      ..shader = RadialGradient(
        center: const Alignment(-0.35, -0.45),
        radius: 0.95,
        colors: [
          IsoLight.lift(color, 0.34),
          color,
          IsoLight.shade(color, 0.60),
        ],
        stops: const [0, 0.52, 1],
      ).createShader(rect);
    canvas.drawCircle(centre, r, _fill);
    _fill.shader = null;
  }
}
