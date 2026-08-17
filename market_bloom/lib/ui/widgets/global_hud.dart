import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../game/game_controller.dart';
import '../../game/game_models.dart';
import '../../services/app_localizations.dart';
import '../../services/app_settings.dart';
import '../theme/po_system.dart';

/// Persistent HUD for the playable market and the management screens.
///
/// Composition follows the convention every successful tycoon title converges
/// on, because it matches how players read the screen: identity and progression
/// on the leading edge, spendable resources on the trailing edge, and a single
/// time-based rail underneath. Nothing scrolls and nothing is hidden — the
/// previous version put five near-identical white pills in a horizontal
/// scroller, so the wallet could be off-screen exactly when it mattered.
///
/// Width is kept clear at the trailing edge for the floating cloud-save badge
/// (a 30px chip inset by 8 in `CloudSaveStatusLayer`).
const double _cloudBadgeLane = 42;

class GlobalHud extends StatelessWidget {
  const GlobalHud({
    super.key,
    required this.game,
    required this.settings,
    this.compactMode = false,
  });

  final GameController game;
  final AppSettings settings;

  /// Set on the market board, where the board itself should own the height.
  final bool compactMode;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final reducedMotion =
        settings.reducedMotion || MediaQuery.disableAnimationsOf(context);

    return DecoratedBox(
      decoration: BoxDecoration(boxShadow: PoElevate.e3),
      child: ColoredBox(
        color: PoColor.chrome,
        child: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final compact = compactMode || width < 430;
              // The phase tag is the only element that drops as the bar
              // narrows. The wordmark keeps a fixed lane and the wallet — the
              // thing a player checks most — is the single flexible child, so
              // it scales a few percent instead of overflowing or scrolling.
              final showPhaseTag = width >= 348;
              return AnimatedBuilder(
                animation: game,
                builder: (context, _) {
                  return Semantics(
                    container: true,
                    label:
                        'PoMarket, ${loc.levelLabel} ${game.storeLevel}, ${game.coins} ${loc.coinsShort}, ${game.gems} ${loc.gemsShort}',
                    child: Stack(
                      children: [
                        const Positioned.fill(child: _HudBackdrop()),
                        // The chrome stays full-bleed; its contents share the
                        // page's measure so the brand, wallet and shift rail
                        // line up with the content column at desktop widths
                        // instead of hugging the window edges.
                        _HudMeasure(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Padding(
                                padding: EdgeInsetsDirectional.fromSTEB(
                                  compact ? 10 : 14,
                                  compact ? 7 : 9,
                                  _cloudBadgeLane,
                                  compact ? 6 : 7,
                                ),
                                child: Row(
                                  children: [
                                    _BrandMark(compact: compact),
                                    SizedBox(width: compact ? 8 : 10),
                                    SizedBox(
                                      width: 90,
                                      child: _BrandWordmark(
                                        subtitle: loc.yourMiniMarket,
                                      ),
                                    ),
                                    // The wallet cluster owns all remaining
                                    // width and right-aligns inside it; on the
                                    // narrowest phones it scales down a few
                                    // percent rather than overflowing.
                                    Expanded(
                                      child: Align(
                                        alignment:
                                            AlignmentDirectional.centerEnd,
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          alignment:
                                              AlignmentDirectional.centerEnd,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (game.shelfStock < 3) ...[
                                                _LowStockFlag(
                                                  message: loc.lowStock,
                                                ),
                                                const SizedBox(width: 7),
                                              ],
                                              _LevelMedallion(
                                                level: game.storeLevel,
                                                progress: game.levelProgress,
                                                label: loc.levelLabel,
                                                compact: compact,
                                                reducedMotion: reducedMotion,
                                              ),
                                              const SizedBox(width: 7),
                                              _WalletCapsule(
                                                icon: Icons
                                                    .monetization_on_rounded,
                                                value: game.coins,
                                                face: PoColor.goldFace,
                                                compact: compact,
                                                semanticLabel: loc.coinsShort,
                                                reducedMotion: reducedMotion,
                                              ),
                                              const SizedBox(width: 7),
                                              _WalletCapsule(
                                                icon: Icons.diamond_rounded,
                                                value: game.gems,
                                                face: PoColor.accentFace,
                                                compact: compact,
                                                semanticLabel: loc.gemsShort,
                                                reducedMotion: reducedMotion,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _ShiftStrip(
                                game: game,
                                loc: loc,
                                showTag: showPhaseTag,
                                compact: compact,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Caps and centres HUD contents on wide windows.
class _HudMeasure extends StatelessWidget {
  const _HudMeasure({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: PoLayout.content),
      child: child,
    ),
  );
}

class _HudBackdrop extends StatelessWidget {
  const _HudBackdrop();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFFFFF), Color(0xFFF3F8F4)],
      ),
    ),
    child: CustomPaint(painter: _HudGlowPainter()),
  );
}

class _HudGlowPainter extends CustomPainter {
  const _HudGlowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // A whisper of brand tint behind the wordmark. Normal blend, not additive:
    // on light chrome an additive bloom just clips to white.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.9, -0.6),
          radius: 1.15,
          colors: [
            PoColor.primaryFace.withValues(alpha: 0.20),
            Colors.transparent,
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Store logo. Squircle medallion with gloss, matching the icon language used
/// throughout the management screens.
class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) => PoIconBadge(
    icon: Icons.storefront_rounded,
    size: compact ? 34 : 38,
    radius: compact ? 11 : 12,
  );
}

class _BrandWordmark extends StatelessWidget {
  const _BrandWordmark({required this.subtitle});

  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        'POMARKET',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: PoText.h3.copyWith(letterSpacing: 0.7, height: 1),
      ),
      const SizedBox(height: 2),
      Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: PoText.caption.copyWith(height: 1),
      ),
    ],
  );
}

/// Level readout as a ring-progress medallion.
///
/// A circular fill is legible at a glance in a way a 4px linear track inside a
/// pill never was, and it gives the leading edge of the wallet cluster a
/// distinct silhouette so level and currency are not read as the same thing.
class _LevelMedallion extends StatelessWidget {
  const _LevelMedallion({
    required this.level,
    required this.progress,
    required this.label,
    required this.compact,
    required this.reducedMotion,
  });

  final int level;
  final double progress;
  final String label;
  final bool compact;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 34.0 : 38.0;
    return _PopOnChange(
      value: level,
      reducedMotion: reducedMotion,
      child: Tooltip(
        message: '$label $level',
        child: Semantics(
          label: '$label $level',
          child: SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              painter: _RingPainter(
                progress: progress.clamp(0.0, 1.0),
                face: PoColor.primaryFace,
              ),
              child: Center(
                child: Text(
                  '$level',
                  textDirection: TextDirection.ltr,
                  style: PoText.numeralSm.copyWith(
                    fontSize: compact ? 13.5 : 15,
                    color: PoColor.deepen(PoColor.primaryFace, 0.58),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.progress, required this.face});

  final double progress;
  final Color face;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final stroke = size.shortestSide * 0.13;
    final radius = (size.shortestSide - stroke) / 2;

    // Saturated body: at HUD scale a pale disc beside two vivid currency
    // capsules read as a disabled control rather than the player's level.
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [PoColor.lighten(face, 0.52), PoColor.lighten(face, 0.14)],
        ).createShader(Offset.zero & size),
    );
    // Gloss cap, matching the icon medallions elsewhere.
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius * 0.74),
      math.pi * 1.08,
      math.pi * 0.84,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.34
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.42),
    );

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = PoColor.deepen(face, 0.46).withValues(alpha: 0.28);
    canvas.drawCircle(centre, radius, track);

    // Outer rim keeps the medallion crisp against the white chrome.
    canvas.drawCircle(
      centre,
      radius + stroke / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: 0.9),
    );

    if (progress <= 0) return;
    final fill = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: math.pi * 1.5,
        colors: [PoColor.lighten(face, 0.28), PoColor.deepen(face, 0.20)],
      ).createShader(Rect.fromCircle(center: centre, radius: radius));
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      fill,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.face != face;
}

/// Currency capsule.
///
/// Saturated body with white numerals, rather than the previous white pill on
/// white chrome — currency has to be the highest-contrast element in the bar or
/// players stop trusting it.
class _WalletCapsule extends StatelessWidget {
  const _WalletCapsule({
    required this.icon,
    required this.value,
    required this.face,
    required this.compact,
    required this.semanticLabel,
    required this.reducedMotion,
  });

  final IconData icon;
  final int value;
  final Color face;
  final bool compact;
  final String semanticLabel;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    final height = compact ? 32.0 : 36.0;
    final medallion = height - 8;
    return _PopOnChange(
      value: value,
      reducedMotion: reducedMotion,
      child: Semantics(
        label: '$semanticLabel $value',
        child: Container(
          height: height,
          padding: EdgeInsetsDirectional.fromSTEB(4, 4, compact ? 10 : 12, 4),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [PoColor.lighten(face, 0.14), PoColor.deepen(face, 0.26)],
            ),
            borderRadius: BorderRadius.circular(PoRadius.pill),
            border: Border.all(color: Colors.white.withValues(alpha: 0.45)),
            boxShadow: [
              ...PoElevate.e1,
              ...PoElevate.glow(face, strength: 0.42),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // White medallion: reads as a minted coin and keeps the glyph
              // legible against the saturated body.
              Container(
                width: medallion,
                height: medallion,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.white, Color(0xFFEDF2EE)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: PoColor.deepen(face, 0.5).withValues(alpha: 0.32),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Icon(
                  icon,
                  size: medallion * 0.62,
                  color: PoColor.deepen(face, 0.24),
                ),
              ),
              SizedBox(width: compact ? 6 : 7),
              Text(
                poShort(value),
                textDirection: TextDirection.ltr,
                style: PoText.numeralSm.copyWith(
                  fontSize: compact ? 13 : 14,
                  color: Colors.white,
                  shadows: [
                    Shadow(
                      color: PoColor.deepen(face, 0.62).withValues(alpha: 0.55),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Scales its child briefly whenever the tracked value changes, so earnings and
/// spends register even when the player is watching the board.
class _PopOnChange extends StatefulWidget {
  const _PopOnChange({
    required this.value,
    required this.reducedMotion,
    required this.child,
  });

  final int value;
  final bool reducedMotion;
  final Widget child;

  @override
  State<_PopOnChange> createState() => _PopOnChangeState();
}

class _PopOnChangeState extends State<_PopOnChange>
    with SingleTickerProviderStateMixin {
  // Constructed eagerly: build() returns early under reduced motion and never
  // touches the controller, so a lazy `late final` would first run its
  // initialiser inside dispose(), where looking up TickerMode on the
  // already-deactivated element throws.
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      value: 1,
    );
  }

  @override
  void didUpdateWidget(covariant _PopOnChange oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && !widget.reducedMotion) {
      _controller
        ..value = 0
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.reducedMotion) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeOutBack.transform(_controller.value);
        return Transform.scale(scale: 0.86 + 0.14 * t, child: child);
      },
      child: widget.child,
    );
  }
}

/// Phase identity: label, accent and glyph for a point in the shift cycle.
({String label, Color face, IconData icon}) _phaseStyle(
  ShiftPhase phase,
  AppLocalizations loc,
) => switch (phase) {
  ShiftPhase.preparation => (
    label: loc.shiftPreparation,
    face: PoColor.goldFace,
    icon: Icons.build_circle_rounded,
  ),
  ShiftPhase.open => (
    label: loc.shiftOpen,
    face: PoColor.primaryFace,
    icon: Icons.lock_open_rounded,
  ),
  ShiftPhase.rush => (
    label: loc.rushHour,
    face: PoColor.danger,
    icon: Icons.local_fire_department_rounded,
  ),
  ShiftPhase.closing => (
    label: loc.shiftClosing,
    face: PoColor.goldFace,
    icon: Icons.schedule_rounded,
  ),
  ShiftPhase.summary => (
    label: loc.shiftSummary,
    face: PoColor.accentFace,
    icon: Icons.assessment_rounded,
  ),
};

/// Shift timing strip.
///
/// Replaces the 6px hairline rail with a labelled row: phase tag, then a real
/// inset meter. The old rail overlaid an 8px caption on a coloured bar, which
/// was unreadable at any width and left the phase unidentifiable on phones.
class _ShiftStrip extends StatelessWidget {
  const _ShiftStrip({
    required this.game,
    required this.loc,
    required this.showTag,
    required this.compact,
  });

  final GameController game;
  final AppLocalizations loc;
  final bool showTag;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final style = _phaseStyle(game.shiftPhase, loc);
    return Semantics(
      label: '${style.label}, ${loc.shift} ${game.shiftNumber}',
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          compact ? 10 : 14,
          0,
          compact ? 10 : 14,
          compact ? 7 : 9,
        ),
        child: Row(
          children: [
            if (showTag) ...[
              PoTag(
                label: '${style.label} · ${game.shiftNumber}',
                icon: style.icon,
                face: style.face,
                tone: PoTagTone.soft,
                dense: true,
                maxWidth: 168,
              ),
              const SizedBox(width: PoSpace.sm),
            ],
            Expanded(
              child: PoMeter(
                value: game.shiftProgress,
                face: style.face,
                height: 8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Attention flag raised when the shelves are nearly empty.
class _LowStockFlag extends StatelessWidget {
  const _LowStockFlag({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: message,
    child: _Pulse(
      child: PoIconBadge(
        // Lightened before extrusion: PoIconBadge shades its own bottom stop,
        // so feeding it the base danger red produced a muddy maroon disc.
        icon: Icons.priority_high_rounded,
        face: PoColor.lighten(PoColor.danger, 0.30),
        size: 30,
        radius: PoRadius.pill,
      ),
    ),
  );
}

/// Slow breathing scale. Used only for the low-stock flag: one moving element
/// in the HUD draws the eye, a dozen would be noise.
class _Pulse extends StatefulWidget {
  const _Pulse({required this.child});

  final Widget child;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Transform.scale(
        scale: 1 + 0.07 * Curves.easeInOut.transform(_controller.value),
        child: child,
      ),
      child: widget.child,
    );
  }
}
