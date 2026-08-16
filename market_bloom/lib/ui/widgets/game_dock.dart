import 'package:flutter/material.dart';

import '../theme/pomarket_design.dart';
import 'game_navigation.dart';

/// Persistent bottom navigation for every screen in the game.
///
/// Replaces the floating hamburger on the market and the side rail on the
/// management screens with one dock, so the same controls sit in the same place
/// everywhere. Secondary areas — including settings — expand in a panel
/// directly above the bar rather than hiding behind a menu.
class GameDock extends StatelessWidget {
  const GameDock({
    super.key,
    required this.primary,
    required this.overflow,
    required this.selected,
    required this.expanded,
    required this.labelFor,
    required this.iconFor,
    required this.hasBadge,
    required this.moreLabel,
    required this.onSelect,
    required this.onToggleMore,
  });

  /// Destinations that always occupy a slot on the bar.
  final List<AppDestination> primary;

  /// Destinations revealed by the trailing "more" slot.
  final List<AppDestination> overflow;

  final AppDestination selected;
  final bool expanded;
  final String Function(AppDestination) labelFor;
  final IconData Function(AppDestination) iconFor;
  final bool Function(AppDestination) hasBadge;
  final String moreLabel;
  final ValueChanged<AppDestination> onSelect;
  final VoidCallback onToggleMore;

  bool get _overflowSelected => overflow.contains(selected);

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reducedMotion
        ? Duration.zero
        : const Duration(milliseconds: 240);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Expanding panel rather than a modal sheet: the secondary areas stay
        // visibly part of the dock instead of becoming a separate destination.
        AnimatedSize(
          duration: duration,
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomCenter,
          child: expanded
              ? _OverflowPanel(
                  destinations: overflow,
                  selected: selected,
                  labelFor: labelFor,
                  iconFor: iconFor,
                  hasBadge: hasBadge,
                  onSelect: onSelect,
                )
              : const SizedBox(width: double.infinity),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [PoDepthColors.forest, PoDepthColors.abyss],
            ),
            border: Border(
              top: BorderSide(color: PoAccent.mintFace.withValues(alpha: 0.22)),
            ),
            boxShadow: [
              BoxShadow(
                color: PoDepthColors.abyss.withValues(alpha: 0.5),
                blurRadius: 18,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Row(
                children: [
                  for (final destination in primary)
                    Expanded(
                      child: _DockSlot(
                        icon: iconFor(destination),
                        label: labelFor(destination),
                        active: destination == selected,
                        badge: hasBadge(destination),
                        onTap: () => onSelect(destination),
                      ),
                    ),
                  Expanded(
                    child: _DockSlot(
                      icon: expanded
                          ? Icons.expand_more_rounded
                          : Icons.grid_view_rounded,
                      label: moreLabel,
                      active: _overflowSelected || expanded,
                      badge: overflow.any(hasBadge),
                      onTap: onToggleMore,
                      semanticExpanded: expanded,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DockSlot extends StatelessWidget {
  const _DockSlot({
    required this.icon,
    required this.label,
    required this.active,
    required this.badge,
    required this.onTap,
    this.semanticExpanded,
  });

  final IconData icon;
  final String label;
  final bool active;
  final bool badge;
  final VoidCallback onTap;
  final bool? semanticExpanded;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reducedMotion
        ? Duration.zero
        : const Duration(milliseconds: 200);

    return Semantics(
      button: true,
      selected: active,
      expanded: semanticExpanded,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedContainer(
                    duration: duration,
                    curve: Curves.easeOutCubic,
                    width: 42,
                    height: 34,
                    decoration: BoxDecoration(
                      gradient: active
                          ? LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                PoAccent.lighten(PoAccent.mintFace),
                                PoAccent.mintFace,
                              ],
                            )
                          : null,
                      color: active ? null : PoDepthColors.glass,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: active
                            ? Colors.white.withValues(alpha: 0.45)
                            : Colors.transparent,
                      ),
                      boxShadow: active
                          ? PoDepth.glow(PoAccent.mintFace, strength: 0.7)
                          : null,
                    ),
                    child: Icon(
                      icon,
                      size: 20,
                      color: active
                          ? PoDepthColors.abyss
                          : Colors.white.withValues(alpha: 0.72),
                    ),
                  ),
                  if (badge)
                    PositionedDirectional(
                      top: -2,
                      end: -2,
                      child: Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(
                          color: PoAccent.coralFace,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: PoDepthColors.abyss,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9,
                  height: 1.1,
                  fontWeight: active ? FontWeight.w900 : FontWeight.w700,
                  color: active
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverflowPanel extends StatelessWidget {
  const _OverflowPanel({
    required this.destinations,
    required this.selected,
    required this.labelFor,
    required this.iconFor,
    required this.hasBadge,
    required this.onSelect,
  });

  final List<AppDestination> destinations;
  final AppDestination selected;
  final String Function(AppDestination) labelFor;
  final IconData Function(AppDestination) iconFor;
  final bool Function(AppDestination) hasBadge;
  final ValueChanged<AppDestination> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [PoDepthColors.canopy, PoDepthColors.deepSea],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: PoAccent.mintFace.withValues(alpha: 0.26)),
        boxShadow: PoDepth.resting(strength: 1.4),
      ),
      child: Row(
        children: [
          for (final destination in destinations)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: _OverflowTile(
                  icon: iconFor(destination),
                  label: labelFor(destination),
                  active: destination == selected,
                  badge: hasBadge(destination),
                  onTap: () => onSelect(destination),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OverflowTile extends StatelessWidget {
  const _OverflowTile({
    required this.icon,
    required this.label,
    required this.active,
    required this.badge,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final bool badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: active
                            ? [
                                PoAccent.lighten(PoAccent.goldFace),
                                PoAccent.goldFace,
                              ]
                            : [
                                Colors.white.withValues(alpha: 0.16),
                                Colors.white.withValues(alpha: 0.06),
                              ],
                      ),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: Colors.white.withValues(
                          alpha: active ? 0.5 : 0.14,
                        ),
                      ),
                      boxShadow: active
                          ? PoDepth.glow(PoAccent.goldFace, strength: 0.6)
                          : null,
                    ),
                    child: Icon(
                      icon,
                      size: 19,
                      color: active ? PoDepthColors.abyss : Colors.white,
                    ),
                  ),
                  if (badge)
                    PositionedDirectional(
                      top: -2,
                      end: -2,
                      child: Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(
                          color: PoAccent.coralFace,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: PoDepthColors.deepSea,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9,
                  height: 1.1,
                  fontWeight: FontWeight.w800,
                  color: Colors.white.withValues(alpha: active ? 1 : 0.78),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
