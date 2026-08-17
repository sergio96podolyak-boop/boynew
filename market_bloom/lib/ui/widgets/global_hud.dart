import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../game/game_controller.dart';
import '../../game/game_models.dart';
import '../../services/app_localizations.dart';
import '../../services/app_settings.dart';
import '../theme/po_system.dart';
import '../theme/pomarket_design.dart';

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
    this.floating = false,
  });

  final GameController game;
  final AppSettings settings;

  /// Set on the market board, where the board itself should own the height.
  final bool compactMode;

  /// Renders as transparent corner pods over the world instead of a solid bar.
  ///
  /// The market screen uses this so the board runs edge to edge behind the
  /// chrome; the management screens keep the bar, where a solid header is the
  /// right frame for a scrolling list.
  final bool floating;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final reducedMotion =
        settings.reducedMotion || MediaQuery.disableAnimationsOf(context);

    if (floating) {
      return _FloatingHud(
        game: game,
        loc: loc,
        reducedMotion: reducedMotion,
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(boxShadow: PoElevate.e3),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [PoColor.chromeLift, PoColor.chrome],
          ),
        ),
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

/// Corner-pod HUD for the world screen.
///
/// No bar, no background: a brand pod on the leading edge, the wallet cluster
/// on the trailing edge, and a compact shift pod beneath. The board runs behind
/// all of it, which is the point — the previous full-width bar plus event strip
/// plus objective strip consumed roughly a quarter of the screen before the
/// player saw any of the shop.
class _FloatingHud extends StatelessWidget {
  const _FloatingHud({
    required this.game,
    required this.loc,
    required this.reducedMotion,
  });

  final GameController game;
  final AppLocalizations loc;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Shift timing as an edge hairline rather than its own pod: constant
        // monitoring info belongs on a screen edge, and one fewer persistent
        // overlay is one fewer thing competing with the world.
        AnimatedBuilder(
          animation: game,
          builder: (context, _) => _ShiftEdge(game: game, loc: loc),
        ),
        _FloatingHudBody(
          game: game,
          loc: loc,
          reducedMotion: reducedMotion,
        ),
      ],
    );
  }
}

class _FloatingHudBody extends StatelessWidget {
  const _FloatingHudBody({
    required this.game,
    required this.loc,
    required this.reducedMotion,
  });

  final GameController game;
  final AppLocalizations loc;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 430;
    return IgnorePointer(
      ignoring: false,
      child: SafeArea(
        bottom: false,
        child: AnimatedBuilder(
          animation: game,
          builder: (context, _) => Semantics(
            container: true,
            label:
                'PoMarket, ${loc.levelLabel} ${game.storeLevel}, ${game.coins} ${loc.coinsShort}, ${game.gems} ${loc.gemsShort}',
            child: Padding(
              padding: EdgeInsetsDirectional.fromSTEB(10, 8, _cloudBadgeLane, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _BrandPod(subtitle: loc.yourMiniMarket, compact: compact),
                      Expanded(
                        child: Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerEnd,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (game.shelfStock < 3) ...[
                                  _LowStockFlag(message: loc.lowStock),
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
                                  icon: Icons.monetization_on_rounded,
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Brand identity as a single glass pod rather than a logo floating on a bar.
class _BrandPod extends StatelessWidget {
  const _BrandPod({required this.subtitle, required this.compact});

  final String subtitle;
  final bool compact;

  @override
  Widget build(BuildContext context) => PoPod(
    padding: const EdgeInsetsDirectional.fromSTEB(5, 5, 12, 5),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _BrandMark(compact: compact),
        const SizedBox(width: 9),
        SizedBox(width: 86, child: _BrandWordmark(subtitle: subtitle)),
      ],
    ),
  );
}

/// Shift phase and timing, drawn as a hairline across the very top edge.
///
/// Costs no layout space, is edge-anchored where constant-monitoring readouts
/// belong, and its colour alone communicates the phase — so the shift no longer
/// needs a pod of its own competing with the brand and the wallet.
class _ShiftEdge extends StatelessWidget {
  const _ShiftEdge({required this.game, required this.loc});

  final GameController game;
  final AppLocalizations loc;

  @override
  Widget build(BuildContext context) {
    final style = _phaseStyle(game.shiftPhase, loc);
    return Semantics(
      label: '${style.label}, ${loc.shift} ${game.shiftNumber}',
      child: SizedBox(
        height: 4,
        child: Row(
          children: [
            Expanded(
              flex: (game.shiftProgress.clamp(0.0, 1.0) * 1000).round(),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      PoColor.lighten(style.face, 0.30),
                      style.face,
                    ],
                  ),
                  boxShadow: PoElevate.glow(style.face, strength: 0.5),
                ),
              ),
            ),
            Expanded(
              flex: 1000 - (game.shiftProgress.clamp(0.0, 1.0) * 1000).round(),
              child: const ColoredBox(color: Color(0x33FFFFFF)),
            ),
          ],
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
  Widget build(BuildContext context) =>
      const CustomPaint(painter: _HudGlowPainter());
}

class _HudGlowPainter extends CustomPainter {
  const _HudGlowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // Two light pools: a brand bloom behind the wordmark and a cool one behind
    // the wallet, so the dark shell has depth instead of being a flat slab.
    for (final (align, radius, color, alpha)
        in <(Alignment, double, Color, double)>[
          (const Alignment(-0.95, -0.9), 1.2, PoColor.primaryFace, 0.22),
          (const Alignment(0.95, 1.0), 0.9, PoColor.secondaryFace, 0.14),
        ]) {
      canvas.drawRect(
        rect,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = RadialGradient(
            center: align,
            radius: radius,
            colors: [
              color.withValues(alpha: alpha),
              Colors.transparent,
            ],
          ).createShader(rect),
      );
    }
    // Lit top edge — the standard cue that a dark bar is a raised surface.
    canvas.drawLine(
      Offset(0, 0.5),
      Offset(size.width, 0.5),
      Paint()
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.10),
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
        style: PoText.h3.copyWith(
          letterSpacing: 0.9,
          height: 1,
          color: PoColor.onChrome,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: PoText.caption.copyWith(height: 1, color: PoColor.onChromeMuted),
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
                    color: PoColor.deepen(PoColor.primaryFace, 0.62),
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
          colors: [PoColor.lighten(face, 0.44), PoColor.deepen(face, 0.10)],
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
      ..color = const Color(0xFF07190F).withValues(alpha: 0.42);
    canvas.drawCircle(centre, radius, track);

    // Outer rim keeps the medallion crisp against the white chrome.
    canvas.drawCircle(
      centre,
      radius + stroke / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withValues(alpha: 0.55),
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
class _WalletCapsule extends StatefulWidget {
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
  State<_WalletCapsule> createState() => _WalletCapsuleState();
}

class _WalletCapsuleState extends State<_WalletCapsule> {
  int? _previous;
  int _gain = 0;
  int _burst = 0;

  @override
  void didUpdateWidget(covariant _WalletCapsule oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = _previous ?? oldWidget.value;
    _previous = widget.value;
    if (widget.reducedMotion || widget.value <= before) return;
    setState(() {
      _gain = widget.value - before;
      _burst++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final compact = widget.compact;
    final face = widget.face;
    final icon = widget.icon;
    final value = widget.value;
    final semanticLabel = widget.semanticLabel;
    final reducedMotion = widget.reducedMotion;
    final height = compact ? 32.0 : 36.0;
    final medallion = height - 8;
    final capsule = _PopOnChange(
      value: value,
      reducedMotion: reducedMotion,
      child: Semantics(
        label: '$semanticLabel $value',
        child: Container(
          height: height,
          padding: EdgeInsetsDirectional.fromSTEB(4, 4, compact ? 11 : 13, 4),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [PoColor.lighten(face, 0.20), PoColor.deepen(face, 0.30)],
            ),
            borderRadius: BorderRadius.circular(PoRadius.pill),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.45),
              width: 1.4,
            ),
            boxShadow: [
              BoxShadow(
                color: PoColor.chromeDeep.withValues(alpha: 0.5),
                blurRadius: 7,
                offset: const Offset(0, 3),
              ),
              ...PoElevate.glow(face, strength: 0.55),
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
                    colors: [Colors.white, Color(0xFFE7EEEA)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: PoColor.deepen(face, 0.55).withValues(alpha: 0.45),
                      blurRadius: 3,
                      offset: const Offset(0, 1.5),
                    ),
                  ],
                ),
                child: Icon(
                  icon,
                  size: medallion * 0.62,
                  color: PoColor.deepen(face, 0.30),
                ),
              ),
              SizedBox(width: compact ? 7 : 8),
              PoValue(
                poShort(value),
                size: compact ? 15 : 16.5,
                rim: PoColor.deepen(face, 0.62),
              ),
            ],
          ),
        ),
      ),
    );

    if (_gain <= 0) return capsule;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        capsule,
        Positioned(
          top: -20,
          child: PoFloatingNumber(
            key: ValueKey('gain-$_burst'),
            text: '+${poShort(_gain)}',
            face: face,
            icon: icon,
            onDone: () {
              if (mounted) setState(() => _gain = 0);
            },
          ),
        ),
      ],
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
              PoPod(
                padding: const EdgeInsetsDirectional.fromSTEB(9, 5, 11, 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(style.icon, size: 13, color: style.face),
                    const SizedBox(width: 5),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 132),
                      child: Text(
                        '${style.label} · ${game.shiftNumber}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PoText.caption.copyWith(
                          color: PoColor.onChrome,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: PoSpace.sm),
            ],
            Expanded(
              child: PoGauge(
                value: game.shiftProgress,
                face: style.face,
                height: compact ? 11 : 13,
                segments: 10,
                onChrome: true,
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
