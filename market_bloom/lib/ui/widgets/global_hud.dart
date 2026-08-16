import 'package:flutter/material.dart';

import '../../game/game_controller.dart';
import '../../game/game_models.dart';
import '../../services/app_localizations.dart';
import '../../services/app_settings.dart';
import '../theme/pomarket_design.dart';

/// Persistent HUD for the playable market and management screens.
///
/// Layout is deliberately fixed rather than scrollable: the previous version
/// packed five near-identical pills into a horizontal scroll view, which
/// overflowed on phones and hid the save indicator. Now the level sits on the
/// left, wallet on the right, and shift state renders as a full-width progress
/// rail along the bottom edge — informative at zero extra height.
/// Width kept clear at the trailing edge for the floating cloud-save badge
/// (30px chip inset by 8 in [CloudSaveStatusLayer]).
const double _cloudBadgeLane = 44;

class GlobalHud extends StatelessWidget {
  const GlobalHud({
    super.key,
    required this.game,
    required this.settings,
    this.compactMode = false,
  });

  final GameController game;
  final AppSettings settings;
  final bool compactMode;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final reducedMotion =
        settings.reducedMotion || MediaQuery.disableAnimationsOf(context);

    return Material(
      color: PoDepthColors.deepSea,
      elevation: 10,
      shadowColor: PoDepthColors.abyss.withValues(alpha: 0.55),
      child: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final compact = compactMode || width < 430;
            final showPhaseLabel = width >= 380;
            // Everything below is fixed-width; the brand wordmark is the only
            // flexible element, so these thresholds decide what fits before the
            // wordmark absorbs whatever is left.
            final showBrandText = width >= 380;
            final showPhaseBadge = width >= 400;
            return AnimatedBuilder(
              animation: game,
              builder: (context, _) {
                return Semantics(
                  container: true,
                  label:
                      'PoMarket, ${loc.levelLabel} ${game.storeLevel}, ${game.coins} ${loc.coinsShort}, ${game.gems} ${loc.gemsShort}',
                  child: SizedBox(
                    height: compact ? 58 : 66,
                    child: Stack(
                      children: [
                        const Positioned.fill(child: _HudBackdrop()),
                        Padding(
                          padding: EdgeInsetsDirectional.fromSTEB(
                            compact ? 9 : 13,
                            compact ? 6 : 8,
                            // CloudSaveStatusLayer floats a 30px badge over the
                            // top-end corner of the whole app. Reserving its
                            // lane here stops it landing on the gem chip and
                            // makes it read as part of the HUD.
                            _cloudBadgeLane,
                            // Room for the shift rail pinned to the bottom.
                            compact ? 9 : 11,
                          ),
                          child: Row(
                            children: [
                              _BrandMark(compact: compact),
                              SizedBox(width: compact ? 6 : 9),
                              // Fixed width so the metric cluster below is the
                              // single flexible child and owns all the slack.
                              if (showBrandText) ...[
                                SizedBox(
                                  width: 92,
                                  child: _BrandWordmark(
                                    subtitle: loc.yourMiniMarket,
                                  ),
                                ),
                                SizedBox(width: compact ? 6 : 9),
                              ],
                              _LevelChip(
                                game: game,
                                loc: loc,
                                compact: compact,
                                reducedMotion: reducedMotion,
                              ),
                              // Takes every remaining pixel and right-aligns
                              // inside it. On the narrowest phones the cluster
                              // scales down a few percent instead of
                              // overflowing the bar.
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
                                          SizedBox(width: compact ? 5 : 8),
                                          _LowStockFlag(message: loc.lowStock),
                                        ],
                                        if (showPhaseBadge) ...[
                                          SizedBox(width: compact ? 5 : 8),
                                          _PhaseBadge(game: game, loc: loc),
                                        ],
                                        SizedBox(width: compact ? 5 : 8),
                                        _WalletChip(
                                          icon: Icons.monetization_on_rounded,
                                          value: game.coins,
                                          face: PoAccent.goldFace,
                                          compact: compact,
                                          semanticLabel: loc.coinsShort,
                                          reducedMotion: reducedMotion,
                                        ),
                                        SizedBox(width: compact ? 5 : 8),
                                        _WalletChip(
                                          icon: Icons.diamond_rounded,
                                          value: game.gems,
                                          face: PoAccent.gemFace,
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
                        PositionedDirectional(
                          start: 0,
                          end: 0,
                          bottom: 0,
                          child: _ShiftRail(
                            game: game,
                            loc: loc,
                            showLabel: showPhaseLabel,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _HudBackdrop extends StatelessWidget {
  const _HudBackdrop();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [PoDepthColors.canopy, PoDepthColors.abyss],
          stops: [0, 0.85],
        ),
      ),
      child: CustomPaint(painter: _HudGlowPainter()),
    );
  }
}

class _HudGlowPainter extends CustomPainter {
  const _HudGlowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // A single soft bloom behind the brand keeps the bar from reading as a
    // flat block without adding noise behind the numbers.
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          center: const Alignment(-0.85, -0.5),
          radius: 1.1,
          colors: [
            PoAccent.mintFace.withValues(alpha: 0.16),
            Colors.transparent,
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 32.0 : 38.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF6DF0BA), Color(0xFF11A26D)],
        ),
        borderRadius: BorderRadius.circular(compact ? 11 : 13),
        border: Border.all(color: Colors.white.withValues(alpha: 0.42)),
        boxShadow: PoDepth.glow(PoAccent.mintFace, strength: 0.7),
      ),
      child: Icon(
        Icons.storefront_rounded,
        color: PoDepthColors.abyss,
        size: compact ? 18 : 21,
      ),
    );
  }
}

/// Brand wordmark. Shrinks and ellipsizes so the metrics beside it always win
/// the available width.
class _BrandWordmark extends StatelessWidget {
  const _BrandWordmark({required this.subtitle});

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'POMARKET',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.6,
            height: 1,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.66),
            fontSize: 9,
            fontWeight: FontWeight.w600,
            height: 1,
          ),
        ),
      ],
    );
  }
}

/// Level readout with an inline progress track toward the next unlock.
class _LevelChip extends StatelessWidget {
  const _LevelChip({
    required this.game,
    required this.loc,
    required this.compact,
    required this.reducedMotion,
  });

  final GameController game;
  final AppLocalizations loc;
  final bool compact;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    return _PopOnChange(
      value: game.storeLevel,
      reducedMotion: reducedMotion,
      child: PoCurrencyChip(
        icon: Icons.stars_rounded,
        value: '${game.storeLevel}',
        label: compact ? null : loc.levelLabel,
        face: PoAccent.mintFace,
        progress: game.levelProgress,
        compact: compact,
        semanticLabel: '${loc.levelLabel} ${game.storeLevel}',
      ),
    );
  }
}

class _WalletChip extends StatelessWidget {
  const _WalletChip({
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
    return _PopOnChange(
      value: value,
      reducedMotion: reducedMotion,
      child: PoCurrencyChip(
        icon: icon,
        value: poShortNumber(value),
        face: face,
        compact: compact,
        semanticLabel: '$semanticLabel $value',
      ),
    );
  }
}

/// Scales its child briefly whenever the tracked value changes, so earnings
/// and spends register even when the player is looking at the market board.
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

/// Phase, colour and icon for the current point in the shift cycle.
({String label, Color face, IconData icon}) _phaseStyle(
  ShiftPhase phase,
  AppLocalizations loc,
) => switch (phase) {
  ShiftPhase.preparation => (
    label: loc.shiftPreparation,
    face: PoAccent.goldFace,
    icon: Icons.build_circle_rounded,
  ),
  ShiftPhase.open => (
    label: loc.shiftOpen,
    face: PoAccent.mintFace,
    icon: Icons.lock_open_rounded,
  ),
  ShiftPhase.rush => (
    label: loc.rushHour,
    face: PoAccent.coralFace,
    icon: Icons.local_fire_department_rounded,
  ),
  ShiftPhase.closing => (
    label: loc.shiftClosing,
    face: PoAccent.goldFace,
    icon: Icons.schedule_rounded,
  ),
  ShiftPhase.summary => (
    label: loc.shiftSummary,
    face: PoAccent.gemFace,
    icon: Icons.assessment_rounded,
  ),
};

/// Compact phase marker. The rail below carries the timing; this carries the
/// identity, so it stays readable even on the narrowest phones.
class _PhaseBadge extends StatelessWidget {
  const _PhaseBadge({required this.game, required this.loc});

  final GameController game;
  final AppLocalizations loc;

  @override
  Widget build(BuildContext context) {
    final style = _phaseStyle(game.shiftPhase, loc);
    return Tooltip(
      message: '${style.label} · ${loc.shift} ${game.shiftNumber}',
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              PoAccent.lighten(style.face),
              PoAccent.deepen(style.face),
            ],
          ),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: Colors.white.withValues(alpha: 0.36)),
          boxShadow: PoDepth.glow(style.face, strength: 0.55),
        ),
        child: Icon(style.icon, color: Colors.white, size: 16),
      ),
    );
  }
}

/// Full-width shift timing rail pinned to the bottom edge of the HUD.
///
/// Deliberately text-free at phone widths: a 7px caption inside a 9px bar was
/// unreadable. The colour comes from the phase badge above it, so the rail only
/// has to answer "how far through are we".
class _ShiftRail extends StatelessWidget {
  const _ShiftRail({
    required this.game,
    required this.loc,
    required this.showLabel,
  });

  final GameController game;
  final AppLocalizations loc;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final style = _phaseStyle(game.shiftPhase, loc);
    return Semantics(
      label: '${style.label}, ${loc.shift} ${game.shiftNumber}',
      child: SizedBox(
        height: showLabel ? 13 : 6,
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: PoDepthColors.abyss.withValues(alpha: 0.6),
              ),
            ),
            Positioned.fill(
              child: FractionallySizedBox(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: game.shiftProgress.clamp(0.0, 1.0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [PoAccent.lighten(style.face), style.face],
                    ),
                    boxShadow: PoDepth.glow(style.face, strength: 0.45),
                  ),
                ),
              ),
            ),
            if (showLabel)
              PositionedDirectional(
                start: 13,
                top: 0,
                bottom: 0,
                child: Align(
                  child: Text(
                    '${style.label.toUpperCase()} · ${loc.shift} ${game.shiftNumber}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PoNumerals.caption.copyWith(
                      color: Colors.white,
                      fontSize: 8,
                      shadows: [
                        Shadow(
                          color: PoDepthColors.abyss.withValues(alpha: 0.95),
                          blurRadius: 3,
                        ),
                      ],
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

class _LowStockFlag extends StatelessWidget {
  const _LowStockFlag({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: message,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [PoAccent.coralFace, PoAccent.coralDeep],
          ),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
          boxShadow: PoDepth.glow(PoAccent.coralFace, strength: 0.7),
        ),
        child: const Icon(
          Icons.priority_high_rounded,
          color: Colors.white,
          size: 17,
        ),
      ),
    );
  }
}
