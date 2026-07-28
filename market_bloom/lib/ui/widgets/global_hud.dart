import 'package:flutter/material.dart';

import '../../game/game_controller.dart';
import '../../services/app_localizations.dart';
import '../../services/app_settings.dart';

class GlobalHud extends StatelessWidget {
  const GlobalHud({super.key, required this.game, required this.settings});

  final GameController game;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final reducedMotion = settings.reducedMotion || MediaQuery.disableAnimationsOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < 360;
    
    return AnimatedBuilder(
      animation: game,
      builder: (context, _) {
        return Container(
          padding: EdgeInsets.fromLTRB(
            isCompact ? 4 : 8,
            isCompact ? 4 : 6,
            isCompact ? 4 : 8,
            MediaQuery.of(context).padding.top + (isCompact ? 4 : 6),
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF063D2C).withValues(alpha: 0.95),
                const Color(0xFF063D2C).withValues(alpha: 0.0),
              ],
            ),
          ),
          child: SafeArea(
            top: false,
            bottom: false,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Brand
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: isCompact ? 6 : 8,
                      vertical: isCompact ? 3 : 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.storefront_rounded,
                          color: const Color(0xFF38B879),
                          size: isCompact ? 14 : 16,
                        ),
                        if (width > 340) ...[
                          const SizedBox(width: 3),
                          Text(
                            'POMARKET',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: isCompact ? 10 : 12,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(width: isCompact ? 4 : (width > 320 ? 6 : 0)),
                  
                  // Level
                  _HudPill(
                    label: 'L${game.storeLevel}',
                    value: '${(game.levelProgress * 100).toInt()}%',
                    color: const Color(0xFF38B879),
                    compact: isCompact,
                    reducedMotion: reducedMotion,
                  ),
                  SizedBox(width: isCompact ? 4 : (width > 320 ? 6 : 0)),
                  
                  // Coins
                  _HudPill(
                    label: loc.coinsShort,
                    value: game.coins.toString(),
                    color: const Color(0xFFF6A623),
                    icon: Icons.monetization_on_rounded,
                    compact: isCompact,
                    reducedMotion: reducedMotion,
                  ),
                  if (width > 340) const SizedBox(width: 3),
                  
                  // Gems
                  if (width > 340)
                    _HudPill(
                      label: loc.gemsShort,
                      value: game.gems.toString(),
                      color: const Color(0xFF8B66D8),
                      icon: Icons.diamond_rounded,
                      compact: isCompact,
                      reducedMotion: reducedMotion,
                    ),
                  
                  // Alert badge for low stock
                  if (game.shelfStock < 3 && game.shelfStock >= 0)
                    _AlertBadge(
                      icon: Icons.warning_amber_rounded,
                      label: loc.lowStock,
                      color: const Color(0xFFE85D75),
                      compact: isCompact,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HudPill extends StatelessWidget {
  const _HudPill({
    required this.label,
    required this.value,
    required this.color,
    this.icon,
    this.compact = false,
    this.reducedMotion = false,
  });

  final String label;
  final String value;
  final Color color;
  final IconData? icon;
  final bool compact;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: compact ? 12 : 14, color: color),
            const SizedBox(width: 3),
          ],
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: compact ? 8 : 9,
                  fontWeight: FontWeight.w600,
                  height: 1.0,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 11 : 13,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AlertBadge extends StatelessWidget {
  const _AlertBadge({
    required this.icon,
    required this.label,
    required this.color,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color, width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 12 : 14, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}