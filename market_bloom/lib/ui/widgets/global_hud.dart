import 'package:flutter/material.dart';

import '../../game/game_controller.dart';
import '../../game/game_models.dart';
import '../../services/app_localizations.dart';
import '../../services/app_settings.dart';

/// The single app-wide status header.
///
/// It participates in normal layout instead of being painted over the whole
/// screen, so it never creates a modal-looking dim layer or covers gameplay.
class GlobalHud extends StatelessWidget {
  const GlobalHud({super.key, required this.game, required this.settings});

  final GameController game;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final reducedMotion =
        settings.reducedMotion || MediaQuery.disableAnimationsOf(context);

    return Material(
      color: const Color(0xFF063D2C),
      elevation: 5,
      shadowColor: const Color(0x55315F4A),
      child: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 360;
            final compactBrand =
                constraints.maxWidth >= 430 && constraints.maxWidth < 500;
            final tight = constraints.maxWidth < 430;
            final showSubtitle = constraints.maxWidth >= 350 && !compactBrand;

            return AnimatedBuilder(
              animation: game,
              builder: (context, _) {
                return Semantics(
                  container: true,
                  label:
                      'PoMarket, ${loc.levelLabel} ${game.storeLevel}, ${game.coins} ${loc.coinsShort}, ${game.gems} ${loc.gemsShort}',
                  child: SizedBox(
                    height: compact ? 58 : 66,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 8 : 12,
                        vertical: compact ? 7 : 8,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Container(
                                  width: compactBrand ? 34 : 40,
                                  height: compactBrand ? 34 : 40,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF38B879),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    Icons.storefront_rounded,
                                    color: Colors.white,
                                    size: compactBrand ? 20 : 23,
                                  ),
                                ),
                                if (!compactBrand) ...[
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'POMARKET',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 0.5,
                                            height: 1,
                                          ),
                                        ),
                                        if (showSubtitle) ...[
                                          const SizedBox(height: 3),
                                          Text(
                                            loc.yourMiniMarket,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Color(0xFFC9E9D9),
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              height: 1,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          _HudPill(
                            icon: Icons.trending_up_rounded,
                            label: 'L${game.storeLevel}',
                            value: '${(game.levelProgress * 100).round()}%',
                            color: const Color(0xFF38B879),
                            compact: compact,
                            reducedMotion: reducedMotion,
                          ),
                          SizedBox(width: compact ? 4 : 6),
                          _HudPill(
                            icon: Icons.monetization_on_rounded,
                            label: loc.coinsShort,
                            value: '${game.coins}',
                            color: const Color(0xFFF6A623),
                            compact: compact,
                            reducedMotion: reducedMotion,
                          ),
                          SizedBox(width: compact ? 4 : 6),
                          _HudPill(
                            icon: Icons.diamond_rounded,
                            label: loc.gemsShort,
                            value: '${game.gems}',
                            color: const Color(0xFF9B7AE6),
                            compact: compact,
                            reducedMotion: reducedMotion,
                          ),
                          SizedBox(width: compact ? 3 : 6),
                          _ShiftPill(game: game, loc: loc, compact: tight),
                          if (game.shelfStock < 3) ...[
                            SizedBox(width: compact ? 3 : 5),
                            Tooltip(
                              message: loc.lowStock,
                              child: const Icon(
                                Icons.warning_amber_rounded,
                                color: Color(0xFFFF7C8F),
                                size: 18,
                              ),
                            ),
                          ],
                        ],
                      ),
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

class _HudPill extends StatelessWidget {
  const _HudPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.compact,
    required this.reducedMotion,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool compact;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    final valueText = Text(
      value,
      key: ValueKey(value),
      style: TextStyle(
        color: Colors.white,
        fontSize: compact ? 10 : 12,
        fontWeight: FontWeight.w900,
        height: 1,
      ),
    );

    return Container(
      constraints: BoxConstraints(minWidth: compact ? 42 : 48),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 5 : 7,
        vertical: compact ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 12 : 14, color: color),
          const SizedBox(width: 3),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  color: const Color(0xFFC9E9D9),
                  fontSize: compact ? 7 : 8,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
              const SizedBox(height: 2),
              Directionality(
                textDirection: TextDirection.ltr,
                child: reducedMotion
                    ? valueText
                    : AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: valueText,
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ShiftPill extends StatelessWidget {
  const _ShiftPill({
    required this.game,
    required this.loc,
    required this.compact,
  });

  final GameController game;
  final AppLocalizations loc;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final phase = switch (game.shiftPhase) {
      ShiftPhase.preparation => loc.shiftPreparation,
      ShiftPhase.open => loc.shiftOpen,
      ShiftPhase.rush => loc.rushHour,
      ShiftPhase.closing => loc.shiftClosing,
      ShiftPhase.summary => loc.shiftSummary,
    };
    final rush = game.rushActive;
    if (compact) {
      return Semantics(
        label: '${loc.shift} ${game.shiftNumber}, $phase',
        child: Tooltip(
          message: phase,
          child: Icon(
            rush ? Icons.local_fire_department_rounded : Icons.schedule_rounded,
            color: rush ? const Color(0xFFFF8FA0) : const Color(0xFF65D7A5),
            size: 18,
          ),
        ),
      );
    }
    return Semantics(
      label: '${loc.shift} ${game.shiftNumber}, $phase',
      child: Container(
        constraints: BoxConstraints(minWidth: compact ? 40 : 54),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 4 : 7,
          vertical: compact ? 4 : 5,
        ),
        decoration: BoxDecoration(
          color: (rush ? const Color(0xFFE85D75) : const Color(0xFF2B9C73))
              .withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: rush ? const Color(0xFFFF8FA0) : const Color(0xFF65D7A5),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${loc.shift} ${game.shiftNumber}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: compact ? 7 : 8,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 3),
            SizedBox(
              width: compact ? 32 : 40,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: game.shiftProgress,
                  minHeight: compact ? 3 : 4,
                  color: rush
                      ? const Color(0xFFFF8FA0)
                      : const Color(0xFF65D7A5),
                  backgroundColor: Colors.white.withValues(alpha: 0.18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
