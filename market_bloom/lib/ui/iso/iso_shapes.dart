import 'dart:math' as math;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'iso_projection.dart';

/// Fixed key-light direction for the whole scene.
///
/// Every solid is shaded from the same imaginary lamp above and to the screen
/// left. Consistency here is what makes separately drawn props read as one
/// space rather than a collage.
abstract final class IsoLight {
  /// Multiplier applied to the upward-facing surface.
  static const top = 1.0;

  /// Screen-left face — the one turned toward the key light.
  static const left = 0.86;

  /// Screen-right face — turned away, carrying the cool fill.
  static const right = 0.66;

  /// Warm key, cool fill. Shading by darkening toward one flat near-black gave
  /// every surface the same grey cast, which is what made the scene read as
  /// flat-shaded geometry. Real stylised lighting tints as it darkens: shadowed
  /// faces go cool and blue, lit faces go warm. That single change is most of
  /// the difference between "diagram" and "lit miniature".
  static const _shadowTint = Color(0xFF17384F);
  static const _keyTint = Color(0xFFFFE9C4);

  static Color shade(Color base, double factor) {
    if (factor >= 1) return base;
    // Darken and cool together.
    final darkened = Color.lerp(base, const Color(0xFF0C1F19), 1 - factor)!;
    return Color.lerp(darkened, _shadowTint, (1 - factor) * 0.42)!;
  }

  /// Lit companion of [base], warmed rather than simply whitened.
  static Color lift(Color base, double amount) {
    final lightened = Color.lerp(base, const Color(0xFFFFFFFF), amount)!;
    return Color.lerp(lightened, _keyTint, amount * 0.35)!;
  }

  /// Cool bounce used on the underside of overhangs and inside recesses.
  static Color bounce(Color base) => Color.lerp(base, _shadowTint, 0.30)!;
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

  /// Rounds the corners of a closed screen-space polygon.
  ///
  /// Hard-edged polygons are the single strongest "this is a diagram" cue.
  /// Softening every corner by a fixed screen radius turns the same geometry
  /// into moulded forms, which is the shape language stylised mobile art uses
  /// for readability at small sizes.
  Path _rounded(List<Offset> points, double radius) {
    if (radius <= 0.4 || points.length < 3) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final p in points.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      return path..close();
    }
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final prev = points[(i - 1 + points.length) % points.length];
      final cur = points[i];
      final next = points[(i + 1) % points.length];

      Offset toward(Offset from, Offset to) {
        final d = to - from;
        final len = d.distance;
        if (len < 0.001) return from;
        // Never round more than a third of the shorter edge, or thin fixtures
        // collapse into lozenges.
        final r = math.min(radius, len / 3);
        return from + d * (r / len);
      }

      final entry = toward(cur, prev);
      final exit = toward(cur, next);
      if (i == 0) {
        path.moveTo(entry.dx, entry.dy);
      } else {
        path.lineTo(entry.dx, entry.dy);
      }
      path.quadraticBezierTo(cur.dx, cur.dy, exit.dx, exit.dy);
    }
    return path..close();
  }

  /// A lit solid: three rounded faces, each gradient-shaded, with a contact
  /// shadow beneath and a highlight along its lit top edge.
  ///
  /// Replaces the flat three-tone box every fixture used to be built from.
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
    final p = projection;
    // Radius scales with the object so small props round proportionally.
    final span = math.min((x1 - x0).abs(), (y1 - y0).abs()) * p.tileWidth;
    final radius = math.min(6.0 * p.scale, math.max(1.2, span * 0.16));

    Offset at(double x, double y, double z) => p.project(x, y, z);

    final leftFace = _rounded([
      at(x1, y0, base),
      at(x1, y1, base),
      at(x1, y1, top),
      at(x1, y0, top),
    ], radius);
    final rightFace = _rounded([
      at(x0, y1, base),
      at(x1, y1, base),
      at(x1, y1, top),
      at(x0, y1, top),
    ], radius);
    final topFace = _rounded([
      at(x0, y0, top),
      at(x1, y0, top),
      at(x1, y1, top),
      at(x0, y1, top),
    ], radius);

    // The union of the three visible faces, as a single hexagon: top vertex,
    // round the lit side, along the base, and back up the shadow side.
    //
    // Used twice. First as an under-fill, because each face rounds its corners
    // independently and the two side faces therefore curve away from each
    // other at the vertical corner they share, leaving a hairline of
    // background showing through the middle of a solid object. Second as the
    // contour stroke below.
    final solid = height > 0.004;
    final silhouette = solid
        ? _rounded([
            at(x0, y0, top),
            at(x1, y0, top),
            at(x1, y0, base),
            at(x1, y1, base),
            at(x0, y1, base),
            at(x0, y1, top),
          ], radius)
        : null;

    _fill
      ..style = PaintingStyle.fill
      ..shader = null;

    // Ambient occlusion where the solid meets whatever it stands on. Cheap,
    // and it is what stops props looking pasted onto the floor.
    if (solid) {
      final footprint = _rounded([
        at(x0, y0, base),
        at(x1, y0, base),
        at(x1, y1, base),
        at(x0, y1, base),
      ], radius);
      canvas.drawPath(
        footprint,
        Paint()
          ..color = const Color(0xFF0A2A22).withValues(alpha: 0.30)
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            math.max(1.6, 4 * p.scale),
          ),
      );
      // Seam guard: the darker of the two side tones, so any gap left by the
      // independently rounded faces reads as shadow rather than as a hole.
      canvas.drawPath(
        silhouette!,
        Paint()
          ..isAntiAlias = true
          ..color = IsoLight.shade(color, IsoLight.right),
      );
    }

    // Side faces carry a vertical gradient: darker at the floor, lighter
    // toward the lit top edge.
    void shadeFace(Path face, double factor) {
      final bounds = face.getBounds();
      canvas.drawPath(
        face,
        Paint()
          ..isAntiAlias = true
          ..shader = ui.Gradient.linear(
            Offset(bounds.center.dx, bounds.bottom),
            Offset(bounds.center.dx, bounds.top),
            [
              IsoLight.shade(color, factor * 0.82),
              IsoLight.shade(color, factor),
              IsoLight.lift(IsoLight.shade(color, factor), 0.10),
            ],
            const [0, 0.62, 1],
          ),
      );
    }

    shadeFace(leftFace, IsoLight.left);
    shadeFace(rightFace, IsoLight.right);

    final crown = topColor ?? IsoLight.lift(color, 0.16);
    final topBounds = topFace.getBounds();
    canvas.drawPath(
      topFace,
      Paint()
        ..isAntiAlias = true
        ..shader = ui.Gradient.linear(
          topBounds.topCenter,
          topBounds.bottomCenter,
          [IsoLight.lift(crown, 0.14), crown],
        ),
    );

    // Contour. A tinted dark edge around the whole solid — tinted rather than
    // black, so it stays inside the scene's palette — is what stops a bright
    // cabinet dissolving into a bright floor. It is the single strongest
    // readability cue stylised mobile 2.5D has.
    //
    // Gated on screen size rather than on [outline], so it needs no call-site
    // changes: every large fixture picks a contour up automatically, while the
    // hundreds of small packs facing off a gondola stay clean and cheap.
    final screenSpan = math.max(
      (x1 - x0).abs() * p.tileWidth,
      height * p.unitHeight,
    );
    final contoured = solid && screenSpan > 7 * p.scale;
    if (contoured) {
      canvas.drawPath(
        silhouette!,
        Paint()
          ..isAntiAlias = true
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = math.max(0.9, 1.1 * p.scale)
          ..color = IsoLight.shade(color, 0.30).withValues(alpha: 0.38),
      );
    }

    // Specular edge along the lit rim, which is what sells a moulded surface,
    // and a cool rim down the shadow side to answer it. A warm highlight alone
    // only says "this face is bright"; the pair says "this is a solid sitting
    // in light", and it separates a fixture from whatever is behind it even
    // where the two are the same value.
    if (outline && contoured) {
      canvas.drawLine(
        at(x0, y0, top),
        at(x1, y0, top),
        Paint()
          ..isAntiAlias = true
          ..strokeCap = StrokeCap.round
          ..strokeWidth = math.max(0.8, 1.3 * p.scale)
          ..color = Colors.white.withValues(alpha: 0.34),
      );
      final coolRim = Paint()
        ..isAntiAlias = true
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(0.7, 1.0 * p.scale)
        ..color = const Color(0xFF8FC7E8).withValues(alpha: 0.30);
      canvas.drawLine(at(x0, y0, top), at(x0, y1, top), coolRim);
      canvas.drawLine(at(x0, y1, top), at(x0, y1, base), coolRim);
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
