import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../widgets/premium_ui.dart';

/// Advanced visual language for PoMarket.
///
/// The management screens keep their bright cream surfaces, but everything the
/// player touches during a shift now uses the depth vocabulary in this file:
/// extruded controls, medallion currency chips and lit surfaces. The goal is
/// the tactile "candy" feel that top-grossing tycoon titles rely on, without
/// pulling in a heavier rendering stack.

/// Deep backdrop ramp. Bright surfaces read as premium when they float on a
/// rich field instead of another pale grey.
abstract final class PoDepthColors {
  static const abyss = Color(0xFF04211A);
  static const deepSea = Color(0xFF073024);
  static const forest = Color(0xFF0A4433);
  static const canopy = Color(0xFF10614A);

  /// Translucent card fills for use on top of the dark ramp.
  static const glass = Color(0x1FFFFFFF);
  static const glassStrong = Color(0x2EFFFFFF);
  static const hairline = Color(0x24FFFFFF);
}

/// Paired light/dark stops so every accent can be extruded consistently.
abstract final class PoAccent {
  static const goldFace = Color(0xFFFFD264);
  static const goldDeep = Color(0xFFE08A0B);

  static const mintFace = Color(0xFF56E8A9);
  static const mintDeep = Color(0xFF0E9C67);

  static const gemFace = Color(0xFFBEA0FF);
  static const gemDeep = Color(0xFF6B3FE0);

  static const coralFace = Color(0xFFFF8095);
  static const coralDeep = Color(0xFFD82F4F);

  static const blueFace = Color(0xFF7FC0FF);
  static const blueDeep = Color(0xFF1E6FD0);

  /// Returns the darker companion used for bevels and button edges.
  static Color deepen(Color face) => Color.lerp(face, Colors.black, 0.34)!;

  /// Returns the lighter companion used for top highlights.
  static Color lighten(Color face) => Color.lerp(face, Colors.white, 0.42)!;
}

abstract final class PoDepth {
  /// Tight contact shadow plus a wide ambient one. Two layers is what makes an
  /// element look like it is resting on the surface rather than pasted onto it.
  static List<BoxShadow> resting({double strength = 1}) => [
    BoxShadow(
      color: PoDepthColors.abyss.withValues(alpha: 0.16 * strength),
      blurRadius: 3 * strength,
      offset: Offset(0, 1.5 * strength),
    ),
    BoxShadow(
      color: PoDepthColors.abyss.withValues(alpha: 0.13 * strength),
      blurRadius: 18 * strength,
      offset: Offset(0, 8 * strength),
    ),
  ];

  /// Coloured bloom used under primary actions and currency medallions.
  static List<BoxShadow> glow(Color color, {double strength = 1}) => [
    BoxShadow(
      color: color.withValues(alpha: 0.42 * strength),
      blurRadius: 16 * strength,
      offset: Offset(0, 5 * strength),
    ),
  ];
}

/// Compact currency formatting.
///
/// Tycoon economies reach seven figures quickly; rendering the raw integer both
/// overflows the HUD and is harder to read at a glance than `2.4M`.
String poShortNumber(num value) {
  final negative = value < 0;
  final magnitude = value.abs();
  final (scaled, suffix) = switch (magnitude) {
    >= 1000000000 => (magnitude / 1000000000, 'B'),
    >= 1000000 => (magnitude / 1000000, 'M'),
    >= 10000 => (magnitude / 1000, 'K'),
    _ => (magnitude.toDouble(), ''),
  };
  final String body;
  if (suffix.isEmpty) {
    body = magnitude.round().toString();
  } else {
    // One decimal below 100 keeps precision where the player still notices it.
    body = scaled < 100
        ? scaled.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '')
        : scaled.round().toString();
  }
  return '${negative ? '-' : ''}$body$suffix';
}

abstract final class PoNumerals {
  /// Currency and score readouts. Tabular-ish spacing keeps digits from
  /// jittering as values tick up.
  static const display = TextStyle(
    fontSize: 19,
    fontWeight: FontWeight.w900,
    height: 1,
    letterSpacing: -0.4,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const chip = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w900,
    height: 1,
    letterSpacing: -0.2,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const caption = TextStyle(
    fontSize: 9,
    fontWeight: FontWeight.w800,
    height: 1,
    letterSpacing: 0.6,
  );
}

/// A pressable control with real thickness.
///
/// The face sits on a solid darker edge; pressing collapses the edge so the
/// button physically sinks. This is the single strongest "game feel" signal a
/// flat UI can gain.
class PoButton extends StatefulWidget {
  const PoButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.face = PoAccent.mintFace,
    this.foreground,
    this.padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    this.radius = 18,
    this.thickness = 5,
    this.expand = false,
    this.semanticLabel,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final Color face;

  /// Defaults to whichever of ink/white reads better on [face]. Bright candy
  /// faces need dark labels; white on mint is close to unreadable.
  final Color? foreground;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double thickness;
  final bool expand;
  final String? semanticLabel;

  @override
  State<PoButton> createState() => _PoButtonState();
}

class _PoButtonState extends State<PoButton> {
  bool _down = false;

  bool get _enabled => widget.onPressed != null;

  void _setDown(bool value) {
    if (_down == value || !_enabled) return;
    setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final edge = ApplyDisabled.color(
      PoAccent.deepen(widget.face),
      enabled: _enabled,
    );
    final face = ApplyDisabled.color(widget.face, enabled: _enabled);
    // Measure the lit top of the gradient, which is what the label sits on.
    final foreground = ApplyDisabled.color(
      widget.foreground ??
          (PoAccent.lighten(widget.face).computeLuminance() > 0.45
              ? PoMarketPalette.ink
              : Colors.white),
      enabled: _enabled,
    );
    final sink = _down ? widget.thickness : 0.0;
    final duration = reducedMotion
        ? Duration.zero
        : const Duration(milliseconds: 70);

    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        onTapDown: (_) => _setDown(true),
        onTapUp: (_) => _setDown(false),
        onTapCancel: () => _setDown(false),
        onTap: widget.onPressed,
        behavior: HitTestBehavior.opaque,
        child: AnimatedPadding(
          duration: duration,
          curve: Curves.easeOut,
          padding: EdgeInsets.only(top: sink, bottom: widget.thickness - sink),
          child: DecoratedBox(
            // The edge is a solid block peeking out below the face.
            decoration: BoxDecoration(
              color: edge,
              borderRadius: BorderRadius.circular(widget.radius),
              boxShadow: _enabled && !_down
                  ? PoDepth.resting(strength: 0.8)
                  : null,
            ),
            child: Container(
              width: widget.expand ? double.infinity : null,
              margin: EdgeInsets.only(bottom: widget.thickness),
              padding: widget.padding,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [PoAccent.lighten(face), face],
                ),
                borderRadius: BorderRadius.circular(widget.radius),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.34),
                  width: 1,
                ),
              ),
              child: DefaultTextStyle.merge(
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: foreground,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                  letterSpacing: 0.2,
                ),
                child: IconTheme.merge(
                  data: IconThemeData(color: foreground, size: 18),
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

abstract final class ApplyDisabled {
  static Color color(Color base, {required bool enabled}) => enabled
      ? base
      : Color.lerp(base, PoMarketPalette.muted, 0.62)!.withValues(alpha: 0.75);
}

/// Currency readout: gradient medallion + tabular value on a glass pill.
class PoCurrencyChip extends StatelessWidget {
  const PoCurrencyChip({
    super.key,
    required this.icon,
    required this.value,
    required this.face,
    this.label,
    this.progress,
    this.compact = false,
    this.semanticLabel,
  });

  final IconData icon;
  final String value;
  final Color face;
  final String? label;

  /// Optional 0..1 track drawn under the value (used by level and shift).
  final double? progress;
  final bool compact;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final medallion = compact ? 22.0 : 26.0;
    return Semantics(
      label: semanticLabel ?? '${label ?? ''} $value'.trim(),
      child: Container(
        padding: EdgeInsetsDirectional.fromSTEB(4, 4, compact ? 9 : 11, 4),
        decoration: BoxDecoration(
          color: PoDepthColors.glass,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: face.withValues(alpha: 0.42)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: medallion,
              height: medallion,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [PoAccent.lighten(face), PoAccent.deepen(face)],
                ),
                boxShadow: PoDepth.glow(face, strength: 0.55),
              ),
              child: Icon(
                icon,
                size: compact ? 13 : 15,
                color: Colors.white.withValues(alpha: 0.96),
              ),
            ),
            SizedBox(width: compact ? 6 : 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (label case final text?) ...[
                  Text(
                    text.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PoNumerals.caption.copyWith(
                      color: Colors.white.withValues(alpha: 0.62),
                    ),
                  ),
                  const SizedBox(height: 3),
                ],
                Text(
                  value,
                  textDirection: TextDirection.ltr,
                  style: PoNumerals.chip.copyWith(
                    color: Colors.white,
                    fontSize: compact ? 13 : 14,
                  ),
                ),
                if (progress case final ratio?) ...[
                  const SizedBox(height: 4),
                  PoTrack(value: ratio, face: face, width: compact ? 26 : 34),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Slim glossy progress track.
class PoTrack extends StatelessWidget {
  const PoTrack({
    super.key,
    required this.value,
    required this.face,
    this.width,
    this.height = 4,
  });

  final double value;
  final Color face;
  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.28)),
            ),
            FractionallySizedBox(
              widthFactor: value.clamp(0.0, 1.0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [PoAccent.lighten(face), face],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cinematic grade for the market board.
///
/// The board art is flat and evenly lit, which reads as a spreadsheet. A warm
/// centre pool plus corner falloff gives it a focal point and depth for free —
/// no changes to the sprite pipeline.
class WorldLightOverlay extends StatelessWidget {
  const WorldLightOverlay({super.key, this.warmth = 1, this.clipper});

  /// Scales the whole effect; 0 disables it.
  final double warmth;

  /// Restricts the grade to the painted board. Callers supply this so the
  /// overlay stays aligned with whatever geometry the board painter used,
  /// rather than duplicating its inset and corner radius here.
  final RRect Function(Size size)? clipper;

  @override
  Widget build(BuildContext context) {
    if (warmth <= 0) return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(
        painter: _WorldLightPainter(warmth: warmth, clipper: clipper),
        size: Size.infinite,
      ),
    );
  }
}

class _WorldLightPainter extends CustomPainter {
  const _WorldLightPainter({required this.warmth, this.clipper});

  final double warmth;
  final RRect Function(Size size)? clipper;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = clipper?.call(size);
    if (bounds != null) {
      canvas.save();
      canvas.clipRRect(bounds);
    }
    final rect = bounds?.outerRect ?? (Offset.zero & size);

    // Warm key light pooling slightly above centre, where the player works.
    final key = Paint()
      ..blendMode = BlendMode.plus
      ..shader = RadialGradient(
        center: const Alignment(0, -0.18),
        radius: 0.80,
        colors: [
          const Color(0xFFFFCE86).withValues(alpha: 0.22 * warmth),
          const Color(0xFFFFCE86).withValues(alpha: 0.06 * warmth),
          Colors.transparent,
        ],
        stops: const [0, 0.55, 1],
      ).createShader(rect);
    canvas.drawRect(rect, key);

    // Saturation lift. The board art is pale, so multiplying a warm tone back
    // over it restores the depth the flat sprites lose at small sizes.
    final grade = Paint()
      ..blendMode = BlendMode.multiply
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.lerp(
            Colors.white,
            const Color(0xFF8FB0A0),
            0.30 * warmth,
          )!,
          Color.lerp(
            Colors.white,
            const Color(0xFFE0B87E),
            0.26 * warmth,
          )!,
        ],
      ).createShader(rect);
    canvas.drawRect(rect, grade);

    // Corner falloff. Kept cool so it reads as shade, not dirt.
    final vignette = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 0.88,
        colors: [
          Colors.transparent,
          const Color(0xFF04211A).withValues(alpha: 0.18 * warmth),
          const Color(0xFF04211A).withValues(alpha: 0.52 * warmth),
        ],
        stops: const [0.48, 0.78, 1],
      ).createShader(rect);
    canvas.drawRect(rect, vignette);

    if (bounds != null) canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WorldLightPainter oldDelegate) =>
      oldDelegate.warmth != warmth || oldDelegate.clipper != clipper;
}

/// A value that pops, rises and fades — the classic "+$12" feedback.
class PoFloatingNumber extends StatefulWidget {
  const PoFloatingNumber({
    super.key,
    required this.text,
    this.face = PoAccent.goldFace,
    this.icon,
    this.onDone,
  });

  final String text;
  final Color face;
  final IconData? icon;
  final VoidCallback? onDone;

  @override
  State<PoFloatingNumber> createState() => _PoFloatingNumberState();
}

class _PoFloatingNumberState extends State<PoFloatingNumber>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    _controller.forward().whenCompleteOrCancel(() {
      if (mounted) widget.onDone?.call();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = _controller.value;
          // Overshoot on entry, then drift up and fade out.
          final pop = t < 0.18
              ? Curves.easeOutBack.transform(t / 0.18)
              : 1.0 - (t - 0.18) * 0.12;
          final rise = Curves.easeOutCubic.transform(t) * -34;
          final fade = t < 0.7 ? 1.0 : 1.0 - (t - 0.7) / 0.3;
          return Transform.translate(
            offset: Offset(0, rise),
            child: Transform.scale(
              scale: pop.clamp(0.0, 1.4),
              child: Opacity(opacity: fade.clamp(0.0, 1.0), child: child),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                PoAccent.lighten(widget.face),
                PoAccent.deepen(widget.face),
              ],
            ),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
            boxShadow: PoDepth.glow(widget.face, strength: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon case final icon?) ...[
                Icon(icon, size: 13, color: Colors.white),
                const SizedBox(width: 4),
              ],
              Text(
                widget.text,
                textDirection: TextDirection.ltr,
                style: PoNumerals.chip.copyWith(color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Radiating rays used behind reward icons in celebration moments.
class PoRayBurst extends StatefulWidget {
  const PoRayBurst({
    super.key,
    this.color = PoAccent.goldFace,
    this.rays = 12,
    this.child,
  });

  final Color color;
  final int rays;
  final Widget? child;

  @override
  State<PoRayBurst> createState() => _PoRayBurstState();
}

class _PoRayBurstState extends State<PoRayBurst>
    with SingleTickerProviderStateMixin {
  // Eager for the same reason as the HUD's pop animation: under reduced motion
  // build() skips the controller entirely, and a lazy initialiser would then
  // fire inside dispose() against a deactivated element.
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: still
                ? CustomPaint(
                    painter: _RayPainter(
                      color: widget.color,
                      rays: widget.rays,
                      turn: 0,
                    ),
                  )
                : AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) => CustomPaint(
                      painter: _RayPainter(
                        color: widget.color,
                        rays: widget.rays,
                        turn: _controller.value,
                      ),
                    ),
                  ),
          ),
        ),
        ?widget.child,
      ],
    );
  }
}

class _RayPainter extends CustomPainter {
  const _RayPainter({
    required this.color,
    required this.rays,
    required this.turn,
  });

  final Color color;
  final int rays;
  final double turn;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final radius = size.longestSide * 0.72;
    final sweep = math.pi * 2 / rays;
    final paint = Paint()..color = color.withValues(alpha: 0.16);
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.rotate(turn * math.pi * 2);
    for (var i = 0; i < rays; i++) {
      final start = sweep * i;
      final path = Path()
        ..moveTo(0, 0)
        ..arcTo(
          Rect.fromCircle(center: Offset.zero, radius: radius),
          start,
          sweep * 0.45,
          false,
        )
        ..close();
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RayPainter oldDelegate) =>
      oldDelegate.turn != turn || oldDelegate.color != color;
}
