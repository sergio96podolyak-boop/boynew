import 'package:flutter/material.dart';

import '../theme/po_system.dart';
import 'game_navigation.dart';

/// Persistent bottom navigation for every screen in the game.
///
/// One dock everywhere, so the same control is always in the same place: the
/// market used to hide navigation behind a floating hamburger while the
/// management screens used a side rail. Secondary areas — settings included —
/// expand in a tray directly above the bar instead of hiding behind a menu,
/// which is what "settings should not be three taps deep" actually requires.
///
/// Visual treatment: a floating rounded capsule inset from the screen edges.
/// Edge-to-edge bars read as browser chrome; a floating dock reads as a game.
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
    final duration = PoMotion.respect(context, PoMotion.normal);
    final tier = PoBreak.of(context);
    final inset = tier.isCompact ? 8.0 : 12.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Expanding tray rather than a modal sheet: the secondary areas stay
        // visibly part of the dock instead of becoming a separate destination.
        AnimatedSize(
          duration: duration,
          curve: PoMotion.curve,
          alignment: Alignment.bottomCenter,
          child: expanded
              ? _Measure(
                  child: _OverflowTray(
                    destinations: overflow,
                    selected: selected,
                    labelFor: labelFor,
                    iconFor: iconFor,
                    hasBadge: hasBadge,
                    onSelect: onSelect,
                    inset: inset,
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(inset, 0, inset, inset),
            // Five slots stretched across a 1440px window left enormous gaps
            // between icons; capping the measure keeps the dock a dock at every
            // width rather than a full-bleed bar.
            child: _Measure(
              child: DecoratedBox(
                // Carries the key of the MobileGameNavigation bar it replaces, so
                // callers and tests that look for "the bottom navigation" still
                // find it after the swap.
                key: const ValueKey('mobile-game-navigation'),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFFFFFFF), Color(0xFFF4F9F5)],
                  ),
                  borderRadius: BorderRadius.circular(PoRadius.lg),
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: PoElevate.e3,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 7,
                  ),
                  child: Row(
                    children: [
                      for (final destination in primary)
                        Expanded(
                          child: _DockSlot(
                            key: ValueKey('mobile-nav-${destination.name}'),
                            icon: iconFor(destination),
                            label: labelFor(destination),
                            active: destination == selected,
                            badge: hasBadge(destination),
                            onTap: () => onSelect(destination),
                          ),
                        ),
                      Expanded(
                        child: _DockSlot(
                          key: const ValueKey('mobile-nav-more'),
                          icon: expanded
                              ? Icons.close_rounded
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
          ),
        ),
      ],
    );
  }
}

/// Caps and centres the dock (and its tray) on tablet and desktop widths.
class _Measure extends StatelessWidget {
  const _Measure({required this.child});

  static const maxWidth = 620.0;

  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}

/// One navigation slot.
///
/// The active state is a filled gradient pill with a glow and a bolder label;
/// inactive slots are unfilled with muted ink. Two independent signals (fill and
/// weight) means the current tab is unmistakable even at a glance or in
/// grayscale.
class _DockSlot extends StatefulWidget {
  const _DockSlot({
    super.key,
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
  State<_DockSlot> createState() => _DockSlotState();
}

class _DockSlotState extends State<_DockSlot> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final duration = PoMotion.respect(context, PoMotion.fast);
    final active = widget.active;
    final ink = active ? Colors.white : PoColor.textSecondary;

    return Semantics(
      button: true,
      selected: active,
      expanded: widget.semanticExpanded,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          duration: duration,
          curve: PoMotion.curve,
          scale: _down ? 0.92 : 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedContainer(
                      duration: PoMotion.respect(context, PoMotion.normal),
                      curve: PoMotion.curve,
                      height: 34,
                      width: 46,
                      decoration: BoxDecoration(
                        gradient: active
                            ? LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  PoColor.lighten(PoColor.primaryFace, 0.16),
                                  PoColor.deepen(PoColor.primaryFace, 0.20),
                                ],
                              )
                            : null,
                        color: active ? null : Colors.transparent,
                        borderRadius: BorderRadius.circular(PoRadius.sm),
                        border: Border.all(
                          color: active
                              ? Colors.white.withValues(alpha: 0.5)
                              : Colors.transparent,
                        ),
                        boxShadow: active
                            ? PoElevate.glow(
                                PoColor.primaryFace,
                                strength: 0.75,
                              )
                            : null,
                      ),
                      child: Icon(widget.icon, size: 21, color: ink),
                    ),
                    if (widget.badge)
                      PositionedDirectional(
                        top: -1,
                        end: -1,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: PoColor.danger,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: PoElevate.glow(
                              PoColor.danger,
                              strength: 0.6,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: PoText.caption.copyWith(
                    fontSize: 9.5,
                    fontWeight: active ? FontWeight.w900 : FontWeight.w700,
                    color: active
                        ? PoColor.deepen(PoColor.primaryFace, 0.36)
                        : PoColor.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tray of secondary destinations, revealed above the dock.
class _OverflowTray extends StatelessWidget {
  const _OverflowTray({
    required this.destinations,
    required this.selected,
    required this.labelFor,
    required this.iconFor,
    required this.hasBadge,
    required this.onSelect,
    required this.inset,
  });

  final List<AppDestination> destinations;
  final AppDestination selected;
  final String Function(AppDestination) labelFor;
  final IconData Function(AppDestination) iconFor;
  final bool Function(AppDestination) hasBadge;
  final ValueChanged<AppDestination> onSelect;
  final double inset;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: EdgeInsets.fromLTRB(inset, 0, inset, PoSpace.sm),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFFFFF), Color(0xFFF2F8F4)],
      ),
      borderRadius: BorderRadius.circular(PoRadius.lg),
      border: Border.all(color: Colors.white, width: 1.5),
      boxShadow: PoElevate.e4,
    ),
    child: Row(
      children: [
        for (final destination in destinations)
          Expanded(
            child: _TrayTile(
              icon: iconFor(destination),
              label: labelFor(destination),
              active: destination == selected,
              badge: hasBadge(destination),
              onTap: () => onSelect(destination),
            ),
          ),
      ],
    ),
  );
}

class _TrayTile extends StatelessWidget {
  const _TrayTile({
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
  Widget build(BuildContext context) => PoPressable(
    onTap: onTap,
    radius: PoRadius.sm,
    semanticLabel: label,
    selected: active,
    pressScale: 0.93,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              PoIconBadge(
                icon: icon,
                face: active ? PoColor.goldFace : PoColor.primaryFace,
                size: 38,
                iconSize: 19,
                radius: PoRadius.xs,
                tinted: !active,
              ),
              if (badge)
                PositionedDirectional(
                  top: -1,
                  end: -1,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: PoColor.danger,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
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
            style: PoText.caption.copyWith(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              color: active ? PoColor.ink : PoColor.textSecondary,
            ),
          ),
        ],
      ),
    ),
  );
}
